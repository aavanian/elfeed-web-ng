# Packaging review: elfeed-web-ng

Scope: whole repository · Commit: 0e482e5 · Date: 2026-09-29

Packaging is in good shape overall.
- **Build:** a build into a temp outDir outside the repo matches the committed `web/` byte for byte, apart from the per-build stamps (buildId, commit, date).
- **Dependencies:** `pnpm-lock.yaml` agrees with `package.json`, and every npm import is declared. Every elfeed and simple-httpd symbol the elisp uses exists in the declared minimum versions (elfeed 3.2.0, simple-httpd 1.5.1).
- **License and recipe:** LICENSE is AGPL-3.0 and matches the SPDX header. The straight `:files ("*.el" "web")` recipe leaves out `legacy/`, `src/` and `test/` as intended.

Only low-severity findings remain. The README description of `merge=ours` is tracked as DOC-006.

## PKG-001: Add an automated check that committed web/ matches src/

- **Severity:** low
- **Confidence:** high
- **Location:** `README.md:107-113`, `vite.config.js:61-72`, `.gitattributes:3`
- **Labels:** packaging, build

Users only ever get the committed `web/` bundle (README.md:107). Keeping it in sync with `src/` is manual, and there is no CI, check script or hook to catch a stale bundle. `web/** merge=ours` (`.gitattributes:3`) makes a stale bundle after a merge or rebase more likely. Today's tree is in sync, so this is future risk, not a current bug.

**Why it matters:** a `src/` change committed without a rebuild ships old frontend code against a newer backend.

**Suggested fix:** add a check (CI or `check.sh`) that runs `vite build --outDir <tmp>` and diffs the result against `web/`, ignoring the build stamps.

**Done when:** a commit that changes `src/` without rebuilding fails the check, and the current tree passes.

## PKG-002: Emacs minimum version 29.2 looks higher than the code needs

- **Severity:** low
- **Confidence:** medium
- **Location:** `elfeed-web-ng.el:11`
- **Labels:** packaging, elisp

`Package-Requires` declares `(emacs "29.2")`. Nothing called in the file (cl-lib, `if-let*`/`and-let*`, `json-encode`, `json-read-from-string`, `url-generic-parse-url`, `secure-hash`, `file-truename`, …) looks newer than about Emacs 26. To confirm, byte-compile and run `test/` on Emacs 29.1 or older.

**Why it matters:** package.el and straight refuse the package below the floor even when it would run.

**Suggested fix:** lower the floor to the oldest tested version (e.g. `"29.1"`), or add a comment naming the feature that needs 29.2.

**Done when:** the minimum is either justified by a named feature or backed by a passing test run on that version.

## PKG-003: Version string is hard-coded in three places

- **Severity:** low
- **Confidence:** high
- **Location:** `elfeed-web-ng.el:10`, `elfeed-web-ng.el:105-106`, `package.json:3`
- **Labels:** packaging, release

"1.0.0" appears in the `;; Version:` header, in `elfeed-web-ng--version`, and in `package.json`. `/elfeed/api` reports the defvar (line 407). Nothing keeps the three in sync.

**Why it matters:** a partial bump makes the API report the wrong version.

**Suggested fix:** derive the defvar from the header (e.g. with `lm-version` at load time), or add a test asserting that all three are equal.

**Done when:** bumping one without the others either cannot happen or fails a test.

## PKG-004: package.json lacks license and package-manager pinning

- **Severity:** low
- **Confidence:** high
- **Location:** `package.json:1-20`, `pnpm-lock.yaml:1`, `CLAUDE.md:5`
- **Labels:** packaging, frontend

`package.json` has no `license` field, although the project is AGPL-3.0-or-later. It has no `packageManager` or `engines` field either, although the project requires pnpm and the lockfile (v9.0) needs pnpm 9 or later. Because of `"private": true`, the impact is limited to tooling and contributors.

**Why it matters:** license scanners report the frontend as unlicensed, and npm, yarn or an older pnpm ignore or rewrite the lockfile.

**Suggested fix:** add `"license": "AGPL-3.0-or-later"` and `"packageManager": "pnpm@<version>"`.

**Done when:** `package.json` declares the elisp license, and Corepack enforces a compatible pnpm.

## PKG-005: Elisp library header lacks Author/Maintainer and Keywords

- **Severity:** low
- **Confidence:** medium
- **Location:** `elfeed-web-ng.el:1-11`
- **Labels:** packaging, elisp

The header has `URL`, `Version` and `Package-Requires`, but no `Author:`, `Maintainer:` or `Keywords:`. package.el shows these, and package-lint and MELPA review expect them.

**Why it matters:** users see no maintainer contact or category, and a future archive submission needs them.

**Suggested fix:** add `;; Author:`, `;; Maintainer:` and `;; Keywords: comm, news`.

**Done when:** `lm-maintainers` and `lm-keywords-list` return non-empty values, and package-lint reports no header warnings.
