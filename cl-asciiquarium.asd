;;; This form comes FIRST, before any defsystem. ASDF binds *package* to
;;; ASDF-USER only for a file it loads itself; read any other way -- a REPL
;;; `load`, an editor evaluating the buffer, flake.nix parsing :version --
;;; the file is read in whatever package happens to be current, and an
;;; unqualified `defsystem` then fails to read at all. See
;;; PACKAGE_STANDARD.md "asd の書き方".
(in-package #:asdf-user)

(defsystem "cl-asciiquarium"
  :description "An original ASCII-art aquarium screensaver for the terminal."
  :long-description "Swimming fish, a shark, rising bubbles, swaying seaweed,
and periodic special guests (a ship that drops an anchor, a line of ducks, a
leaping dolphin, a segmented sea monster) rendered live in a terminal via
cl-tty-kit. Pause, adjust the live fish count, spawn a shark or guest on
demand, or run monochrome. Every sprite is original art authored for this
repository. SBCL only."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/nerima-lisp/cl-asciiquarium"
  :bug-tracker "https://github.com/nerima-lisp/cl-asciiquarium/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-asciiquarium.git")
  :depends-on ("cl-tty-kit"    ; screens, sprites, entities, tick loop, raw mode, input decoding
               "cl-cli")       ; --width/--height/--seed/--fps command-line parsing
  :pathname "src"
  :serial t
  :components ((:file "package")
               (:file "conditions")
               (:file "geometry")
               (:file "creature")
               (:file "creature-cache")
               (:file "world")
               (:file "art-fish-data")
               (:file "art-fish")
               (:file "art-shark")
               (:file "art-decor-data")
               (:file "art-decor")
               (:file "art-guests-data")
               (:file "art-guests")
               (:file "bubble")
               (:file "spawn")
               (:file "collision")
               (:file "update")
               (:file "input")
               (:file "render-state")
               (:file "render")
               (:file "app")
               (:file "cli"))
  ;; Delivers the `asciiquarium` executable via `(asdf:operate 'asdf:program-op
  ;; "cl-asciiquarium")` / `nix build`, both driven from these three keys --
  ;; see cl-weave.asd, which this follows, and flake.nix's `executable` block.
  :build-operation "program-op"
  :build-pathname "asciiquarium"
  :entry-point "cl-asciiquarium:image-entry-point"
  ;; Mandatory. Without it `asdf:test-system "cl-asciiquarium"` succeeds while
  ;; running zero tests. See PACKAGE_STANDARD.md.
  :in-order-to ((test-op (test-op "cl-asciiquarium/test"))))

;;; The test system is `cl-asciiquarium/test` (singular, slash-separated) with
;;; :pathname "t". It is NOT `cl-asciiquarium-test`.
(defsystem "cl-asciiquarium/test"
  :description "Test system for cl-asciiquarium."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/nerima-lisp/cl-asciiquarium"
  :bug-tracker "https://github.com/nerima-lisp/cl-asciiquarium/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-asciiquarium.git")
  ;; cl-weave is the org's test framework everywhere. Do not introduce FiveAM,
  ;; parachute, rove or prove.
  ;;
  ;; Test-only: cl-tty-kit for DECODE-INPUT (t/input-test.lisp builds
  ;; KEY-EVENTs from a plain string; see t/package.lisp). It is already the
  ;; main system's own dependency, at the same layer, so this stays within
  ;; DEPENDENCY_POLICY.md's test-only-dependency limit.
  :depends-on ("cl-asciiquarium" "cl-weave" "cl-tty-kit")
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "helpers-world")
               (:file "conditions-test")
               (:file "geometry-test")
               (:file "creature-test")
               (:file "art-fish-test")
               (:file "world-test")
               (:file "world-resize-test")
               (:file "input-test")
               (:file "collision-test")
               (:file "spawn-test")
               (:file "render-test")
               (:file "cli-test")
               (:file "app-test"))
  :perform (test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-asciiquarium/test :run-tests)
               (error "cl-asciiquarium self test suite failed."))))
