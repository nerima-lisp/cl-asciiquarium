;;;; src/bubble.lisp -- rising bubble trails emitted by fish.
(in-package #:cl-asciiquarium)

(defparameter +bubble-art-frames+ (list "." "o" "O")
  "The three-frame looping animation a rising bubble cycles through, widening
slightly as it ascends.")

(defun make-bubble (world fish)
  "Create a bubble CREATURE rising from FISH's current position in WORLD.
Policy :NONE: a bubble is removed explicitly by WORLD-ADVANCE once it reaches
+WATERLINE-ROW+ (see update.lisp), not by ENTITY's off-bounds callback, since
the waterline sits a few rows below the true top edge."
  (multiple-value-bind (fish-width fish-height) (creature-dimensions fish)
    (declare (ignore fish-height))
    (make-creature :world world
                    :kind :bubble
                    :frames +bubble-art-frames+
                    :frame-period 4
                    :style (make-style (style-fg (named-color :bright-white)))
                    :z 4
                    :policy :none
                    :x (+ (creature-x fish) (random (max 1 fish-width)))
                    :y (1- (creature-y fish))
                    :dx 0
                    :dy -1/2)))
