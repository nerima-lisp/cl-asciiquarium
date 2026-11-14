(in-package #:cl-asciiquarium)

(defparameter +egg-frames+ #("°"))
(defparameter +fry-frames+ #("°>"))
(defparameter +heart-frames+ #("♥"))
(defparameter +courting-threat+
  '(:grip :body :effect brood-effect :prey nil :alarm nil))

(defparameter *brood-sprite-prototypes* (make-hash-table :test #'equal))

(defun %brood-sprite-prototype (kind theme)
  (let* ((key (list kind theme (effective-color-mode) *ascii*))
         (frames (ecase kind
                   (:egg +egg-frames+)
                   (:heart +heart-frames+)))
         (color (if (eq kind :heart) :bright-red :bright-white)))
    (or (gethash key *brood-sprite-prototypes*)
        (setf (gethash key *brood-sprite-prototypes*)
              (make-creature :kind :brood-sprite-prototype
                             :frames frames :style (visual-style theme color)
                             :x 0 :y 0 :policy :none)))))
