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

  (it "accepts the --fps boundary values 1 and 60"
    (with-soft-assertions
      (expect (= (option-value (parse-argv *app* '("asciiquarium" "--fps" "1")) :fps) 1)
              :to-be-truthy)
      (expect (= (option-value (parse-argv *app* '("asciiquarium" "--fps" "60")) :fps) 60)
              :to-be-truthy)))

  (it "rejects a --fps below the 1 minimum"
    (expect (signals (parse-argv *app* '("asciiquarium" "--fps" "0"))
                     'cli-invalid-option-value)
            :to-be-truthy))

  (it "rejects a --fps above the 60 maximum"
    (expect (signals (parse-argv *app* '("asciiquarium" "--fps" "61"))
                     'cli-invalid-option-value)
            :to-be-truthy)))

(describe "the cl-asciiquarium app spec: --help and --version"
  (it "exits 0 on --help without invoking the aquarium handler"
    (let ((output (with-output-to-string (out)
                    (expect (= (run-app *app* :argv '("asciiquarium" "--help")
                                       :stdout out)
                              0)
                            :to-be-truthy))))
      (expect (search "asciiquarium" output) :to-be-truthy)))

  (it "exits 0 on --version and prints the app's name and version"
    (let ((output (with-output-to-string (out)
                    (expect (= (run-app *app* :argv '("asciiquarium" "--version")
                                       :stdout out)
                              0)
                            :to-be-truthy))))
      (expect (search "asciiquarium" output) :to-be-truthy))))
