;;;; src/bubble.lisp -- rising bubble trails emitted by fish.
(in-package #:cl-asciiquarium)

(defun %bubble-sprite-prototype (&optional (theme :abyss))
  "Select the immutable bubble sprite owner for THEME and render mode."
  (%themed-bubble-sprite-prototype theme))

(defun make-bubble (world fish)
  "Create a bubble CREATURE rising from FISH's current position in WORLD.
Policy :NONE: a bubble is removed explicitly by WORLD-ADVANCE once it reaches
+WATERLINE-ROW+ (see update.lisp), not by ENTITY's off-bounds callback, since
the waterline sits a few rows below the true top edge. The selected immutable
sprite prototype matches the current color mode; mutable entity state remains
per bubble."
  (multiple-value-bind (fish-width fish-height) (creature-dimensions fish)
    (declare (ignore fish-height))
    (make-creature
      :world
      world
      :kind
      :bubble
      :%sprite-prototype
      (%bubble-sprite-prototype (world-theme world))
      :frame-period
      4
      :z
      4
      :policy
      :none
      :x
      (+ (creature-x fish) (random (max 1 fish-width)))
      :y
      (1- (creature-y fish))
      :dx
      0
      :dy
      -0.5f0)))
