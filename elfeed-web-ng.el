;;; elfeed-web-ng.el --- web interface to Elfeed -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: AGPL-3.0-or-later
;;
;; Copyright (C) 2024-2026 elfeed-web-ng contributors
;; Based on elfeed-web by Christopher Wellons <wellons@nullprogram.com>
;; Original: https://github.com/skeeto/elfeed (Unlicense)

;; URL: https://github.com/aavanian/elfeed-web-ng

;;; Commentary:

;; Web interface for Elfeed with a RESTful JSON API.  Entries and feeds
;; are identified by short alphanumeric "webids" to avoid encoding issues
;; with arbitrary RSS/Atom IDs.
;;
;; Endpoints:
;;
;; /elfeed/<path>           -- static files (HTML, JS, CSS)
;; /elfeed/api              -- server capabilities
;; /elfeed/search?q=FILTER  -- search entries
;; /elfeed/things/<webid>   -- entry or feed as JSON
;; /elfeed/content/<ref>    -- entry content (HTML)
;; /elfeed/tags             -- PUT to modify entry tags
;; /elfeed/feed-update      -- trigger a feed update
;; /elfeed/feed-update-done -- long-poll until feed update completes
;; /elfeed/mark-all-read    -- remove unread from all entries
;; /elfeed/saved-searches   -- configured saved searches
;; /elfeed/annotation/<id>  -- GET/PUT entry annotations (requires elfeed-curate)

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'simple-httpd)
(require 'elfeed-db)
(require 'elfeed-search)

(defcustom elfeed-web-ng-enabled nil
  "If true, serve a web interface Elfeed with simple-httpd."
  :group 'elfeed
  :type 'boolean)

(defvar elfeed-web-ng-limit 512
  "Maximum number of entries to serve at once.")

(defcustom elfeed-web-ng-saved-searches nil
  "List of saved searches for the web interface.
Each element is a plist with :label and :filter keys.
Example: \\='((:label \"Unread\" :filter \"+unread\"))"
  :group 'elfeed
  :type '(repeat (plist :key-type symbol :value-type string)))

(defvar elfeed-web-ng-data-root
  (expand-file-name "web" (file-name-directory load-file-name))
  "Location of the static Elfeed web data files.")

(defvar elfeed-web-ng-webid-map (make-hash-table :test 'equal)
  "Track the mapping between entries and IDs.")

(defvar elfeed-web-ng-webid-seed
  (let ((items (list (random) (float-time) (emacs-pid) (system-name))))
    (secure-hash 'sha1 (format "%S" items)))
  "Used to make webids less predictable.")

(defun elfeed-web-ng-make-webid (thing)
  "Compute a unique web ID for THING."
  (let* ((thing-id (prin1-to-string (aref thing 1)))
         (keyed (concat thing-id elfeed-web-ng-webid-seed))
         (hash (base64-encode-string (secure-hash 'sha1 keyed nil nil t)))
         (no-slash (replace-regexp-in-string "/" "-" hash))
         (no-plus (replace-regexp-in-string "\\+" "_" no-slash))
         (webid (substring no-plus 0 8)))
    (setf (gethash webid elfeed-web-ng-webid-map) thing)
    webid))

(defun elfeed-web-ng-lookup (webid)
  "Lookup a thing by its WEBID."
  (let ((thing (gethash webid elfeed-web-ng-webid-map)))
    (if thing
        thing
      (or (with-elfeed-db-visit (entry _)
            (when (string= webid (elfeed-web-ng-make-webid entry))
              (setf (gethash webid elfeed-web-ng-webid-map)
                    (elfeed-db-return entry))))
          (cl-loop for feed hash-values of elfeed-db-feeds
                   when (string= (elfeed-web-ng-make-webid feed) webid)
                   return (setf (gethash webid elfeed-web-ng-webid-map) feed))))))

(defun elfeed-web-ng-for-json (thing)
  "Prepare THING for JSON serialization."
  (cl-etypecase thing
    (elfeed-entry
     (list :webid        (elfeed-web-ng-make-webid thing)
           :title        (elfeed-entry-title thing)
           :link         (elfeed-entry-link thing)
           :date         (* 1000 (elfeed-entry-date thing))
           :content      (let ((content (elfeed-entry-content thing)))
                           (and content (elfeed-ref-id content)))
           :contentType  (elfeed-entry-content-type thing)
           :enclosures   (or (mapcar #'car (elfeed-entry-enclosures thing)) [])
           :tags         (or (elfeed-entry-tags thing) [])
           :annotation   (when (featurep 'elfeed-curate)
                           (elfeed-curate-get-entry-annotation thing))
           :feed         (elfeed-web-ng-for-json (elfeed-entry-feed thing))))
    (elfeed-feed
     (list :webid  (elfeed-web-ng-make-webid thing)
           :url    (elfeed-feed-url thing)
           :title  (elfeed-feed-title thing)
           :author (elfeed-feed-author thing)))))

(defmacro with-elfeed-web-ng (&rest body)
  "Only execute BODY if `elfeed-web-ng-enabled' is true."
  (declare (indent 0))
  `(if (not elfeed-web-ng-enabled)
       (progn
         (princ (json-encode '(:error 403)))
         (httpd-send-header t "application/json" 403))
     ,@body))

(defservlet* elfeed/things/:webid application/json ()
  "Return a requested thing (entry or feed)."
  (with-elfeed-web-ng
    (princ (json-encode (elfeed-web-ng-for-json (elfeed-web-ng-lookup webid))))))

(defservlet* elfeed/content/:ref text/html ()
  "Serve content-addressable content at REF."
  (with-elfeed-web-ng
    (let ((content (elfeed-deref (elfeed-ref--create :id ref))))
      (if content
          (princ (concat
                  "<html><head>"
                  "<meta charset=\"utf-8\">"
                  "<style>"
                  "body { background: #fdf6e3; color: #657b83; }"
                  "a { color: #268bd2; }"
                  "img { max-width: 100%; height: auto; }"
                  "@media (prefers-color-scheme: dark) {"
                  "  body { background: #002b36; color: #839496; }"
                  "}"
                  "</style></head><body>"
                  content
                  "</body></html>"))
        (princ (json-encode '(:error 404)))
        (httpd-send-header t "application/json" 404)))))

(defservlet* elfeed/search application/json (q)
  "Perform a search operation with Q and return the results."
  (with-elfeed-web-ng
    (let* ((results ())
           (modified-q (format "#%d %s" elfeed-web-ng-limit q))
           (filter (elfeed-search-parse-filter modified-q))
           (count 0))
      (with-elfeed-db-visit (entry feed)
        (when (elfeed-search-filter filter entry feed count)
          (push entry results)
          (cl-incf count)))
      (princ
       (json-encode
        (cl-coerce
         (mapcar #'elfeed-web-ng-for-json (nreverse results)) 'vector))))))

(defvar elfeed-web-ng-feed-done-waiting ()
  "Clients waiting for feed update completion.")

(defun elfeed-web-ng--notify-feed-done ()
  "Respond to all clients waiting for feed update completion."
  (while elfeed-web-ng-feed-done-waiting
    (let ((proc (pop elfeed-web-ng-feed-done-waiting)))
      (ignore-errors
        (with-httpd-buffer proc "application/json"
          (princ (json-encode '(:status "done"))))))))

(defservlet* elfeed/mark-all-read application/json ()
  "Marks all entries in the database as read (quick-and-dirty)."
  (with-elfeed-web-ng
    (with-elfeed-db-visit (e _)
      (elfeed-untag e 'unread))
    (princ (json-encode t))))

(defservlet* elfeed/tags application/json ()
  "Endpoint for adding and removing tags on zero or more entries.
Only PUT requests are accepted, and the content must be a JSON
object with any of these properties:

  add     : array of tags to be added
  remove  : array of tags to be removed
  entries : array of web IDs for entries to be modified

The current set of tags for each entry will be returned."
  (with-elfeed-web-ng
    (let* ((request (caar httpd-request))
           (content (decode-coding-string
                     (cadr (assoc "Content" httpd-request)) 'utf-8))
           (json (ignore-errors (json-read-from-string content)))
           (add (cdr (assoc 'add json)))
           (remove (cdr (assoc 'remove json)))
           (webids (cdr (assoc 'entries json)))
           (entries (cl-map 'list #'elfeed-web-ng-lookup webids))
           (status
            (cond
             ((not (equal request "PUT")) 405)
             ((null json) 400)
             ((cl-some #'null entries) 404)
             (t 200))))
      (if (not (eql status 200))
          (progn
            (princ (json-encode `(:error ,status)))
            (httpd-send-header t "application/json" status))
        (cl-loop for entry in entries
                 for webid = (elfeed-web-ng-make-webid entry)
                 do (apply #'elfeed-tag entry (cl-map 'list #'intern add))
                 do (apply #'elfeed-untag entry (cl-map 'list #'intern remove))
                 collect (cons webid (elfeed-entry-tags entry)) into result
                 finally (princ (if result (json-encode result) "{}")))))))

(defvar elfeed-web-ng-version "1.0.0"
  "Version of elfeed-web-ng.")

(defservlet* elfeed/api application/json ()
  "Return server capabilities for feature negotiation."
  (with-elfeed-web-ng
    (princ (json-encode
            (list :server "elfeed-web-ng"
                  :version elfeed-web-ng-version
                  :features (vconcat
                             (delq nil
                                   (list "saved-searches"
                                         "tags"
                                         "feed-update-done"
                                         (when (featurep 'elfeed-curate)
                                           "annotations")))))))))

(defservlet* elfeed/saved-searches application/json ()
  "Return the configured saved searches."
  (with-elfeed-web-ng
    (princ (json-encode
            (vconcat
             (mapcar (lambda (s)
                       (list :label (plist-get s :label)
                             :filter (plist-get s :filter)))
                     elfeed-web-ng-saved-searches))))))

(defservlet* elfeed/annotation/:webid application/json ()
  "GET or PUT an annotation on an entry.
Requires elfeed-curate to be loaded; returns 501 otherwise for PUT,
and empty string for GET."
  (with-elfeed-web-ng
    (let* ((method (caar httpd-request))
           (entry (elfeed-web-ng-lookup webid)))
      (cond
       ((null entry)
        (princ (json-encode '(:error "not found")))
        (httpd-send-header t "application/json" 404))
       ((equal method "GET")
        (let ((annotation (if (featurep 'elfeed-curate)
                              (elfeed-curate-get-entry-annotation entry)
                            "")))
          (princ (json-encode (list :webid webid :annotation annotation)))))
       ((equal method "PUT")
        (if (not (featurep 'elfeed-curate))
            (progn
              (princ (json-encode '(:error "elfeed-curate not available")))
              (httpd-send-header t "application/json" 501))
          (let* ((content (decode-coding-string
                           (cadr (assoc "Content" httpd-request)) 'utf-8))
                 (json-data (ignore-errors (json-read-from-string content)))
                 (annotation (cdr (assoc 'annotation json-data))))
            (if (null json-data)
                (progn
                  (princ (json-encode '(:error "invalid JSON")))
                  (httpd-send-header t "application/json" 400))
              (elfeed-curate-set-entry-annotation entry (or annotation ""))
              (princ (json-encode (list :webid webid
                                        :annotation (elfeed-curate-get-entry-annotation entry))))))))
       (t
        (princ (json-encode '(:error "method not allowed")))
        (httpd-send-header t "application/json" 405))))))

(defun elfeed-web-ng--check-queue-done ()
  "Poll `elfeed-queue-count-total' until all feeds are fetched,
then notify waiting clients."
  (if (zerop (elfeed-queue-count-total))
      (elfeed-web-ng--notify-feed-done)
    (run-at-time 1 nil #'elfeed-web-ng--check-queue-done)))

(defservlet* elfeed/feed-update application/json ()
  "Trigger an elfeed feed update and start monitoring for completion."
  (with-elfeed-web-ng
    (elfeed-update)
    (elfeed-web-ng--check-queue-done)
    (princ (json-encode '(:status "updating")))))

(defservlet* elfeed/feed-update-done application/json ()
  "Long-poll endpoint that responds when a feed update completes.
If the update already finished before this request arrived, respond
immediately rather than parking the process with nothing to drain it."
  (with-elfeed-web-ng
    (if (zerop (elfeed-queue-count-total))
        (princ (json-encode '(:status "done")))
      (push (httpd-discard-buffer) elfeed-web-ng-feed-done-waiting))))

(defservlet elfeed text/plain (uri-path _ request)
  "Serve static files from `elfeed-web-ng-data-root'."
  (if (not elfeed-web-ng-enabled)
      (insert "Elfeed web interface is disabled.\n"
              "Set `elfeed-web-ng-enabled' to true to enable it.")
    (let ((base "/elfeed/"))
      (if (< (length uri-path) (length base))
          (httpd-redirect t base)
        (let ((path (substring uri-path (1- (length base)))))
          (if (or (string= path "/") (string= path "/index.html"))
              (progn
                (insert-file-contents
                 (expand-file-name "index.html" elfeed-web-ng-data-root))
                (httpd-send-header t "text/html" 200
                                   :Cache-Control "no-cache, no-store, must-revalidate"))
            (httpd-serve-root t elfeed-web-ng-data-root path request)))))))

(defun httpd/favicon.ico (proc &rest _)
  "Redirect /favicon.ico to /elfeed/favicon.ico."
  (httpd-redirect proc "/elfeed/icons/favicon_dark.svg"))


;;;###autoload
(defun elfeed-web-ng-start ()
  "Start the Elfeed web interface server."
  (interactive)
  (httpd-start)
  (setf elfeed-web-ng-enabled t))

(defun elfeed-web-ng-stop ()
  "Stop the Elfeed web interface server.
This stops the underlying simple-httpd server, which is shared across
all packages that use it (e.g., impatient-mode, skewer-mode)."
  (interactive)
  (setf elfeed-web-ng-enabled nil)
  (httpd-stop))

(provide 'elfeed-web-ng)

;;; elfeed-web-ng.el ends here
