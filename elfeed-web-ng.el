;;; elfeed-web-ng.el --- web interface to Elfeed -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: AGPL-3.0-or-later
;;
;; Copyright (C) 2024-2026 elfeed-web-ng contributors
;; Based on elfeed-web by Christopher Wellons <wellons@nullprogram.com>
;; Original: https://github.com/skeeto/elfeed (Unlicense)

;; URL: https://github.com/aavanian/elfeed-web-ng
;; Version: 1.0.0
;; Package-Requires: ((simple-httpd "1.5.1") (elfeed "3.2.0") (emacs "25.1"))

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
(require 'url-parse)
(require 'simple-httpd)
(require 'elfeed-db)
(require 'elfeed-search)

;; Optional integration with elfeed-curate for entry annotations.
(declare-function elfeed-curate-get-entry-annotation "ext:elfeed-curate" (entry))
(declare-function elfeed-curate-set-entry-annotation "ext:elfeed-curate" (entry annotation))

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

(defcustom elfeed-web-ng-allowed-hosts nil
  "Hostnames permitted in the HTTP Host and Origin request headers.

Requests whose Host header names a host outside this list are rejected,
which blocks DNS-rebinding attacks; the same list gates the Origin
header on cross-site requests, which blocks CSRF.

When nil the allowlist is derived automatically from `httpd-host' (when
it names a specific address) plus the loopback names.  That default
serves the common case of a single private bind address with no
configuration.  Set this to a list of hostname strings to permit
additional names, for example a Tailscale MagicDNS name reached
alongside the raw tailnet IP.  Ports are ignored; list bare hostnames.

Loopback names are always permitted: they cannot be the target of a
DNS-rebinding attack, since the browser only sends them when the user
genuinely navigated to a loopback address."
  :group 'elfeed
  :type '(choice (const :tag "Auto (derive from `httpd-host')" nil)
                 (repeat string)))

(defcustom elfeed-web-ng-allow-public-bind nil
  "When non-nil, suppress the warning about binding to all interfaces.
`elfeed-web-ng-start' warns when the server listens on every network
interface with no authentication.  Set this to acknowledge a deliberate
public bind (for example behind an authenticating reverse proxy)."
  :group 'elfeed
  :type 'boolean)

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
         (webid (substring no-plus 0 12)))
    (setf (gethash webid elfeed-web-ng-webid-map) thing)
    webid))

(defvar elfeed-web-ng--webid-index-stamp nil
  "Database `:last-update' time when the webid map was last fully built.
While it matches the current stamp, a webid absent from
`elfeed-web-ng-webid-map' is known not to exist, so a lookup miss costs a
hash probe rather than a rescan of the whole database.")

(defun elfeed-web-ng--valid-webid-p (webid)
  "Return non-nil if WEBID has the shape `elfeed-web-ng-make-webid' makes.
Rejecting other strings turns a malformed request into a cheap miss
instead of a trigger for the database scan below."
  (and (stringp webid)
       (let ((case-fold-search nil))
         (string-match-p "\\`[A-Za-z0-9_-]\\{12\\}\\'" webid))))

(defun elfeed-web-ng--ensure-webid-index ()
  "Register every entry's and feed's webid, at most once per DB revision.
Webids are normally added to `elfeed-web-ng-webid-map' as things are
serialized, but a client may hold one the server has not computed since
its last restart.  Building the whole map on the first such miss lets it
and every later miss resolve by hash lookup, rather than rescanning and
re-hashing the database on each request."
  (let ((stamp (plist-get elfeed-db :last-update)))
    (unless (equal stamp elfeed-web-ng--webid-index-stamp)
      (with-elfeed-db-visit (entry _)
        (elfeed-web-ng-make-webid entry))
      (cl-loop for feed hash-values of elfeed-db-feeds
               do (elfeed-web-ng-make-webid feed))
      (setf elfeed-web-ng--webid-index-stamp stamp))))

(defun elfeed-web-ng-lookup (webid)
  "Lookup a thing by its WEBID, or nil when no entry or feed matches."
  (when (elfeed-web-ng--valid-webid-p webid)
    (or (gethash webid elfeed-web-ng-webid-map)
        (progn
          (elfeed-web-ng--ensure-webid-index)
          (gethash webid elfeed-web-ng-webid-map)))))

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

(defun elfeed-web-ng--valid-tag-p (tag)
  "Return non-nil if TAG is a valid elfeed tag string.
Rejects strings that are too long or contain characters outside the
allowed set, preventing unbounded obarray growth via `intern'."
  (and (stringp tag)
       (<= (length tag) 64)
       (string-match-p "\\`[-a-zA-Z0-9_★]+\\'" tag)))

(defun elfeed-web-ng--valid-ref-p (ref)
  "Return non-nil if REF is a well-formed content reference.
Elfeed content refs are SHA-1 hex digests.  Rejecting anything else
keeps a crafted ref from escaping the content store via path components
such as slashes or \"..\" when it is concatenated into a filename."
  (and (stringp ref)
       (let ((case-fold-search nil))
         (string-match-p "\\`[0-9a-f]\\{40\\}\\'" ref))))

(defconst elfeed-web-ng--loopback-hosts
  '("localhost" "127.0.0.1" "::1" "ip6-localhost")
  "Loopback names always accepted in the Host and Origin headers.")

(defun elfeed-web-ng--header (name &optional request)
  "Return the value of request header NAME, case-insensitively, or nil.
REQUEST is the parsed request alist; it defaults to `httpd-request',
which `defservlet*' binds but plain `defservlet' does not."
  (cadr (assoc-string name (or request httpd-request) t)))

(defun elfeed-web-ng--strip-port (host)
  "Return the hostname part of HOST, dropping any \":port\" suffix.
Handles bracketed IPv6 literals such as \"[::1]:8080\"."
  (cond
   ((null host) nil)
   ((string-prefix-p "[" host)
    (if (string-match "\\`\\(\\[[^]]*\\]\\)" host) (match-string 1 host) host))
   ((string-match "\\`\\([^:]*\\):[0-9]+\\'" host) (match-string 1 host))
   (t host)))

(defun elfeed-web-ng--effective-allowed-hosts ()
  "Return the normalized list of permitted hostnames.
Combines the loopback names with `elfeed-web-ng-allowed-hosts', or, when
that is nil, with `httpd-host' if it names a specific address."
  (let ((extra (if elfeed-web-ng-allowed-hosts
                   elfeed-web-ng-allowed-hosts
                 (and (stringp httpd-host)
                      (not (member httpd-host '("0.0.0.0" "::")))
                      (list httpd-host)))))
    (mapcar (lambda (h) (downcase (elfeed-web-ng--strip-port h)))
            (append elfeed-web-ng--loopback-hosts extra))))

(defun elfeed-web-ng--host-allowed-p (host)
  "Return non-nil if the Host header HOST is permitted."
  (let ((name (and host (downcase (elfeed-web-ng--strip-port host)))))
    (and name (member name (elfeed-web-ng--effective-allowed-hosts)) t)))

(defun elfeed-web-ng--origin-allowed-p (origin)
  "Return non-nil if ORIGIN is absent or names a permitted host.
A missing Origin is permitted; the Host check guards those requests.  An
opaque \"null\" origin, or one naming a host outside the allowlist, is
rejected so cross-site requests cannot drive state-changing endpoints."
  (or (null origin)
      (let ((host (and (not (equal origin "null"))
                       (ignore-errors
                         (url-host (url-generic-parse-url origin))))))
        (and host
             (member (downcase host) (elfeed-web-ng--effective-allowed-hosts))
             t))))

(defun elfeed-web-ng--reject (header value)
  "Send a generic 403 for a request rejected by the HEADER allowlist.
VALUE is the offending header value.  It is recorded in the *httpd* log
next to the request entry (which carries the client address) rather than
returned, so the response reveals neither it nor the allowlist.  The
logged key names what VALUE is -- the host the request was addressed to,
or the cross-site origin -- not the client that sent it."
  (httpd-log
   (list 'elfeed-web-ng-rejected
         (list (if (equal header "Host") 'requested-host 'origin) value)
         '(reason "not in elfeed-web-ng-allowed-hosts")))
  (princ (concat
          "403 Forbidden\n\n"
          "This request was rejected because its " header " header is not\n"
          "in the allowlist.  If you are running this service, add the\n"
          "hostname to `elfeed-web-ng-allowed-hosts'.  See the README.\n"))
  (httpd-send-header t "text/plain" 403))

(defmacro with-elfeed-web-ng (&rest body)
  "Execute BODY for a permitted, enabled request, else send an error.
Rejects the request when its Host or Origin header falls outside
`elfeed-web-ng-allowed-hosts', and sends 403 when the interface is
disabled."
  (declare (indent 0))
  `(cond
    ((not (elfeed-web-ng--host-allowed-p (elfeed-web-ng--header "Host")))
     (elfeed-web-ng--reject "Host" (elfeed-web-ng--header "Host")))
    ((not (elfeed-web-ng--origin-allowed-p (elfeed-web-ng--header "Origin")))
     (elfeed-web-ng--reject "Origin" (elfeed-web-ng--header "Origin")))
    ((not elfeed-web-ng-enabled)
     (princ (json-encode '(:error 403)))
     (httpd-send-header t "application/json" 403))
    (t ,@body)))

(defservlet* elfeed/things/:webid application/json ()
  "Return a requested thing (entry or feed)."
  (with-elfeed-web-ng
    (princ (json-encode (elfeed-web-ng-for-json (elfeed-web-ng-lookup webid))))))

(defservlet* elfeed/content/:ref text/html ()
  "Serve content-addressable content at REF."
  (with-elfeed-web-ng
    (let ((content (and (elfeed-web-ng--valid-ref-p ref)
                        (elfeed-deref (elfeed-ref--create :id ref)))))
      (if content
          (progn
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
            ;; The content is arbitrary feed HTML.  Served top-level (not just
            ;; inside the app's sandboxed iframe) it would otherwise run scripts
            ;; in this origin; the sandbox directive disables that, and
            ;; 'unsafe-inline' keeps the inline <style> above working.
            (httpd-send-header t "text/html" 200
                               :Content-Security-Policy
                               "sandbox allow-popups; default-src 'self'; style-src 'unsafe-inline'"))
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
  "Marks all entries in the database as read (quick-and-dirty).
Only POST requests are accepted; this keeps a bare GET (an image tag or
a link on a malicious page) from clearing unread state."
  (with-elfeed-web-ng
    (if (not (equal (caar httpd-request) "POST"))
        (progn
          (princ (json-encode '(:error 405)))
          (httpd-send-header t "application/json" 405))
      (with-elfeed-db-visit (e _)
        (elfeed-untag e 'unread))
      (princ (json-encode t)))))

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
           (add (append (cdr (assoc 'add json)) nil))
           (remove (append (cdr (assoc 'remove json)) nil))
           (webids (cdr (assoc 'entries json)))
           (entries (cl-map 'list #'elfeed-web-ng-lookup webids))
           (tags-valid (and (cl-every #'elfeed-web-ng--valid-tag-p add)
                            (cl-every #'elfeed-web-ng--valid-tag-p remove)))
           (status
            (cond
             ((not (equal request "PUT")) 405)
             ((null json) 400)
             ((not tags-valid) 400)
             ((cl-some #'null entries) 404)
             (t 200))))
      (if (not (eql status 200))
          (progn
            (princ (json-encode `(:error ,status)))
            (httpd-send-header t "application/json" status))
        (cl-loop for entry in entries
                 for webid = (elfeed-web-ng-make-webid entry)
                 do (apply #'elfeed-tag entry (mapcar #'intern add))
                 do (apply #'elfeed-untag entry (mapcar #'intern remove))
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
  "Trigger an elfeed feed update and start monitoring for completion.
Only POST requests are accepted; this keeps a bare GET (an image tag or
a link on a malicious page) from triggering a feed fetch."
  (with-elfeed-web-ng
    (if (not (equal (caar httpd-request) "POST"))
        (progn
          (princ (json-encode '(:error 405)))
          (httpd-send-header t "application/json" 405))
      (elfeed-update)
      (elfeed-web-ng--check-queue-done)
      (princ (json-encode '(:status "updating"))))))

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
  (cond
   ((not (elfeed-web-ng--host-allowed-p (elfeed-web-ng--header "Host" request)))
    (elfeed-web-ng--reject "Host" (elfeed-web-ng--header "Host" request)))
   ((not elfeed-web-ng-enabled)
    (insert "Elfeed web interface is disabled.\n"
            "Set `elfeed-web-ng-enabled' to true to enable it."))
   (t
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
            (httpd-serve-root t elfeed-web-ng-data-root path request))))))))

(defun httpd/favicon.ico (proc &rest _)
  "Redirect /favicon.ico to /elfeed/favicon.ico."
  (httpd-redirect proc "/elfeed/icons/favicon_dark.svg"))


(defun elfeed-web-ng--warn-public-bind ()
  "Warn when serving on all interfaces with no authentication.
Suppressed by `elfeed-web-ng-allow-public-bind'."
  (when (and (not elfeed-web-ng-allow-public-bind)
             (or (null httpd-host)
                 (member httpd-host '("0.0.0.0" "::"))))
    (display-warning
     'elfeed-web-ng
     (concat
      "Serving on all network interfaces (`httpd-host' is unset or "
      "wildcard) with no authentication.\n"
      "Anyone who can reach this machine can read and modify your feeds.\n"
      "Pin `httpd-host' to a private address (loopback or a tailnet IP), "
      "or set `elfeed-web-ng-allow-public-bind' to silence this warning. "
      "See the README.")
     :warning)))

;;;###autoload
(defun elfeed-web-ng-start ()
  "Start the Elfeed web interface server."
  (interactive)
  (elfeed-web-ng--warn-public-bind)
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
