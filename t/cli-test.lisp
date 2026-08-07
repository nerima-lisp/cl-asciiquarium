;;;; t/cli-test.lisp
;;;;
;;;; Flag parsing only: the handler calls RUN (src/app.lisp), which takes
;;;; over a real terminal in raw mode via a realtime tick loop -- the same
;;;; shape as cl-cmatrix's CLI (a persistent, full-screen loop) rather than
;;;; cl-cowsay's one-shot print -- so these tests never invoke it (never
;;;; RUN-APP without --help or --version); see
;;;; cl-cmatrix/t/cli-test.lisp, which gives the same reasoning.

(in-package #:cl-asciiquarium/test)

(describe "the cl-asciiquarium app spec: flag parsing round-trips"
  (it "defaults --width, --height, --seed, and --fps to unset"
    (let ((invocation (parse-argv *app* '("asciiquarium"))))
      (with-soft-assertions
        (expect (option-value invocation :width) :to-be-falsy)
        (expect (option-value invocation :height) :to-be-falsy)
        (expect (option-value invocation :seed) :to-be-falsy)
        (expect (option-value invocation :fps) :to-be-falsy))))

  (it "parses --width and --height as integers"
    (let ((invocation (parse-argv *app* '("asciiquarium" "--width" "100" "--height" "30"))))
      (with-soft-assertions
        (expect (= (option-value invocation :width) 100) :to-be-truthy)
        (expect (= (option-value invocation :height) 30) :to-be-truthy))))

  (it "parses --seed as an integer -- the flag a reproducible run depends on"
    (let ((invocation (parse-argv *app* '("asciiquarium" "--seed" "42"))))
      (expect (= (option-value invocation :seed) 42) :to-be-truthy)))

  (it "parses --fps as an integer"
    (let ((invocation (parse-argv *app* '("asciiquarium" "--fps" "30"))))
      (expect (= (option-value invocation :fps) 30) :to-be-truthy)))

  (it "parses --theme as a declared visual choice"
    (let ((invocation (parse-argv *app* '("asciiquarium" "--theme" "coral"))))
      (expect (string= (option-value invocation :theme) "coral") :to-be-truthy)))

  (it "accepts the --fps boundary values 1 and 60"
    (with-soft-assertions
      (expect (= (option-value (parse-argv *app* '("asciiquarium" "--fps" "1")) :fps) 1)
              :to-be-truthy)
      (expect (= (option-value (parse-argv *app* '("asciiquarium" "--fps" "60")) :fps) 60)
              :to-be-truthy)))

  (it "rejects a --fps below the 1 minimum"
    (signals cli-invalid-option-value (parse-argv *app* '("asciiquarium" "--fps" "0"))))

  (it "rejects a --fps above the 60 maximum"
    (signals cli-invalid-option-value (parse-argv *app* '("asciiquarium" "--fps" "61"))))

  (it "defaults --no-shark and --monochrome to unset"
    (let ((invocation (parse-argv *app* '("asciiquarium"))))
      (with-soft-assertions
        (expect (option-value invocation :no-shark) :to-be-falsy)
        (expect (option-value invocation :monochrome) :to-be-falsy))))

  (it "parses --no-shark and --monochrome as flags, taking no value"
    (let ((invocation (parse-argv *app* '("asciiquarium" "--no-shark" "--monochrome"))))
      (with-soft-assertions
        (expect (option-value invocation :no-shark) :to-be-truthy)
        (expect (option-value invocation :monochrome) :to-be-truthy)))))

(describe "the cl-asciiquarium app spec: --help and --version"
  (it "exits 0 on --help without invoking the aquarium handler"
    (let ((output (with-output-to-string (out)
                    (expect (zerop (run-app *app* :argv '("asciiquarium" "--help")
                                       :stdout out))
                            :to-be-truthy))))
      (expect (search "asciiquarium" output) :to-be-truthy)))

  (it "exits 0 on --version and prints the app's name and version"
    (let ((output (with-output-to-string (out)
                    (expect (zerop (run-app *app* :argv '("asciiquarium" "--version")
                                       :stdout out))
                            :to-be-truthy))))
      (expect (search "asciiquarium" output) :to-be-truthy))))

(describe "run-handler"
  (it "uses the detected terminal dimensions and default frame interval"
    (let* ((terminal-size-symbol 'cl-asciiquarium::terminal-size)
           (run-symbol 'cl-asciiquarium:run)
           (original-terminal-size (symbol-function terminal-size-symbol))
           (original-run (symbol-function run-symbol))
           (arguments nil))
      (unwind-protect
           (progn
             (setf (symbol-function terminal-size-symbol)
                   (lambda () (values 100 40))
                   (symbol-function run-symbol)
                   (lambda (&rest received) (setf arguments received)))
             (expect (zerop (cl-asciiquarium::run-handler
                             (parse-argv *app* '("asciiquarium"))))
                     :to-be-truthy)
             (expect (equal arguments
                            '(:width 100 :height 40 :seed nil :interval 1/20
                              :shark-enabled-p t :monochrome-p nil :theme :abyss))
                     :to-be-truthy))
        (setf (symbol-function terminal-size-symbol) original-terminal-size
              (symbol-function run-symbol) original-run))))

  (it "passes explicit CLI options to run instead of terminal defaults"
    (let* ((terminal-size-symbol 'cl-asciiquarium::terminal-size)
           (run-symbol 'cl-asciiquarium:run)
           (original-terminal-size (symbol-function terminal-size-symbol))
           (original-run (symbol-function run-symbol))
           (arguments nil))
      (unwind-protect
           (progn
             (setf (symbol-function terminal-size-symbol)
                   (lambda () (values 100 40))
                   (symbol-function run-symbol)
                   (lambda (&rest received) (setf arguments received)))
             (expect (zerop (cl-asciiquarium::run-handler
                             (parse-argv *app*
                                         '("asciiquarium" "--width" "90" "--height" "30"
                                           "--seed" "42" "--fps" "25" "--no-shark"
                                           "--monochrome" "--theme" "moonlight"))))
                     :to-be-truthy)
             (expect (equal arguments
                            '(:width 90 :height 30 :seed 42 :interval 1/25
                              :shark-enabled-p nil :monochrome-p t :theme :moonlight))
                     :to-be-truthy))
        (setf (symbol-function terminal-size-symbol) original-terminal-size
              (symbol-function run-symbol) original-run)))))
(describe "CLI entry points"
  (it "uses the ASDF version when available and falls back when unavailable"
    (let* ((find-system-symbol (quote asdf:find-system))
           (original-find-system (symbol-function find-system-symbol)))
      (unwind-protect
           (progn
             (expect (string= (cl-asciiquarium::asciiquarium-version)
                              (asdf:component-version
                               (asdf:find-system "cl-asciiquarium" nil)))
                     :to-be-truthy)
             (setf (symbol-function find-system-symbol)
                   (lambda (&rest ignored)
                     (declare (ignore ignored))
                     nil))
             (expect (string= (cl-asciiquarium::asciiquarium-version) "0.0.0")
                     :to-be-truthy))
        (setf (symbol-function find-system-symbol) original-find-system))))

  (it "passes the process argv to RUN-APP and quits with its result"
    (let* ((argv-symbol (quote cl-asciiquarium::current-process-argv))
           (run-app-symbol (quote cl-asciiquarium::run-app))
           (quit-symbol (quote uiop:quit))
           (original-argv (symbol-function argv-symbol))
           (original-run-app (symbol-function run-app-symbol))
           (original-quit (symbol-function quit-symbol))
           (received-argv nil)
           (exit-code nil))
      (unwind-protect
           (progn
             (setf (symbol-function argv-symbol)
                   (lambda () (quote ("asciiquarium" "--help")))
                   (symbol-function run-app-symbol)
                   (lambda (app &key argv)
                     (declare (ignore app))
                     (setf received-argv argv)
                     23)
                   (symbol-function quit-symbol)
                   (lambda (code) (setf exit-code code)))
             (cl-asciiquarium:main)
             (with-soft-assertions
               (expect (equal received-argv (quote ("asciiquarium" "--help")))
                       :to-be-truthy)
               (expect (= exit-code 23) :to-be-truthy)))
        (setf (symbol-function argv-symbol) original-argv
              (symbol-function run-app-symbol) original-run-app
              (symbol-function quit-symbol) original-quit))))

  (it "delegates the delivered-image entry point to MAIN"
    (let* ((main-symbol (quote cl-asciiquarium:main))
           (original-main (symbol-function main-symbol))
           (called nil))
      (unwind-protect
           (progn
             (setf (symbol-function main-symbol) (lambda () (setf called t)))
             (cl-asciiquarium:image-entry-point)
             (expect called :to-be-truthy))
        (setf (symbol-function main-symbol) original-main)))))
