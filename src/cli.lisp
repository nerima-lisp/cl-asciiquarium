;;;; src/cli.lisp -- the command-line surface (cl-cli) and the executable's
;;;; entry points. Follows cl-weave's small-app delivery pattern: *APP* is
;;;; the declarative spec, MAIN drives it under a normal Lisp image, and
;;;; IMAGE-ENTRY-POINT (named by :ENTRY-POINT in cl-asciiquarium.asd) is the
;;;; toplevel of the `asciiquarium` binary `nix build` and
;;;; `(asdf:operate 'asdf:program-op ...)` both produce.
(in-package #:cl-asciiquarium)

(defparameter +version+ "0.1.0"
  "Mirrors :VERSION in cl-asciiquarium.asd; see docs/src/project/roadmap.md
for why this project does not derive the CLI's --version output from the .asd
file the way flake.nix does.")

(defparameter *app*
  (make-app
   :name "asciiquarium"
   :version +version+
   :summary "An ASCII-art aquarium screensaver for the terminal."
   :description "Swimming fish, a shark, rising bubbles, swaying seaweed, and
periodic special guests (a ship that drops an anchor, a line of ducks),
rendered live in the terminal. Press q to quit, r to redraw."
   :global-options
   (list (make-option :name "width" :kind :value :type :integer
                       :description "Terminal width override; defaults to the detected terminal size.")
         (make-option :name "height" :kind :value :type :integer
                       :description "Terminal height override; defaults to the detected terminal size.")
         (make-option :name "seed" :kind :value :type :integer
                       :description "Seed the random number generator for a reproducible run.")
         (make-option :name "fps" :kind :value :type :integer :min 1 :max 60
                       :description "Target frames per second (default 20)."))
   :handler #'%run-handler))

(defun %run-handler (invocation)
  "The handler cl-cli:RUN-APP dispatches to: resolve --width/--height against
the detected terminal size, then run the aquarium. Returns 0 once RUN returns
(i.e. once the user presses `q')."
  (multiple-value-bind (detected-columns detected-rows) (terminal-size)
    (run :width (or (option-value invocation :width) detected-columns +default-width+)
         :height (or (option-value invocation :height) detected-rows +default-height+)
         :seed (option-value invocation :seed)
         :interval (/ 1 (or (option-value invocation :fps) 20))))
  0)

(defun main ()
  "Entry point for a plain `sbcl --script'/REPL invocation: parse the current
process argv against *APP* and exit with its result code."
  (uiop:quit (run-app *app* :argv (current-process-argv))))

(defun image-entry-point ()
  "Toplevel of the delivered `asciiquarium' executable; named by :ENTRY-POINT
in cl-asciiquarium.asd. Identical to MAIN -- this application loads no further
ASDF systems at run time, so it needs none of cl-weave's image-relocation
bootstrapping (see cl-weave/src/cli-image.lisp) beyond this thin wrapper."
  (uiop:quit (run-app *app* :argv (current-process-argv))))
