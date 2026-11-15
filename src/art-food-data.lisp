;;;; src/art-food-data.lisp -- the food grain's art, threat row, and shared
;;;; sprite prototypes.
(in-package #:cl-asciiquarium)

(defparameter +food-art+ "•"
  "A food grain. ASCII-TEXT turns it into `o' under --ascii.")

(defparameter +food-threat+
  '(:grip :body :effect food-eaten-effect :prey nil :alarm nil)
  "The :THREAT row every grain carries: the first live fish overlapping it
eats it (FOOD-EATEN-EFFECT, update-food.lisp) and stays alive. No alarm, so
schools do not scatter and puffers do not inflate at food.")

(defvar *food-sprite-prototypes* (make-hash-table :test #'equal)
  "Prepared food prototypes keyed by (THEME COLOR-MODE ASCII).")

(defun %food-sprite-prototype (theme)
  "Return the immutable food prototype for THEME, the effective color mode,
and *ASCII*, building it on first use. The color is the fixed :FOOD color over
THEME's background."
  (let ((key (list theme (effective-color-mode) *ascii*)))
    (or (gethash key *food-sprite-prototypes*)
        (setf (gethash key *food-sprite-prototypes*)
              (make-creature :kind :food-sprite-prototype
                             :frames (list (copy-seq +food-art+))
                             :style (color-style :food :theme theme)
                             :%trusted-frames-p t
                             :%trusted-style-p t
                             :x 0 :y 0 :policy :none)))))
