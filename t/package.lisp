;;;; t/package.lisp
(defpackage #:cl-asciiquarium/test
  (:use #:cl #:cl-asciiquarium)
  ;; DESCRIBE clashes with CL:DESCRIBE, so shadow-import cl-weave's.
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:it #:it-each #:expect #:signals #:run-all #:with-soft-assertions
                #:it-property #:it-fuzz #:gen-integer #:gen-string
                #:*default-timeout-ms*
                #:run-mutations #:assert-mutation-score #:it-sequential)
  ;; Test-only cl-tty-kit primitives. cl-asciiquarium imports all of these
  ;; into its own package already (src/package.lisp) but does not re-export
  ;; them as part of its own public API -- an application does not need to
  ;; forward its rendering library's primitives -- so tests that exercise
  ;; ENTITY/SCREEN/RENDERER directly (rather than only through CREATURE/WORLD)
  ;; import them here instead. DECODE-INPUT (a one-shot decoder building
  ;; KEY-EVENTs from a plain string) is the simplest way for a test to drive
  ;; WORLD-APPLY-KEY-EVENT without composing raw escape sequences; the shipped
  ;; application only needs the incremental DECODE-INPUT-CHUNK (src/app.lisp).
  (:import-from #:cl-tty-kit
                #:decode-input
                #:entity-tick #:entity-x #:entity-y #:entity-dx #:entity-dy
                #:make-screen #:make-renderer
                #:tick-loop-run
                #:cell-char #:screen-cell
                #:make-input-decoder
                #:make-style #:style-fg #:named-color)
  ;; Test-only cl-cli primitives for t/cli-test.lisp. cl-asciiquarium imports
  ;; make-app/make-option/run-app/option-value/current-process-argv into its
  ;; own package already (src/package.lisp) but does not re-export them as
  ;; part of its own public API, so tests that drive *APP* through cl-cli's
  ;; own parsing entry points (rather than only through RUN) import them
  ;; here instead, the same reasoning DECODE-INPUT above follows for
  ;; cl-tty-kit.
  (:import-from #:cl-cli
                #:parse-argv
                #:run-app
                #:option-value
                #:cli-invalid-option-value)
  (:export #:run-tests))

(in-package #:cl-asciiquarium/test)

(defun run-tests (&key coverage
                       coverage-output
                       coverage-report-directory
                       coverage-include-pathnames
                       coverage-exclude-pathnames
                       coverage-minimum-expression
                       coverage-minimum-branch)
  "Run every registered spec and signal on any failure.
COVERAGE and its keyword arguments are passed to cl-weave so the same test
entry point can run either the normal suite or a coverage-gated report."
  (setf *default-timeout-ms* 5000)
  (unless
      (run-all :reporter :spec
               :coverage coverage
               :coverage-output coverage-output
               :coverage-report-directory coverage-report-directory
               :coverage-include-pathnames coverage-include-pathnames
               :coverage-exclude-pathnames coverage-exclude-pathnames
               :coverage-minimum-expression coverage-minimum-expression
               :coverage-minimum-branch coverage-minimum-branch
               :pass-with-no-tests nil)
    (error "cl-asciiquarium test suite failed"))
  (format t "~&cl-asciiquarium/test: successful completion with 0 failures~%")
  t)
