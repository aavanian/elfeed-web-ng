#!/bin/bash
# Run every automated check: lint, byte-compilation and the ERT suite.
#
# The elisp dependencies are looked up in the straight.el build directory
# this checkout normally lives next to.  Point ELFEED_DIR and HTTPD_DIR at
# the directories holding elfeed.el and simple-httpd.el to use others.
set -euo pipefail

cd "$(dirname "$0")"

EMACS=${EMACS:-emacs}

emacs_version() {
	"$EMACS" --batch --eval '(princ emacs-version)'
}

straight_build_dir() {
	echo "../../build-$(emacs_version)"
}

ELFEED_DIR=${ELFEED_DIR:-$(straight_build_dir)/elfeed}
HTTPD_DIR=${HTTPD_DIR:-$(straight_build_dir)/simple-httpd}

check_dependencies() {
	local dir
	for dir in "$ELFEED_DIR" "$HTTPD_DIR"; do
		if [ ! -d "$dir" ]; then
			echo "missing elisp dependency directory: $dir" >&2
			echo "set ELFEED_DIR and HTTPD_DIR (see README, Tests)" >&2
			exit 1
		fi
	done
}

run_emacs() {
	"$EMACS" --batch -L "$ELFEED_DIR" -L "$HTTPD_DIR" -L . "$@"
}

lint_shell() {
	echo "== shellcheck"
	shellcheck check.sh
}

byte_compile() {
	echo "== byte-compile"
	local out
	out=$(mktemp -d)
	# Compile into a scratch directory so no .elc shadows the sources.
	run_emacs --eval "(setq byte-compile-error-on-warn t
                            byte-compile-dest-file-function
                            (lambda (f) (expand-file-name
                                         (concat (file-name-nondirectory f) \"c\")
                                         \"$out\")))" \
		-f batch-byte-compile elfeed-web-ng.el
	rm -rf "$out"
}

run_ert() {
	echo "== ERT"
	run_emacs -l test/elfeed-web-ng-test.el -f ert-run-tests-batch-and-exit
}

check_dependencies
lint_shell
byte_compile
run_ert
