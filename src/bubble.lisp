;;;; src/bubble.lisp -- rising bubble trails emitted by fish.
(in-package #:cl-asciiquarium)

(defparameter +bubble-art-frames+ (list "." "o" "O")
  "The three-frame looping animation a rising bubble cycles through, widening
slightly as it ascends.")

(defparameter +bubble-style+ (make-style (style-fg (named-color :bright-white))) "The canonical drawing style copied into each bubble creature.")

  (defparameter +bubble-sprite-prototype+
  (make-creature :kind :bubble-sprite-prototype
                 :frames (mapcar #'copy-seq +bubble-art-frames+)
                 :style (copy-tree +bubble-style+)
                 :%trusted-frames-p t
                 :%trusted-style-p t
                 :x 0 :y 0 :policy :none)
  "A private owner for immutable prepared bubble frames and blit screens.")

  (defun make-bubble (world fish)
    "Create a bubble CREATURE rising from FISH's current position in WORLD.
Policy :NONE: a bubble is removed explicitly by WORLD-ADVANCE once it reaches
+WATERLINE-ROW+ (see update.lisp), not by ENTITY's off-bounds callback, since
the waterline sits a few rows below the true top edge. Prepared frame data is
shared from +BUBBLE-SPRITE-PROTOTYPE+; STYLE is still resolved fresh through
SOLID-STYLE on every call so a bubble honors the current *MONOCHROME* setting
rather than the one in effect when +BUBBLE-SPRITE-PROTOTYPE+ was built;
mutable entity state remains per bubble."
    (multiple-value-bind (fish-width fish-height) (creature-dimensions fish)
      (declare (ignore fish-height))
      (let ((bubble
            (make-creature :world world
                           :kind :bubble
                           :%sprite-prototype +bubble-sprite-prototype+
                           :frame-period 4
                           :z 4
                           :policy :none
                           :x (+ (creature-x fish) (random (max 1 fish-width)))
                           :y (1- (creature-y fish))
                           :dx 0
                           :dy -1/2)))
        (%set-creature-style bubble (solid-style :bright-white) :escaped-p nil)
        bubble)))
