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

(defun make-waterline (world)
  "Create the waterline decoration spanning the full width of WORLD."
  (make-creature :world world
                  :kind :waterline
                  :frames (list (waterline-art (world-width world)))
                  :style (solid-style :bright-blue)
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
                    :style (solid-style :yellow)
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
                    :style (solid-style :green)
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
  (declare (ignore world))
  (make-creature :kind :help-overlay
                  :frames (list +help-overlay-art+)
                  :style (solid-style :bright-white)
                  :z 99
                  :policy :none
                  :x 1
                  :y (1+ +waterline-row+)
                  :dx 0 :dy 0))
