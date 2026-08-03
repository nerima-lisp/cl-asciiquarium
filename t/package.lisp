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
                #:make-input-decoder)
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

(defun run-tests ()
  "Run every registered spec, signalling on any failure so ASDF's TEST-OP
fails. Randomness in the specs below is pinned via SB-EXT:SEED-RANDOM-STATE
inside each test that needs a deterministic scenario (predator/prey removal,
special-guest spawn), not via cl-weave's own --seed replay mechanism, since
those scenarios bind CL:*RANDOM-STATE* around a handful of direct calls into
cl-asciiquarium rather than around cl-weave's own attempt machinery.
*DEFAULT-TIMEOUT-MS* is set here, not left at cl-weave's NIL default, so a
runaway loop (e.g. a fuzz-generated width/height that never terminates
WORLD-ADVANCE) fails this one `it' in seconds instead of exhausting CI's
6-hour job default; see TEST_STANDARD.md's 実行 section."
  (setf *default-timeout-ms* 5000)
  (unless (run-all :reporter :spec)
    (error "cl-asciiquarium test suite failed"))
  (format t "~&cl-asciiquarium/test: successful completion with 0 failures~%")
  t)
