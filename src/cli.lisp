;;;; src/cli.lisp -- the command-line surface (cl-cli) and the executable's
;;;; entry points. Follows cl-weave's small-app delivery pattern: *APP* is
;;;; the declarative spec, MAIN drives it under a normal Lisp image, and
;;;; IMAGE-ENTRY-POINT (named by :ENTRY-POINT in cl-asciiquarium.asd) is the
;;;; toplevel of the `asciiquarium` binary `nix build` and
;;;; `(asdf:operate 'asdf:program-op ...)` both produce.
(in-package #:cl-asciiquarium)

(defun asciiquarium-version ()
  "The running CL-ASCIIQUARIUM system's :VERSION, the single source of truth
also read by flake.nix and enforced by release.yml against the git tag."
  (let ((system (asdf:find-system "cl-asciiquarium" nil)))
    (if system (asdf:component-version system) "0.0.0")))

(defun color-environment ()
  "Return (VALUES COLORTERM TERM NO-COLOR), the environment variables
--color auto reads (see DETECT-COLOR-MODE), each a string or NIL."
  (values (uiop:getenv "COLORTERM") (uiop:getenv "TERM") (uiop:getenv "NO_COLOR")))

(defun run-handler (invocation)
  "The handler cl-cli:RUN-APP dispatches to: resolve --width/--height against
the detected terminal size and --color against the terminal's environment,
then run the aquarium. The initial fish count is +DEFAULT-FISH-COUNT+, lowered
to --max-fish when that is smaller. Returns 0 once RUN returns (i.e. once the
user presses `q')."
  (multiple-value-bind (detected-columns detected-rows) (terminal-size)
    (let ((max-fish (or (option-value invocation :max-fish) +default-max-fish+)))
      (run :width (or (option-value invocation :width) detected-columns +default-width+)
           :height (or (option-value invocation :height) detected-rows +default-height+)
           :seed (option-value invocation :seed)
           :interval (/ 1 (or (option-value invocation :fps) 20))
           :shark-enabled-p (not (option-value invocation :no-shark))
           :monochrome-p (option-value invocation :monochrome)
           :theme (parse-visual-theme
                   (or (option-value invocation :theme) "abyss"))
           :color-mode (multiple-value-bind (colorterm term no-color) (color-environment)
                         (resolve-color-mode (option-value invocation :color)
                                             :colorterm colorterm
                                             :term term
                                             :no-color no-color
                                             :monochrome-p (option-value invocation :monochrome)))
           :ascii-p (option-value invocation :ascii)
           :fish-count (min +default-fish-count+ max-fish)
           :max-fish max-fish
           :calm-p (option-value invocation :calm))))
  0)

(defparameter *app*
  (make-app
   :name "asciiquarium"
   :version (asciiquarium-version)
   :summary "An ASCII-art aquarium screensaver for the terminal."
   :description "Swimming fish, a shark, rising bubbles, swaying seaweed, and
periodic special guests (a ship that drops an anchor, a line of ducks, a
leaping dolphin, a segmented sea monster), rendered live in the terminal.
Press q to quit, r to redraw, space to pause, +/- to grow or shrink the fish
count, s/g to spawn a shark/guest on demand, t to cycle themes, u to toggle
the status bar, and h for the full key list."
   :global-options
   (list (make-option :name "width" :kind :value :type :integer
                       :description
                       "Terminal width override; defaults to the detected terminal size.")
         (make-option :name "height" :kind :value :type :integer
                       :description
                       "Terminal height override; defaults to the detected terminal size.")
         (make-option :name "seed" :kind :value :type :integer
                       :description "Seed the random number generator for a reproducible run.")
         (make-option :name "fps" :kind :value :type :integer :min 1 :max 60
                       :description "Target frames per second (default 20).")
         (make-option :name "max-fish" :kind :value :type :integer
                       :min 1 :max +max-fish-count+
                       :description
                       "Most fish the + key grows the tank to (1-40, default 30).")
         (make-option :name "calm" :kind :flag
                       :description "Turn off blinking animations.")
         (make-option :name "theme" :kind :value
                       :choices '("abyss" "coral" "moonlight")
                       :description "Initial visual theme (default abyss).")
         (make-option :name "no-shark" :kind :flag
                       :description "Disable the shark, so fish are never eaten.")
         (make-option :name "color" :kind :value
                       :choices '("auto" "truecolor" "256" "16" "mono")
                       :description
                       "Color depth: auto (default; from COLORTERM, TERM, and NO_COLOR), truecolor, 256, 16, or mono.")
         (make-option :name "ascii" :kind :flag
                       :description
                       "Draw only ASCII symbols, for terminals without the Unicode ones or that draw them two columns wide.")
         (make-option :name "monochrome" :kind :flag
                       :description
                       "Same as --color mono: render everything in the terminal's default colors."))
   :handler #'run-handler))

(defun main ()
  "Entry point for a plain `sbcl --script'/REPL invocation: parse the current
process argv against *APP* and exit with its result code."
  (uiop:quit (run-app *app* :argv (current-process-argv))))

(defun image-entry-point ()
  "Toplevel of the delivered `asciiquarium' executable; named by :ENTRY-POINT
in cl-asciiquarium.asd. Delegates to MAIN -- this application loads no further
ASDF systems at run time, so it needs none of cl-weave's image-relocation
bootstrapping (see cl-weave/src/cli-image.lisp) beyond this thin wrapper."
  (main))
