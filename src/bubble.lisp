;;;; src/bubble.lisp -- rising bubble trails emitted by fish.
(in-package #:cl-asciiquarium)

(defparameter +bubble-art-frames+ (list "." "o" "O")
  "The three-frame looping animation a rising bubble cycles through, widening
slightly as it ascends.")

(defparameter +bubble-style+ (make-style (style-fg (named-color :bright-white)))
  "The canonical colored style held by the immutable bubble prototype.")

(defun %make-bubble-sprite-prototype (style)
  "Create an immutable prepared sprite owner for one bubble color mode."
  (make-creature
    :kind
    :bubble-sprite-prototype
    :frames
    (mapcar #'copy-seq +bubble-art-frames+)
    :style
    style
    :%trusted-frames-p
    t
    :%trusted-style-p
    t
    :x
    0
    :y
    0
    :policy
    :none))

(defparameter +bubble-sprite-prototype+ (%make-bubble-sprite-prototype (copy-tree +bubble-style+))
  "Prepared colored bubble frames and blit screens.")

(defparameter +monochrome-bubble-sprite-prototype+ (%make-bubble-sprite-prototype nil)
  "Prepared monochrome bubble frames and blit screens.")

(defun %bubble-sprite-prototype ()
  "Select the immutable bubble sprite owner for the current render mode."
  (if *monochrome* +monochrome-bubble-sprite-prototype+
    +bubble-sprite-prototype+))

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
      (%bubble-sprite-prototype)
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
