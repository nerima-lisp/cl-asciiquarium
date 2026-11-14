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

(defparameter *bubble-sprite-prototypes*
  (let ((prototypes (make-hash-table :test #'equal)))
    (setf (gethash (list :abyss :colored) prototypes)
          +bubble-sprite-prototype+
          (gethash (list :abyss :monochrome) prototypes)
          +monochrome-bubble-sprite-prototype+)
    prototypes)
  "Prepared bubble prototypes keyed by visual theme and color mode.")

(defun %themed-bubble-sprite-prototype (theme)
  "Return the immutable bubble prototype for THEME and the effective color
mode. The 16-color and monochrome entries keep their original
(THEME :COLORED) and (THEME :MONOCHROME) keys; the RGB modes key by the mode
itself and paint the theme's :BUBBLE color."
  (let* ((theme (parse-visual-theme theme))
         (mode (effective-color-mode))
         (key (list theme (case mode
                            (:mono :monochrome)
                            (:ansi16 :colored)
                            (t mode)))))
    (or (gethash key *bubble-sprite-prototypes*)
        (setf (gethash key *bubble-sprite-prototypes*)
              (%make-bubble-sprite-prototype
               (case mode
                 (:mono nil)
                 (:ansi16 (visual-style theme :bright-white))
                 (t (color-style :bubble :theme theme))))))))
