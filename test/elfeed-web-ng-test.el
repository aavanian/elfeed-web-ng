;;; elfeed-web-ng-test.el --- Tests for elfeed-web-ng -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for the elfeed-web-ng server.  `./check.sh' runs them; to
;; run them alone, put elfeed and simple-httpd on the load path:
;;
;;   emacs --batch -L "$ELFEED_DIR" -L "$HTTPD_DIR" -L . \
;;         -l test/elfeed-web-ng-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'elfeed-web-ng)

;;; Host header parsing.

(ert-deftest elfeed-web-ng-test-strip-port ()
  (should (null (elfeed-web-ng--strip-port nil)))
  (should (equal "host" (elfeed-web-ng--strip-port "host")))
  (should (equal "host" (elfeed-web-ng--strip-port "host:8080")))
  (should (equal "127.0.0.1" (elfeed-web-ng--strip-port "127.0.0.1:80")))
  (should (equal "[::1]" (elfeed-web-ng--strip-port "[::1]:8080")))
  (should (equal "[::1]" (elfeed-web-ng--strip-port "[::1]"))))

(ert-deftest elfeed-web-ng-test-hostname ()
  "Hostnames compare without port, case or IPv6 brackets."
  (should (null (elfeed-web-ng--hostname nil)))
  (should (equal "feeds.example.net" (elfeed-web-ng--hostname "Feeds.Example.Net:80")))
  (should (equal "::1" (elfeed-web-ng--hostname "[::1]:8080")))
  (should (equal "::1" (elfeed-web-ng--hostname "[::1]")))
  (should (equal "::1" (elfeed-web-ng--hostname "::1"))))

;;; Effective allowlist.

(ert-deftest elfeed-web-ng-test-effective-hosts-explicit ()
  "An explicit list is used, with loopback always appended."
  (let ((elfeed-web-ng-allowed-hosts '("feeds.example.net"))
        (httpd-host "203.0.113.7"))
    (let ((hosts (elfeed-web-ng--effective-allowed-hosts)))
      (should (member "feeds.example.net" hosts))
      (should (member "localhost" hosts))
      ;; httpd-host is ignored once an explicit list is given.
      (should-not (member "203.0.113.7" hosts)))))

(ert-deftest elfeed-web-ng-test-effective-hosts-derived ()
  "With no explicit list, a specific `httpd-host' is derived."
  (let ((elfeed-web-ng-allowed-hosts nil)
        (httpd-host "100.64.0.1"))
    (should (member "100.64.0.1" (elfeed-web-ng--effective-allowed-hosts)))))

(ert-deftest elfeed-web-ng-test-effective-hosts-wildcard-bind ()
  "A wildcard or unset `httpd-host' derives only loopback."
  (dolist (bind '(nil "0.0.0.0" "::"))
    (let ((elfeed-web-ng-allowed-hosts nil)
          (httpd-host bind))
      (let ((hosts (elfeed-web-ng--effective-allowed-hosts)))
        (should (member "localhost" hosts))
        (should-not (member "0.0.0.0" hosts))))))

;;; Host check.

(ert-deftest elfeed-web-ng-test-host-allowed ()
  (let ((elfeed-web-ng-allowed-hosts '("feeds.example.net"))
        (httpd-host nil))
    (should (elfeed-web-ng--host-allowed-p "feeds.example.net"))
    (should (elfeed-web-ng--host-allowed-p "feeds.example.net:8080"))
    ;; Hostnames are case-insensitive.
    (should (elfeed-web-ng--host-allowed-p "Feeds.Example.Net"))
    ;; Loopback is always allowed.
    (should (elfeed-web-ng--host-allowed-p "localhost:8080"))
    (should (elfeed-web-ng--host-allowed-p "[::1]:8080"))
    ;; A rebound origin keeps its own Host header.
    (should-not (elfeed-web-ng--host-allowed-p "evil.example.com"))
    (should-not (elfeed-web-ng--host-allowed-p nil))))

;;; Origin check.

(ert-deftest elfeed-web-ng-test-origin-allowed ()
  "An Origin must name the host and port the request was addressed to."
  ;; A missing Origin defers to the Host check.
  (should (elfeed-web-ng--origin-allowed-p nil "feeds.example.net"))
  ;; Same origin, with the port explicit or implied by the scheme.
  (should (elfeed-web-ng--origin-allowed-p "http://feeds.example.net:8080"
                                           "feeds.example.net:8080"))
  (should (elfeed-web-ng--origin-allowed-p "http://Feeds.Example.Net:8080"
                                           "feeds.example.net:8080"))
  (should (elfeed-web-ng--origin-allowed-p "https://feeds.example.net"
                                           "feeds.example.net"))
  (should (elfeed-web-ng--origin-allowed-p "http://feeds.example.net"
                                           "feeds.example.net:80"))
  (should (elfeed-web-ng--origin-allowed-p "http://[::1]:8082" "[::1]:8082"))
  ;; Another service on the same machine is another origin.
  (should-not (elfeed-web-ng--origin-allowed-p "http://localhost:3000"
                                               "localhost:8082"))
  (should-not (elfeed-web-ng--origin-allowed-p "http://localhost:3000"
                                               "127.0.0.1:8082"))
  (should-not (elfeed-web-ng--origin-allowed-p "http://feeds.example.net"
                                               "feeds.example.net:8080"))
  ;; Cross-site, opaque and malformed origins are rejected.
  (should-not (elfeed-web-ng--origin-allowed-p "http://evil.example.com:8080"
                                               "feeds.example.net:8080"))
  (should-not (elfeed-web-ng--origin-allowed-p "null" "feeds.example.net"))
  (should-not (elfeed-web-ng--origin-allowed-p "garbage" "feeds.example.net"))
  (should-not (elfeed-web-ng--origin-allowed-p "http://feeds.example.net" nil)))

;;; Content ref validation.

(ert-deftest elfeed-web-ng-test-valid-ref ()
  "Only a bare SHA-1 hex digest is accepted as a content ref."
  ;; A real elfeed ref: 40 lowercase hex characters.
  (should (elfeed-web-ng--valid-ref-p (make-string 40 ?a)))
  (should (elfeed-web-ng--valid-ref-p
           "da39a3ee5e6b4b0d3255bfef95601890afd80709"))
  ;; Wrong length.
  (should-not (elfeed-web-ng--valid-ref-p (make-string 39 ?a)))
  (should-not (elfeed-web-ng--valid-ref-p (make-string 41 ?a)))
  (should-not (elfeed-web-ng--valid-ref-p ""))
  ;; Outside the hex alphabet: uppercase, and the digits a SHA-1 never holds.
  (should-not (elfeed-web-ng--valid-ref-p (make-string 40 ?A)))
  (should-not (elfeed-web-ng--valid-ref-p (concat (make-string 39 ?a) "g")))
  ;; Path components that would escape the content store once concatenated
  ;; into a filename, including the double-encoded form that survives
  ;; simple-httpd's split-then-decode handling.
  (should-not (elfeed-web-ng--valid-ref-p "../../../etc/passwd"))
  (should-not (elfeed-web-ng--valid-ref-p "..%2f..%2fetc%2fpasswd"))
  (should-not (elfeed-web-ng--valid-ref-p ".."))
  (should-not (elfeed-web-ng--valid-ref-p nil)))

;;; Webid validation.

(ert-deftest elfeed-web-ng-test-valid-webid ()
  "Only a 12-character webid in the base64url-derived alphabet is accepted."
  ;; The alphabet `elfeed-web-ng-make-webid' emits: base64 with / and +
  ;; rewritten to - and _, truncated to 12 characters.
  (should (elfeed-web-ng--valid-webid-p "aB3-_xyz0123"))
  (should (elfeed-web-ng--valid-webid-p (make-string 12 ?a)))
  ;; Wrong length.
  (should-not (elfeed-web-ng--valid-webid-p (make-string 11 ?a)))
  (should-not (elfeed-web-ng--valid-webid-p (make-string 13 ?a)))
  (should-not (elfeed-web-ng--valid-webid-p ""))
  ;; Characters outside the alphabet, including the path-bearing ones a
  ;; lookup must never feed to the database scan.
  (should-not (elfeed-web-ng--valid-webid-p "aaaaaa/aaaaa"))
  (should-not (elfeed-web-ng--valid-webid-p "aaaaaa.aaaaa"))
  (should-not (elfeed-web-ng--valid-webid-p "aaaaaa+aaaaa"))
  (should-not (elfeed-web-ng--valid-webid-p nil)))

;;; Static file serving.

(ert-deftest elfeed-web-ng-test-serve-static-resolves-symlinks ()
  "A symlinked asset is served by its target, not by the link.
`simple-httpd' builds the ETag and Last-Modified from `file-attributes',
which describes the link itself, so serving the link would pin a
validator to the link's own mtime and never invalidate a client cache."
  (let* ((dir (make-temp-file "elfeed-web-ng-test" t))
         (target (expand-file-name "real.css" dir))
         (link (expand-file-name "link.css" dir))
         (elfeed-web-ng--data-root dir)
         (served nil))
    (unwind-protect
        (progn
          (with-temp-file target (insert "body{}"))
          (make-symbolic-link target link)
          (cl-letf (((symbol-function 'httpd-send-file)
                     (lambda (_proc path &optional _req) (setq served path))))
            (elfeed-web-ng--serve-static "/link.css" nil))
          (should (equal (file-truename target) served))
          (should-not (equal link served)))
      (delete-directory dir t))))

;;; Request harness.

(defmacro elfeed-web-ng-test--with-db (&rest body)
  "Run BODY against a fresh, empty elfeed database in a temporary directory.
The webid map and index stamp are reset too, so webids computed in one
test cannot resolve in another."
  (declare (indent 0))
  `(let* ((elfeed-db nil)
          (elfeed-db-feeds nil)
          (elfeed-db-entries nil)
          (elfeed-db-index nil)
          (elfeed-db-directory (make-temp-file "elfeed-web-ng-db" t))
          (elfeed-new-entry-hook nil)
          (elfeed-db-update-hook nil)
          (elfeed-web-ng--webid-map (make-hash-table :test 'equal))
          (elfeed-web-ng--webid-index-stamp nil))
     (unwind-protect
         (progn ,@body)
       (delete-directory elfeed-db-directory t))))

(cl-defun elfeed-web-ng-test--add-entry
    (&key (id "1") (title "Title") (tags (list 'unread)) (date 1000) content)
  "Add an entry with ID, TITLE, TAGS, DATE and CONTENT to the database.
All entries belong to one feed.  Return the stored entry."
  (let* ((feed (elfeed-db-get-feed "https://example.com/feed"))
         (entry (elfeed-entry--create
                 :id (cons "example.com" id)
                 :title title
                 :link (concat "https://example.com/" id)
                 :date date
                 :tags tags
                 :feed-id (elfeed-feed-id feed)
                 :content (and content (elfeed-ref content)))))
    (setf (elfeed-feed-url feed) "https://example.com/feed"
          (elfeed-feed-title feed) "Example")
    (elfeed-db-add (list entry))
    (elfeed-db-get-entry (elfeed-entry-id entry))))

(defmacro elfeed-web-ng-test--with-server (&rest body)
  "Run BODY with the interface enabled and bound to 127.0.0.1."
  (declare (indent 0))
  `(let ((elfeed-web-ng-enabled t)
         (elfeed-web-ng-allowed-hosts nil)
         (httpd-host "127.0.0.1")
         (httpd-log-buffer nil))
     ,@body))

(cl-defun elfeed-web-ng-test--request
    (method uri &key (host "127.0.0.1:8082") origin body)
  "Dispatch a METHOD request for URI to its servlet, as simple-httpd does.
HOST and ORIGIN are the request headers of those names; nil omits them.
BODY is the request content.  Return the response as a plist with
:status, :mime, :headers (a keyword plist) and :body.  An error escaping
the servlet is reported as status 500, which is what the server sends."
  (let* ((request `((,method ,uri "HTTP/1.1")
                    ,@(and host `(("Host" ,host)))
                    ,@(and origin `(("Origin" ,origin)))
                    ,@(and body `(("Content" ,(encode-coding-string body 'utf-8))))))
         (parsed (httpd-parse-uri uri))
         (servlet (httpd-get-servlet (car parsed)))
         (response nil))
    (cl-letf (((symbol-function 'httpd-send-header)
               (lambda (_proc mime status &rest headers)
                 (setq httpd--header-sent t
                       response (list :status status :mime mime
                                      :headers headers
                                      :body (buffer-string))))))
      (condition-case nil
          (funcall servlet 'elfeed-web-ng-test-proc
                   (car parsed) (cadr parsed) request)
        (error (setq response (list :status 500)))))
    response))

(defun elfeed-web-ng-test--status (&rest args)
  "Return the status of the request that ARGS describe.
ARGS are those of `elfeed-web-ng-test--request'."
  (plist-get (apply #'elfeed-web-ng-test--request args) :status))

(defun elfeed-web-ng-test--json (response)
  "Parse the body of RESPONSE as JSON, with objects as alists."
  (json-read-from-string (plist-get response :body)))

(defconst elfeed-web-ng-test--guarded-requests
  '(("GET" "/elfeed/")
    ("GET" "/elfeed/index.html")
    ("GET" "/elfeed/manifest.json")
    ("GET" "/elfeed/api")
    ("GET" "/elfeed/search?q=")
    ("GET" "/elfeed/content/da39a3ee5e6b4b0d3255bfef95601890afd80709")
    ("GET" "/elfeed/saved-searches")
    ("GET" "/elfeed/feed-update-done")
    ("PUT" "/elfeed/tags")
    ("PUT" "/elfeed/annotation/aaaaaaaaaaaa")
    ("POST" "/elfeed/mark-all-read")
    ("POST" "/elfeed/feed-update"))
  "One request for every guarded servlet, static files included.")

(defconst elfeed-web-ng-test--state-changing-requests
  '(("PUT" "/elfeed/tags")
    ("PUT" "/elfeed/annotation/aaaaaaaaaaaa")
    ("POST" "/elfeed/mark-all-read")
    ("POST" "/elfeed/feed-update"))
  "One request for every servlet that changes state.")

(defmacro elfeed-web-ng-test--with-feed-update-stubs (&rest body)
  "Run BODY with feed fetching stubbed out and an empty fetch queue."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'elfeed-update) #'ignore)
             ((symbol-function 'elfeed-queue-count-total) (lambda () 0)))
     ,@body))

(defmacro elfeed-web-ng-test--with-curate (&rest body)
  "Run BODY with a stand-in for elfeed-curate.
Annotations live in the entry's meta, and setting a non-string signals,
as the real package does."
  (declare (indent 0))
  ;; `featurep' ignores a let-binding of `features', so provide the
  ;; feature for real and withdraw it afterwards.
  `(let ((provided (featurep 'elfeed-curate)))
     (unwind-protect
         (cl-letf (((symbol-function 'elfeed-curate-get-entry-annotation)
                    (lambda (entry) (or (elfeed-meta entry :test-annotation) "")))
                   ((symbol-function 'elfeed-curate-set-entry-annotation)
                    (lambda (entry annotation)
                      (cl-check-type annotation string)
                      (setf (elfeed-meta entry :test-annotation) annotation))))
           (provide 'elfeed-curate)
           ,@body)
       (unless provided
         (setq features (delq 'elfeed-curate features))))))

;;; Request guards.

(ert-deftest elfeed-web-ng-test-guard-host ()
  "Every servlet rejects a Host outside the allowlist."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (elfeed-web-ng-test--with-feed-update-stubs
        (dolist (req elfeed-web-ng-test--guarded-requests)
          (let ((response (elfeed-web-ng-test--request
                           (car req) (cadr req) :host "evil.example.com")))
            (should (equal (list req 403)
                           (list req (plist-get response :status))))
            (should (string-prefix-p "403 Forbidden"
                                     (plist-get response :body)))))))))

(ert-deftest elfeed-web-ng-test-guard-missing-host ()
  "Every servlet rejects a request with no Host header."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (elfeed-web-ng-test--with-feed-update-stubs
        (dolist (req elfeed-web-ng-test--guarded-requests)
          (should (equal (list req 403)
                         (list req (elfeed-web-ng-test--status
                                    (car req) (cadr req) :host nil)))))))))

(ert-deftest elfeed-web-ng-test-guard-origin ()
  "Every state-changing servlet rejects a cross-site or opaque Origin."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (elfeed-web-ng-test--with-feed-update-stubs
        (dolist (req elfeed-web-ng-test--state-changing-requests)
          (dolist (origin '("http://evil.example.com" "null"))
            (should (equal (list req origin 403)
                           (list req origin
                                 (elfeed-web-ng-test--status
                                  (car req) (cadr req)
                                  :origin origin :body "{}"))))))))))

(ert-deftest elfeed-web-ng-test-guard-local-cross-origin ()
  "Another web service on the same machine cannot drive the API.
Covers both a loopback bind and a tailnet bind, where the loopback
names stay in the Host allowlist."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (elfeed-web-ng-test--with-feed-update-stubs
        (dolist (bind '("127.0.0.1" "100.64.0.1"))
          (let ((httpd-host bind)
                (host (concat bind ":8082")))
            (dolist (req elfeed-web-ng-test--state-changing-requests)
              (should (equal (list bind req 403)
                             (list bind req
                                   (elfeed-web-ng-test--status
                                    (car req) (cadr req) :host host
                                    :origin "http://localhost:3000"
                                    :body "{}")))))
            (should (equal 200 (elfeed-web-ng-test--status
                                "POST" "/elfeed/mark-all-read" :host host
                                :origin (concat "http://" host))))))))))

(ert-deftest elfeed-web-ng-test-guard-disabled ()
  "A disabled interface serves no API and no app."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (elfeed-web-ng-test--with-feed-update-stubs
        (let ((elfeed-web-ng-enabled nil))
          (dolist (req elfeed-web-ng-test--guarded-requests)
            (let ((response (elfeed-web-ng-test--request (car req) (cadr req))))
              (if (eq 'httpd/elfeed
                      (httpd-get-servlet (car (httpd-parse-uri (cadr req)))))
                  ;; Static files answer with an explanation instead.
                  (should (equal (list req t)
                                 (list req (and (string-match-p
                                                 "disabled"
                                                 (plist-get response :body))
                                                t))))
                (should (equal (list req 403)
                               (list req (plist-get response :status))))))))))))

(ert-deftest elfeed-web-ng-test-guard-method ()
  "State-changing endpoints refuse GET, even for an existing entry."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (elfeed-web-ng-test--with-feed-update-stubs
        (elfeed-web-ng-test--with-curate
          (let ((webid (elfeed-web-ng-make-webid (elfeed-web-ng-test--add-entry))))
            (dolist (uri (list "/elfeed/mark-all-read" "/elfeed/feed-update"
                               "/elfeed/tags"
                               (concat "/elfeed/annotation/" webid)))
              (should (equal (list uri 405)
                             (list uri (elfeed-web-ng-test--status "GET" uri)))))))))))

(ert-deftest elfeed-web-ng-test-no-things-endpoint ()
  "Entries are only served through search; there is no per-thing endpoint."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (let ((webid (elfeed-web-ng-make-webid (elfeed-web-ng-test--add-entry))))
        (should (equal 404 (elfeed-web-ng-test--status
                            "GET" (concat "/elfeed/things/" webid))))))))

(ert-deftest elfeed-web-ng-test-content-csp ()
  "Entry content is served with a CSP that sandboxes it."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (let* ((entry (elfeed-web-ng-test--add-entry :content "<p>hello</p>"))
             (ref (elfeed-ref-id (elfeed-entry-content entry)))
             (response (elfeed-web-ng-test--request
                        "GET" (concat "/elfeed/content/" ref)))
             (csp (plist-get (plist-get response :headers)
                             :Content-Security-Policy)))
        (should (equal 200 (plist-get response :status)))
        (should (string-match-p "<p>hello</p>" (plist-get response :body)))
        (should (string-match-p "\\`sandbox allow-popups;" csp))))))

(ert-deftest elfeed-web-ng-test-content-unstyled ()
  "Entry content is served as-is, declared UTF-8; the reader styles it."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (let* ((entry (elfeed-web-ng-test--add-entry :content "<p>hé</p>"))
             (ref (elfeed-ref-id (elfeed-entry-content entry))))
        (should (equal "<meta charset=\"utf-8\"><p>hé</p>"
                       (plist-get (elfeed-web-ng-test--request
                                   "GET" (concat "/elfeed/content/" ref))
                                  :body)))))))

(ert-deftest elfeed-web-ng-test-no-referrer ()
  "Pages that can load feed content forbid sending a Referer.
The reader shows feed HTML in an about:srcdoc frame, which inherits the
app page's referrer policy, so the app shell must carry it too."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (let* ((entry (elfeed-web-ng-test--add-entry :content "<img src=x>"))
             (ref (elfeed-ref-id (elfeed-entry-content entry))))
        (dolist (uri (list "/elfeed/" "/elfeed/index.html"
                           (concat "/elfeed/content/" ref)))
          (let ((response (elfeed-web-ng-test--request "GET" uri)))
            (should (equal (list uri 200 "no-referrer")
                           (list uri (plist-get response :status)
                                 (plist-get (plist-get response :headers)
                                            :Referrer-Policy))))))))))

(ert-deftest elfeed-web-ng-test-same-origin-request-passes ()
  "A same-origin state change passes the guards and takes effect."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (let ((entry (elfeed-web-ng-test--add-entry)))
        (should (equal 200 (elfeed-web-ng-test--status
                            "POST" "/elfeed/mark-all-read"
                            :origin "http://127.0.0.1:8082")))
        (should-not (memq 'unread (elfeed-entry-tags entry)))))))

;;; Webid generation and lookup.

(defmacro elfeed-web-ng-test--counting-webids (counter &rest body)
  "Run BODY, counting calls to `elfeed-web-ng-make-webid' in COUNTER."
  (declare (indent 1))
  (let ((original (make-symbol "original")))
    `(let ((,original (symbol-function 'elfeed-web-ng-make-webid)))
       (cl-letf (((symbol-function 'elfeed-web-ng-make-webid)
                  (lambda (thing)
                    (cl-incf ,counter)
                    (funcall ,original thing))))
         ,@body))))

(ert-deftest elfeed-web-ng-test-webid-is-valid ()
  "Every webid the server makes passes its own validator."
  (elfeed-web-ng-test--with-db
    (dotimes (i 50)
      (let ((entry (elfeed-web-ng-test--add-entry :id (number-to-string i))))
        (should (elfeed-web-ng--valid-webid-p
                 (elfeed-web-ng-make-webid entry)))))))

(ert-deftest elfeed-web-ng-test-lookup-unseen-webid ()
  "A webid the server has not computed since startup still resolves."
  (elfeed-web-ng-test--with-db
    (let* ((entry (elfeed-web-ng-test--add-entry))
           (webid (elfeed-web-ng-make-webid entry))
           (feed-webid (elfeed-web-ng-make-webid (elfeed-entry-feed entry))))
      (clrhash elfeed-web-ng--webid-map)
      (should (eq entry (elfeed-web-ng-lookup webid)))
      (should (eq (elfeed-entry-feed entry)
                  (elfeed-web-ng-lookup feed-webid))))))

(ert-deftest elfeed-web-ng-test-lookup-miss-scans-once-per-revision ()
  "Repeated misses rescan the database only after it changes."
  (elfeed-web-ng-test--with-db
    (elfeed-web-ng-test--add-entry :id "1")
    (let ((calls 0))
      (elfeed-web-ng-test--counting-webids calls
        (should-not (elfeed-web-ng-lookup "aaaaaaaaaaaa"))
        (should (< 0 calls))
        (setq calls 0)
        (should-not (elfeed-web-ng-lookup "aaaaaaaaaaaa"))
        (should (= 0 calls))
        ;; Adding an entry moves the database's :last-update stamp.
        (let ((entry (elfeed-web-ng-test--add-entry :id "2")))
          (should-not (elfeed-web-ng-lookup "aaaaaaaaaaaa"))
          (should (< 0 calls))
          (should (gethash (elfeed-web-ng-make-webid entry)
                           elfeed-web-ng--webid-map)))))))

(ert-deftest elfeed-web-ng-test-lookup-rejects-malformed-webid ()
  "A malformed webid misses without scanning the database."
  (elfeed-web-ng-test--with-db
    (elfeed-web-ng-test--add-entry)
    (let ((calls 0))
      (elfeed-web-ng-test--counting-webids calls
        (should-not (elfeed-web-ng-lookup "../etc"))
        (should (= 0 calls))))))

;;; Tag updates.

(ert-deftest elfeed-web-ng-test-valid-tag ()
  "Tags are short words of letters, digits, - and _, plus the star."
  (should (elfeed-web-ng--valid-tag-p "unread"))
  (should (elfeed-web-ng--valid-tag-p "to_source-2"))
  (should (elfeed-web-ng--valid-tag-p "★"))
  (should (elfeed-web-ng--valid-tag-p (make-string 64 ?a)))
  (should-not (elfeed-web-ng--valid-tag-p (make-string 65 ?a)))
  (should-not (elfeed-web-ng--valid-tag-p ""))
  (should-not (elfeed-web-ng--valid-tag-p "two words"))
  (should-not (elfeed-web-ng--valid-tag-p "a/b"))
  (should-not (elfeed-web-ng--valid-tag-p 'unread))
  (should-not (elfeed-web-ng--valid-tag-p 5)))

(defun elfeed-web-ng-test--put-tags (body)
  "PUT BODY to /elfeed/tags and return the response."
  (elfeed-web-ng-test--request "PUT" "/elfeed/tags" :body body))

(ert-deftest elfeed-web-ng-test-tags-rejects-malformed-requests ()
  "Each malformed tag request gets its own 4xx status, never a 500."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (let ((webid (elfeed-web-ng-make-webid (elfeed-web-ng-test--add-entry))))
        (dolist (case
                 `((nil . 400)
                   ("" . 400)
                   ("not json" . 400)
                   ("[1, 2]" . 400)
                   ("{\"entries\": 5}" . 400)
                   ("{\"entries\": \"aaaaaaaaaaaa\"}" . 400)
                   (,(format "{\"add\": \"unread\", \"entries\": [%S]}" webid) . 400)
                   (,(format "{\"add\": [\"a b\"], \"entries\": [%S]}" webid) . 400)
                   (,(format "{\"remove\": [5], \"entries\": [%S]}" webid) . 400)
                   ("{\"add\": [\"x\"], \"entries\": [\"aaaaaaaaaaaa\"]}" . 404)
                   ("{\"add\": [\"x\"], \"entries\": [5]}" . 404)))
          (should (equal case
                         (cons (car case)
                               (plist-get (elfeed-web-ng-test--put-tags (car case))
                                          :status)))))))))

(ert-deftest elfeed-web-ng-test-tags-updates-entries ()
  "A valid tag request applies the change and returns each entry's tags."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (let* ((entry (elfeed-web-ng-test--add-entry))
             (webid (elfeed-web-ng-make-webid entry))
             (response (elfeed-web-ng-test--put-tags
                        (format "{\"add\": [\"★\"], \"remove\": [\"unread\"], \"entries\": [%S]}"
                                webid))))
        (should (equal 200 (plist-get response :status)))
        (should (equal (list '★) (elfeed-entry-tags entry)))
        (should (equal `((,(intern webid) . ["★"]))
                       (elfeed-web-ng-test--json response)))))))

;;; Feed updates.

(defvar elfeed-web-ng-test--queue 0
  "Length of the stand-in feed fetch queue.")

(defvar elfeed-web-ng-test--scheduled nil
  "Functions scheduled with `run-at-time', most recent first.")

(defvar elfeed-web-ng-test--updates 0
  "Number of times `elfeed-update' was called.")

(defmacro elfeed-web-ng-test--with-fetch-queue (&rest body)
  "Run BODY against a stand-in fetch queue and timer list.
The queue length is `elfeed-web-ng-test--queue'; timers are recorded in
`elfeed-web-ng-test--scheduled' instead of running, and `elfeed-update'
calls are counted in `elfeed-web-ng-test--updates'."
  (declare (indent 0))
  `(let ((elfeed-web-ng-test--queue 0)
         (elfeed-web-ng-test--scheduled nil)
         (elfeed-web-ng-test--updates 0)
         (elfeed-web-ng--feed-done-timer nil)
         (elfeed-web-ng--feed-done-waiting nil))
     (cl-letf (((symbol-function 'elfeed-queue-count-total)
                (lambda () elfeed-web-ng-test--queue))
               ((symbol-function 'elfeed-update)
                (lambda () (cl-incf elfeed-web-ng-test--updates)))
               ((symbol-function 'run-at-time)
                (lambda (_time _repeat function &rest _args)
                  (push function elfeed-web-ng-test--scheduled)
                  (list 'test-timer function))))
       ,@body)))

(defun elfeed-web-ng-test--run-timers ()
  "Run and clear the recorded timers, capturing any responses they send.
Return the responses as a list of (STATUS . BODY)."
  (let ((timers (reverse elfeed-web-ng-test--scheduled))
        (responses nil))
    (setq elfeed-web-ng-test--scheduled nil)
    (cl-letf (((symbol-function 'httpd-send-header)
               (lambda (_proc _mime status &rest _headers)
                 (setq httpd--header-sent t)
                 (push (cons status (buffer-string)) responses))))
      (mapc #'funcall timers))
    (nreverse responses)))

(ert-deftest elfeed-web-ng-test-feed-update-poll-chain ()
  "Repeated monitoring keeps a single poll timer running."
  (elfeed-web-ng-test--with-fetch-queue
    (setq elfeed-web-ng-test--queue 3)
    (elfeed-web-ng--monitor-feed-update)
    (elfeed-web-ng--monitor-feed-update)
    (should (= 1 (length elfeed-web-ng-test--scheduled)))
    ;; Each poll of a non-empty queue schedules exactly one more.
    (elfeed-web-ng-test--run-timers)
    (should (= 1 (length elfeed-web-ng-test--scheduled)))
    (setq elfeed-web-ng-test--queue 0)
    (elfeed-web-ng-test--run-timers)
    (should-not elfeed-web-ng-test--scheduled)
    (should-not elfeed-web-ng--feed-done-timer)))

(ert-deftest elfeed-web-ng-test-feed-update-skips-fetch-in-flight ()
  "A feed update starts a fetch only when none is in flight."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-fetch-queue
      (setq elfeed-web-ng-test--queue 2)
      (should (equal 200 (elfeed-web-ng-test--status "POST" "/elfeed/feed-update")))
      (should (= 0 elfeed-web-ng-test--updates))
      (setq elfeed-web-ng-test--queue 0)
      (should (equal 200 (elfeed-web-ng-test--status "POST" "/elfeed/feed-update")))
      (should (= 1 elfeed-web-ng-test--updates)))))

(ert-deftest elfeed-web-ng-test-feed-update-done-when-idle ()
  "With nothing being fetched, the long poll answers at once."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-fetch-queue
      (let ((response (elfeed-web-ng-test--request
                       "GET" "/elfeed/feed-update-done")))
        (should (equal 200 (plist-get response :status)))
        (should (equal '((status . "done"))
                       (elfeed-web-ng-test--json response)))
        (should-not elfeed-web-ng--feed-done-waiting)))))

(ert-deftest elfeed-web-ng-test-feed-update-done-without-trigger ()
  "A long poll parked during an update started from Emacs is answered.
No /feed-update request ever starts the poll chain in this case."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-fetch-queue
      (setq elfeed-web-ng-test--queue 4)
      (should-not (elfeed-web-ng-test--request "GET" "/elfeed/feed-update-done"))
      (should (= 1 (length elfeed-web-ng--feed-done-waiting)))
      (setq elfeed-web-ng-test--queue 0)
      (should (equal '((200 . "{\"status\":\"done\"}"))
                     (elfeed-web-ng-test--run-timers)))
      (should-not elfeed-web-ng--feed-done-waiting))))

;;; Server capabilities.

(ert-deftest elfeed-web-ng-test-api-features ()
  "Only features that depend on the setup are advertised."
  (elfeed-web-ng-test--with-server
    (let ((json-array-type 'list))
      (should (equal nil (alist-get 'features
                                    (elfeed-web-ng-test--json
                                     (elfeed-web-ng-test--request
                                      "GET" "/elfeed/api")))))
      (elfeed-web-ng-test--with-curate
        (should (equal '("annotations")
                       (alist-get 'features
                                  (elfeed-web-ng-test--json
                                   (elfeed-web-ng-test--request
                                    "GET" "/elfeed/api")))))))))

;;; Search.

(defun elfeed-web-ng-test--search (uri)
  "GET URI from the search endpoint and return the entry titles found."
  (let ((response (elfeed-web-ng-test--request "GET" uri)))
    (should (equal 200 (plist-get response :status)))
    (mapcar (lambda (e) (alist-get 'title e))
            (elfeed-web-ng-test--json response))))

(ert-deftest elfeed-web-ng-test-search-query ()
  "A missing or empty query matches everything; a filter narrows it."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (elfeed-web-ng-test--add-entry :id "1" :title "one" :date 1000)
      (elfeed-web-ng-test--add-entry :id "2" :title "two" :date 2000 :tags nil)
      (should (equal '("two" "one") (elfeed-web-ng-test--search "/elfeed/search")))
      (should (equal '("two" "one") (elfeed-web-ng-test--search "/elfeed/search?q=")))
      (should (equal '("one") (elfeed-web-ng-test--search
                               "/elfeed/search?q=%2Bunread"))))))

(ert-deftest elfeed-web-ng-test-search-limit ()
  "No query can raise the number of results above `elfeed-web-ng-limit'."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (dotimes (i 5)
        (elfeed-web-ng-test--add-entry :id (number-to-string i) :date (* 1000 (1+ i))))
      (let ((elfeed-web-ng-limit 2))
        (should (= 2 (length (elfeed-web-ng-test--search "/elfeed/search?q="))))
        (should (= 2 (length (elfeed-web-ng-test--search
                              "/elfeed/search?q=%23100000"))))
        ;; A lower limit in the query is honoured.
        (should (= 1 (length (elfeed-web-ng-test--search
                              "/elfeed/search?q=%231"))))))))

;;; Request bodies.

(ert-deftest elfeed-web-ng-test-body-keys-not-interned ()
  "Object keys in a request body never become symbols."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (let* ((prefix (format "elfeed-web-ng-test-key-%d-" (random 1000000)))
             (keys (cl-loop for i below 200 collect (format "%s%d" prefix i)))
             (body (concat "{"
                           (mapconcat (lambda (k) (format "%S: 1" k)) keys ", ")
                           ", \"entries\": []}")))
        (should (equal 200 (plist-get (elfeed-web-ng-test--put-tags body)
                                      :status)))
        (should-not (cl-some #'intern-soft keys))))))

(ert-deftest elfeed-web-ng-test-body-size-limit ()
  "A request body over the size limit is refused before it is parsed."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (let ((padding (make-string elfeed-web-ng--max-body-size ?\s)))
        (should (equal 413 (plist-get (elfeed-web-ng-test--put-tags
                                       (concat "{\"entries\": []}" padding))
                                      :status)))
        (should (equal 200 (plist-get (elfeed-web-ng-test--put-tags
                                       "{\"entries\": []}")
                                      :status)))))))

(ert-deftest elfeed-web-ng-test-annotation-type ()
  "Only a string or null is accepted as an annotation."
  (elfeed-web-ng-test--with-server
    (elfeed-web-ng-test--with-db
      (elfeed-web-ng-test--with-curate
        (let* ((entry (elfeed-web-ng-test--add-entry))
               (uri (concat "/elfeed/annotation/" (elfeed-web-ng-make-webid entry))))
          (dolist (body '("{\"annotation\": 5}"
                          "{\"annotation\": [1]}"
                          "{\"annotation\": {\"a\": 1}}"
                          "{\"annotation\": true}"))
            (should (equal (cons body 400)
                           (cons body (elfeed-web-ng-test--status
                                       "PUT" uri :body body)))))
          ;; Nothing was stored by the rejected requests.
          (should-not (elfeed-meta entry :test-annotation))
          (should (equal 200 (elfeed-web-ng-test--status
                              "PUT" uri :body "{\"annotation\": \"note\"}")))
          (should (equal "note" (elfeed-meta entry :test-annotation)))
          (should (equal 200 (elfeed-web-ng-test--status
                              "PUT" uri :body "{\"annotation\": null}")))
          (should (equal "" (elfeed-meta entry :test-annotation))))))))

;;; JSON shape served to the frontend.

(defun elfeed-web-ng-test--round-trip (thing)
  "Encode THING the way the servlets do and parse it back as an alist."
  (let ((json-array-type 'vector))
    (json-read-from-string (json-encode (elfeed-web-ng-for-json thing)))))

(ert-deftest elfeed-web-ng-test-entry-json-empty-lists ()
  "Empty tags and enclosures encode as arrays, and missing content as null."
  (elfeed-web-ng-test--with-db
    (let ((json (elfeed-web-ng-test--round-trip
                 (elfeed-web-ng-test--add-entry :tags nil))))
      (should (equal [] (alist-get 'tags json)))
      (should (equal [] (alist-get 'enclosures json)))
      (should (assq 'content json))
      (should-not (alist-get 'content json)))))

(ert-deftest elfeed-web-ng-test-entry-json-shape ()
  "An entry carries its fields, a millisecond date and its nested feed."
  (elfeed-web-ng-test--with-db
    (let* ((entry (elfeed-web-ng-test--add-entry
                   :title "Hello" :date 1700000000 :tags (list 'unread 'later)
                   :content "<p>body</p>"))
           (json (elfeed-web-ng-test--round-trip entry))
           (feed (alist-get 'feed json)))
      (should (equal (elfeed-web-ng-make-webid entry) (alist-get 'webid json)))
      (should (equal "Hello" (alist-get 'title json)))
      (should (equal "https://example.com/1" (alist-get 'link json)))
      (should (equal 1700000000000 (alist-get 'date json)))
      (should (equal ["unread" "later"] (alist-get 'tags json)))
      (should (equal (elfeed-ref-id (elfeed-entry-content entry))
                     (alist-get 'content json)))
      (should (elfeed-web-ng--valid-webid-p (alist-get 'webid feed)))
      (should (equal "Example" (alist-get 'title feed)))
      (should (equal "https://example.com/feed" (alist-get 'url feed))))))

(provide 'elfeed-web-ng-test)
;;; elfeed-web-ng-test.el ends here
