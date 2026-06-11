;;; elfeed-web-ng-test.el --- Tests for elfeed-web-ng -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for the request-guarding helpers.  Run with:
;;
;;   emacs --batch -L <deps> -L . -l test/elfeed-web-ng-test.el \
;;         -f ert-run-tests-batch-and-exit

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
    ;; A rebound origin keeps its own Host header.
    (should-not (elfeed-web-ng--host-allowed-p "evil.example.com"))
    (should-not (elfeed-web-ng--host-allowed-p nil))))

;;; Origin check.

(ert-deftest elfeed-web-ng-test-origin-allowed ()
  (let ((elfeed-web-ng-allowed-hosts '("feeds.example.net"))
        (httpd-host nil))
    ;; A missing Origin defers to the Host check.
    (should (elfeed-web-ng--origin-allowed-p nil))
    ;; Same-site origins pass, port and scheme notwithstanding.
    (should (elfeed-web-ng--origin-allowed-p "http://feeds.example.net:8080"))
    (should (elfeed-web-ng--origin-allowed-p "https://feeds.example.net"))
    (should (elfeed-web-ng--origin-allowed-p "http://localhost:8080"))
    ;; Cross-site and opaque origins are rejected.
    (should-not (elfeed-web-ng--origin-allowed-p "http://evil.example.com"))
    (should-not (elfeed-web-ng--origin-allowed-p "null"))))

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

(provide 'elfeed-web-ng-test)
;;; elfeed-web-ng-test.el ends here
