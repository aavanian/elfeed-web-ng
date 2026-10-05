;;; elfeed-web-ng.el --- web interface to Elfeed -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: AGPL-3.0-or-later
;;
;; Copyright (C) 2024-2026 elfeed-web-ng contributors
;; Based on elfeed-web by Christopher Wellons <wellons@nullprogram.com>
;; Original: https://github.com/skeeto/elfeed (Unlicense)

;; URL: https://github.com/aavanian/elfeed-web-ng
;; Version: 1.0.0
;; Package-Requires: ((simple-httpd "1.5.1") (elfeed "3.2.0") (emacs "29.2"))

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
;; /elfeed/content/<ref>    -- entry content (HTML)
;; /elfeed/tags             -- PUT to modify entry tags
;; /elfeed/feed-update      -- trigger a feed update
;; /elfeed/feed-update-done -- long-poll until feed update completes
;; /elfeed/mark-all-read    -- remove unread from all entries
;; /elfeed/saved-searches   -- configured saved searches
;; /elfeed/annotation/<id>  -- GET/PUT entry annotations (requires elfeed-curate)

;;; Code:

(require 'cl-lib)
(require 'subr-x)
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

(defcustom elfeed-web-ng-limit 512
  "Maximum number of entries to serve at once."
  :group 'elfeed
  :type 'integer)

(defcustom elfeed-web-ng-saved-searches nil
  "List of saved searches for the web interface.
Each element is a plist with :label and :filter keys.
Example: \\='((:label \"Unread\" :filter \"+unread\"))"
  :group 'elfeed
  :type '(repeat (plist :key-type symbol :value-type string)))

(defcustom elfeed-web-ng-allowed-hosts nil
  "Hostnames permitted in the HTTP Host and Origin request headers.

Requests whose Host header names a host outside this list are rejected,
which blocks DNS-rebinding attacks.  Cross-site requests are blocked
separately: a request carrying an Origin header must come from the
same host and port it was sent to.

When nil the allowlist is derived automatically from `httpd-host' (when
it names a specific address) plus the loopback names.  That default
serves the common case of a single private bind address with no
configuration.  Set this to a list of hostname strings to permit
additional names, for example a Tailscale MagicDNS name reached
alongside the raw tailnet IP.  Ports are ignored; list bare hostnames.

Loopback names (including \"[::1]\") are always permitted: they cannot be
the target of a DNS-rebinding attack, since the browser only sends them
when the user genuinely navigated to a loopback address, for example
through an SSH tunnel.  Other services on the same machine are still
kept out by the Origin check."
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

(defvar elfeed-web-ng--data-root
  (expand-file-name "web" (file-name-directory load-file-name))
  "Location of the static Elfeed web data files.")

(defvar elfeed-web-ng--webid-map (make-hash-table :test 'equal)
  "Track the mapping between entries and IDs.")

(defvar elfeed-web-ng--webid-seed
  (let ((items (list (random) (float-time) (emacs-pid) (system-name))))
    (secure-hash 'sha1 (format "%S" items)))
  "Used to make webids less predictable.")

(defvar elfeed-web-ng--version "1.0.0"
  "Version of elfeed-web-ng.")

(defvar elfeed-web-ng--feed-done-waiting ()
  "Clients waiting for feed update completion.")

(defun elfeed-web-ng-make-webid (thing)
  "Compute a unique web ID for THING."
  (let* ((thing-id (prin1-to-string (aref thing 1)))
         (keyed (concat thing-id elfeed-web-ng--webid-seed))
         (hash (base64-encode-string (secure-hash 'sha1 keyed nil nil t)))
         (no-slash (replace-regexp-in-string "/" "-" hash))
         (no-plus (replace-regexp-in-string "\\+" "_" no-slash))
         (webid (substring no-plus 0 12)))
    (setf (gethash webid elfeed-web-ng--webid-map) thing)
    webid))

(defvar elfeed-web-ng--webid-index-stamp nil
  "Database `:last-update' time when the webid map was last fully built.
While it matches the current stamp, a webid absent from
`elfeed-web-ng--webid-map' is known not to exist, so a lookup miss costs a
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
Webids are normally added to `elfeed-web-ng--webid-map' as things are
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
      (setq elfeed-web-ng--webid-index-stamp stamp))))

(defun elfeed-web-ng-lookup (webid)
  "Lookup a thing by its WEBID, or nil when no entry or feed matches."
  (when (elfeed-web-ng--valid-webid-p webid)
    (or (gethash webid elfeed-web-ng--webid-map)
        (progn
          (elfeed-web-ng--ensure-webid-index)
          (gethash webid elfeed-web-ng--webid-map)))))

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

(defun elfeed-web-ng--valid-tags-p (tags)
  "Return non-nil if TAGS, a decoded JSON value, is absent or valid.
A valid value is an array whose every element satisfies
`elfeed-web-ng--valid-tag-p'."
  (or (null tags)
      (and (vectorp tags)
           (cl-every #'elfeed-web-ng--valid-tag-p tags))))

(defun elfeed-web-ng--valid-ref-p (ref)
  "Return non-nil if REF is a well-formed content reference.
Elfeed content refs are SHA-1 hex digests.  Rejecting anything else
keeps a crafted ref from escaping the content store via path components
such as slashes or \"..\" when it is concatenated into a filename."
  (and (stringp ref)
       (let ((case-fold-search nil))
         (string-match-p "\\`[0-9a-f]\\{40\\}\\'" ref))))

(defconst elfeed-web-ng--max-body-size 65536
  "Largest request body, in bytes, that the API endpoints accept.
The client only ever sends small JSON objects: tag changes and
annotations.  simple-httpd itself reads a body of any length, so the
bound is applied before the body is decoded or parsed.")

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

(defun elfeed-web-ng--hostname (host)
  "Return the hostname in HOST in a comparable form, or nil.
HOST is a Host header value, an allowlist entry or a URL host.  The
port, letter case and IPv6 brackets are dropped, so \"[::1]:8082\" and
\"::1\" compare equal."
  (when-let* ((name (elfeed-web-ng--strip-port host)))
    (downcase (string-trim name "\\[" "\\]"))))

(defun elfeed-web-ng--host-port (host)
  "Return the port number in the Host header value HOST, or nil."
  (and host
       (string-match "\\(?:\\`[^:]*\\|\\]\\):\\([0-9]+\\)\\'" host)
       (string-to-number (match-string 1 host))))

(defun elfeed-web-ng--effective-allowed-hosts ()
  "Return the normalized list of permitted hostnames.
Combines the loopback names with `elfeed-web-ng-allowed-hosts', or, when
that is nil, with `httpd-host' if it names a specific address."
  (let ((extra (if elfeed-web-ng-allowed-hosts
                   elfeed-web-ng-allowed-hosts
                 (and (stringp httpd-host)
                      (not (member httpd-host '("0.0.0.0" "::")))
                      (list httpd-host)))))
    (mapcar #'elfeed-web-ng--hostname
            (append elfeed-web-ng--loopback-hosts extra))))

(defun elfeed-web-ng--host-allowed-p (host)
  "Return non-nil if the Host header HOST is permitted."
  (and-let* ((name (elfeed-web-ng--hostname host)))
    (and (member name (elfeed-web-ng--effective-allowed-hosts)) t)))

(defconst elfeed-web-ng--default-ports '(("http" . 80) ("https" . 443))
  "Port implied by each scheme a browser sends in an Origin header.
Looked up here rather than with `url-port', which loads the url-http
library and its proxy setup on first use.")

(defun elfeed-web-ng--origin-allowed-p (origin host)
  "Return non-nil if ORIGIN is absent or names the server at HOST.
ORIGIN and HOST are the values of the request headers of those names.
A missing Origin is permitted; the Host check guards those requests.
Otherwise the Origin must name the very host and port the request was
addressed to: matching the hostname alone would admit any other web
service on the same machine, such as a dev server on localhost, as a
source of cross-site requests.  A port missing from HOST is the
default port of the Origin's scheme.  The scheme itself is not
compared, so a TLS-terminating proxy in front of the server still
works.  An opaque \"null\" origin is rejected."
  (or (null origin)
      (and-let* (((not (equal origin "null")))
                 (url (ignore-errors (url-generic-parse-url origin)))
                 (origin-name (elfeed-web-ng--hostname (url-host url)))
                 ((not (string-empty-p origin-name))))
        (let ((default-port (cdr (assoc (url-type url)
                                        elfeed-web-ng--default-ports))))
          (and (equal origin-name (elfeed-web-ng--hostname host))
               (equal (or (url-portspec url) default-port)
                      (or (elfeed-web-ng--host-port host) default-port)))))))

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

(defun elfeed-web-ng--send-json-error (status &optional message)
  "Send STATUS as a JSON error response.
MESSAGE, when non-nil, is the error payload in place of the numeric STATUS."
  (princ (json-encode (list :error (or message status))))
  (httpd-send-header t "application/json" status))

(defmacro elfeed-web-ng--with (&rest body)
  "Execute BODY for a permitted, enabled request, else send an error.
Rejects the request when its Host header falls outside
`elfeed-web-ng-allowed-hosts' or its Origin header names another
server (see `elfeed-web-ng--origin-allowed-p'), sends 403 when the interface is
disabled, and 413 when the request body exceeds
`elfeed-web-ng--max-body-size'."
  (declare (indent 0))
  `(cond
    ((not (elfeed-web-ng--host-allowed-p (elfeed-web-ng--header "Host")))
     (elfeed-web-ng--reject "Host" (elfeed-web-ng--header "Host")))
    ((not (elfeed-web-ng--origin-allowed-p (elfeed-web-ng--header "Origin")
                                           (elfeed-web-ng--header "Host")))
     (elfeed-web-ng--reject "Origin" (elfeed-web-ng--header "Origin")))
    ((not elfeed-web-ng-enabled)
     (elfeed-web-ng--send-json-error 403))
    ((> (length (cadr (assoc "Content" httpd-request)))
        elfeed-web-ng--max-body-size)
     (elfeed-web-ng--send-json-error 413))
    (t ,@body)))

(defmacro elfeed-web-ng--with-method (method &rest body)
  "Execute BODY when the request method is METHOD, else send a 405.
Requiring an explicit method keeps a bare GET -- an image tag or a link
on a malicious page -- from triggering a state change.

Expands into code that reads the free variable `httpd-request', so it
must be used inside a `defservlet*' body where that binding is in scope."
  (declare (indent 1))
  `(if (equal (caar httpd-request) ,method)
       (progn ,@body)
     (elfeed-web-ng--send-json-error 405)))

(defun elfeed-web-ng--request-json ()
  "Return the request body parsed as a JSON object, or nil.
The object is an alist with string keys: reading keys as symbols would
intern every key a client sends, growing the obarray without bound.
Nil stands for a missing body, invalid JSON, or a JSON value that is
not a non-empty object.  Reads the free variable `httpd-request', so it
must be called inside a `defservlet*' body."
  (when-let* ((content (cadr (assoc "Content" httpd-request)))
              (json (ignore-errors
                      (let ((json-key-type 'string)
                            (json-object-type 'alist))
                        (json-read-from-string
                         (decode-coding-string content 'utf-8))))))
    (and (consp json) json)))

(defun elfeed-web-ng--json-field (json key)
  "Return the value of KEY, a string, in the JSON object alist JSON."
  (cdr (assoc key json)))

(defservlet* elfeed/content/:ref text/html ()
  "Serve content-addressable content at REF."
  (elfeed-web-ng--with
    (if-let* ((content (and (elfeed-web-ng--valid-ref-p ref)
                            (elfeed-deref (elfeed-ref--create :id ref)))))
        (progn
          ;; The reader parses this and applies its own styling, so only
          ;; the encoding is declared here.
          (princ (concat "<meta charset=\"utf-8\">" content))
          ;; The content is arbitrary feed HTML.  Served top-level (not just
          ;; inside the app's sandboxed iframe) it would otherwise run scripts
          ;; in this origin; the sandbox directive disables that, and
          ;; 'unsafe-inline' keeps the feed's own inline styles working.  No
          ;; Referer tells the hosts of its images where the reader lives.
          (httpd-send-header t "text/html" 200
                             :Content-Security-Policy
                             "sandbox allow-popups; default-src 'self'; style-src 'unsafe-inline'"
                             :Referrer-Policy "no-referrer"))
      (elfeed-web-ng--send-json-error 404))))

(defun elfeed-web-ng--search-filter (query)
  "Parse the search QUERY into a filter capped at `elfeed-web-ng-limit'.
A nil QUERY, from a request without one, matches every entry.  The cap
is applied after parsing because the filter syntax lets a \"#N\" in the
query set the limit, and the last one wins: prepending the configured
limit to the query would let the client override it."
  (let* ((filter (elfeed-search-parse-filter (or query "")))
         (limit (plist-get filter :limit)))
    (plist-put filter :limit (min (or limit elfeed-web-ng-limit)
                                  elfeed-web-ng-limit))))

(defservlet* elfeed/search application/json (q)
  "Perform a search operation with Q and return the results."
  (elfeed-web-ng--with
    (let ((results ())
          (filter (elfeed-web-ng--search-filter q))
          (count 0))
      (with-elfeed-db-visit (entry feed)
        (when (elfeed-search-filter filter entry feed count)
          (push entry results)
          (cl-incf count)))
      (princ
       (json-encode
        (vconcat
         (mapcar #'elfeed-web-ng-for-json (nreverse results))))))))

(defun elfeed-web-ng--notify-feed-done ()
  "Respond to all clients waiting for feed update completion."
  (while elfeed-web-ng--feed-done-waiting
    (let ((proc (pop elfeed-web-ng--feed-done-waiting)))
      (ignore-errors
        (with-httpd-buffer proc "application/json"
          (princ (json-encode '(:status "done"))))))))

(defservlet* elfeed/mark-all-read application/json ()
  "Marks all entries in the database as read (quick-and-dirty).
Only POST requests are accepted; this keeps a bare GET (an image tag or
a link on a malicious page) from clearing unread state."
  (elfeed-web-ng--with
    (elfeed-web-ng--with-method "POST"
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
  (elfeed-web-ng--with
    (elfeed-web-ng--with-method "PUT"
      (let* ((json (elfeed-web-ng--request-json))
             (add (elfeed-web-ng--json-field json "add"))
             (remove (elfeed-web-ng--json-field json "remove"))
             (webids (elfeed-web-ng--json-field json "entries")))
        (if (not (and json
                      (elfeed-web-ng--valid-tags-p add)
                      (elfeed-web-ng--valid-tags-p remove)
                      (or (null webids) (vectorp webids))))
            (elfeed-web-ng--send-json-error 400)
          (let* ((webids (append webids nil))
                 (entries (mapcar #'elfeed-web-ng-lookup webids)))
            (if (memq nil entries)
                (elfeed-web-ng--send-json-error 404)
              (cl-loop for webid in webids
                       for entry in entries
                       do (apply #'elfeed-tag entry (mapcar #'intern add))
                       do (apply #'elfeed-untag entry (mapcar #'intern remove))
                       collect (cons webid (elfeed-entry-tags entry)) into result
                       finally (princ (if result (json-encode result) "{}"))))))))))

(defservlet* elfeed/api application/json ()
  "Return the server version and its optional features.
Only features that depend on the setup are listed; everything else the
frontend uses is always available."
  (elfeed-web-ng--with
    (princ (json-encode
            (list :server "elfeed-web-ng"
                  :version elfeed-web-ng--version
                  :features (if (featurep 'elfeed-curate)
                                ["annotations"]
                              []))))))

(defservlet* elfeed/saved-searches application/json ()
  "Return the configured saved searches."
  (elfeed-web-ng--with
    (princ (json-encode
            (vconcat
             (mapcar (lambda (s)
                       (list :label (plist-get s :label)
                             :filter (plist-get s :filter)))
                     elfeed-web-ng-saved-searches))))))

(defservlet* elfeed/annotation/:webid application/json ()
  "Set the annotation of an entry from a PUT JSON body.
The body is an object whose \"annotation\" is a string, or null to
clear it.  Requires elfeed-curate to be loaded; answers 501 otherwise.
Annotations are read from the search results, not from here."
  (elfeed-web-ng--with
    (elfeed-web-ng--with-method "PUT"
      (let* ((entry (elfeed-web-ng-lookup webid))
             (json (elfeed-web-ng--request-json))
             (annotation (elfeed-web-ng--json-field json "annotation")))
        (cond
         ((null entry)
          (elfeed-web-ng--send-json-error 404 "not found"))
         ((not (featurep 'elfeed-curate))
          (elfeed-web-ng--send-json-error 501 "elfeed-curate not available"))
         ((null json)
          (elfeed-web-ng--send-json-error 400 "invalid JSON"))
         ((not (or (null annotation) (stringp annotation)))
          (elfeed-web-ng--send-json-error 400 "annotation must be a string"))
         (t
          (elfeed-curate-set-entry-annotation entry (or annotation ""))
          (princ (json-encode
                  (list :webid webid
                        :annotation (elfeed-curate-get-entry-annotation entry))))))))))

(defvar elfeed-web-ng--feed-done-timer nil
  "Active completion-poll timer, or nil when no poll chain is running.
Guards against stacking one polling chain per `feed-update' request.")

(defun elfeed-web-ng--check-queue-done ()
  "Poll `elfeed-queue-count-total' until all feeds are fetched,
then notify waiting clients."
  (if (zerop (elfeed-queue-count-total))
      (progn
        (setq elfeed-web-ng--feed-done-timer nil)
        (elfeed-web-ng--notify-feed-done))
    (setq elfeed-web-ng--feed-done-timer
          (run-at-time 1 nil #'elfeed-web-ng--check-queue-done))))

(defun elfeed-web-ng--monitor-feed-update ()
  "Start a completion-poll chain unless one is already running."
  (unless elfeed-web-ng--feed-done-timer
    (elfeed-web-ng--check-queue-done)))

(defservlet* elfeed/feed-update application/json ()
  "Trigger an elfeed feed update and start monitoring for completion.
Only POST requests are accepted; this keeps a bare GET (an image tag or
a link on a malicious page) from triggering a feed fetch.

A fetch is launched only when none is already in flight: pressing the
button again while feeds are still arriving would add load without
yielding new data.  Either way a single completion-poll chain is kept
running so `feed-update-done' clients are notified."
  (elfeed-web-ng--with
    (elfeed-web-ng--with-method "POST"
      (when (zerop (elfeed-queue-count-total))
        (elfeed-update))
      (elfeed-web-ng--monitor-feed-update)
      (princ (json-encode '(:status "updating"))))))

(defservlet* elfeed/feed-update-done application/json ()
  "Long-poll endpoint that responds when a feed update completes.
If the update already finished before this request arrived, respond
immediately rather than parking the process with nothing to drain it.
Otherwise park it and make sure a completion-poll chain is running: the
update may have been started from Emacs rather than by `feed-update'."
  (elfeed-web-ng--with
    (if (zerop (elfeed-queue-count-total))
        (princ (json-encode '(:status "done")))
      (push (httpd-discard-buffer) elfeed-web-ng--feed-done-waiting)
      (elfeed-web-ng--monitor-feed-update))))

(defun elfeed-web-ng--serve-static (path request)
  "Serve PATH under `elfeed-web-ng--data-root' for REQUEST.
Like `httpd-serve-root', but hands `httpd-send-file' the target of a
symbolic link rather than the link.  `simple-httpd' derives both ETag and
Last-Modified from `file-attributes', which describes a link itself, so a
package whose static files are symlinks into a checkout -- what
`straight.el' and friends build -- would serve a validator frozen at link
creation and clients would revalidate their way into a stale build
forever."
  (let* ((file (httpd-gen-path path elfeed-web-ng--data-root))
         (status (httpd-status file)))
    (cond
     ((/= status 200)
      (httpd-error t status))
     ((file-directory-p file)
      (httpd-send-directory t file path))
     (t
      (httpd-send-file t (file-truename file) request)))))

(defservlet elfeed text/plain (uri-path _ request)
  "Serve static files from `elfeed-web-ng--data-root'."
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
                 (expand-file-name "index.html" elfeed-web-ng--data-root))
                ;; The reader's about:srcdoc frame inherits this page's
                ;; referrer policy, so it covers feed images and embeds.
                (httpd-send-header t "text/html" 200
                                   :Cache-Control "no-cache, no-store, must-revalidate"
                                   :Referrer-Policy "no-referrer"))
            (elfeed-web-ng--serve-static path request))))))))

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
  (setq elfeed-web-ng-enabled t))

(defun elfeed-web-ng-stop ()
  "Stop the Elfeed web interface server.
This stops the underlying simple-httpd server, which is shared across
all packages that use it (e.g., impatient-mode, skewer-mode)."
  (interactive)
  (setq elfeed-web-ng-enabled nil)
  (httpd-stop))

(provide 'elfeed-web-ng)

;;; elfeed-web-ng.el ends here
