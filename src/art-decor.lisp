;;;; src/art-decor.lisp -- the static-ish ocean background: waterline,
;;;; castle, and swaying seaweed. All three are CREATURE instances like every
;;;; other sprite (policy :NONE: none of them ever leaves the world bounds).
;;;; The art itself is data, in art-decor-data.lisp.
(in-package #:cl-asciiquarium)

(defun waterline-art (width)
  "Return a WIDTH-wide wavy waterline pattern, repeating a 4-character motif."
  (let ((motif "^^~~"))
    (with-output-to-string (out)
      (loop for column below width
            do (write-char (char motif (mod column (length motif))) out)))))

(defun ambient-current-art (width phase)
  "Return two WIDTH-wide rows of drifting ambient current marks."
  (with-output-to-string (out)
    (dotimes (row 2)
      (loop for column below width
            do (write-char
                (char +ambient-current-motif+
                      (mod (+ column phase (* row 5))
                           (length +ambient-current-motif+)))
                out))
      (when (zerop row)
        (terpri out)))))

(defun ambient-current-frames (width)
  "Return the deterministic looping frames for WORLD's ambient current."
  (loop for phase below 4
        collect (ambient-current-art width phase)))

(defun hud-art (world)
  "Return the one-line status bar for WORLD's current visual state."
  (format nil "[~A]  FISH ~2,'0D  ~A"
          (visual-theme-label (world-theme world))
          (world-fish-count world)
          (if (world-paused-p world) "PAUSED" "SWIM")))

(defun make-ambient-current (world)
  "Create a subtle animated current behind the aquarium population."
  (make-creature :world world
                 :kind :ambient-current
                 :frames (ambient-current-frames (world-width world))
                 :frame-period 8
                 :style (world-style world :bright-blue)
                 :z -1
                 :policy :none
                 :x 0
                 :y 1
                 :dx 0
                 :dy 0))

(defun make-waterline (world)
  "Create the waterline decoration spanning the full width of WORLD."
  (make-creature :world world
                  :kind :waterline
                  :frames (list (waterline-art (world-width world)))
                  :style (world-style world :bright-blue)
                  :%trusted-frames-p t
                  :%trusted-style-p t
                  :z 0
                  :policy :none
                  :x 0
                  :y +waterline-row+
                  :dx 0 :dy 0))

(defun make-castle (world)
  "Create the castle decoration near the bottom-left of WORLD."
  (multiple-value-bind (width height) (sprite-dimensions +castle-art+)
    (declare (ignore width))
    (make-creature :world world
                    :kind :castle
                    :frames (list +castle-art+)
                    :style (world-style world :yellow)
                    :z 1
                    :policy :none
                    :x 2
                    :y (max (1+ +waterline-row+) (- (world-height world) height 1))
                    :dx 0 :dy 0)))

(defun make-seaweed (world x)
  "Create one swaying seaweed strand rooted at column X near the bottom of
WORLD."
  (multiple-value-bind (width height) (sprite-dimensions (first +seaweed-frames+))
    (declare (ignore width))
    (make-creature :world world
                    :kind :seaweed
                    :frames +seaweed-frames+
                    :frame-period (random-between 8 16)
                    :style (world-style world :green)
                    :z 1
                    :policy :none
                    :x x
                    :y (- (world-height world) height)
                    :dx 0 :dy 0)))

(defun make-help-overlay (world)
  "Create the :HELP-OVERLAY CREATURE toggled by the `h' key (see
WORLD-TOGGLE-HELP-OVERLAY, input.lisp): a fixed panel near the top-left
corner, painted at Z 99 so it always sits above every other creature. Unlike
every other decoration, its policy is :NONE and it is never touched by
WORLD-REDRAW (excluded from +TRANSIENT-CREATURE-KINDS+, world.lisp): it is UI
state, not aquarium population."
  (make-creature :world world
                  :kind :help-overlay
                  :frames (list +help-overlay-art+)
                  :style (world-style world :bright-white)
                  :z 99
                  :policy :none
                  :x 1
                  :y (1+ +waterline-row+)
                  :dx 0 :dy 0))

(defun make-hud (world)
  "Create the persistent status bar at the top of WORLD."
  (make-creature :world world
                 :kind :hud
                 :frames (list (hud-art world))
                 :style (world-style world :bright-white :bold-p t)
                 :z 100
                 :policy :none
                 :x 1
                 :y 0
                 :dx 0
                 :dy 0))
