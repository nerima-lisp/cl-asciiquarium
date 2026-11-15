;;;; src/art-submarine-data.lisp -- the submarine's art, masks, colors, threat
;;;; rows, and the sonar ring's frames. Pure data; art-submarine.lisp builds the
;;;; creatures from it.
(in-package #:cl-asciiquarium)

(defparameter +sub-art+
  (format nil "      |_~%  ____|____~%=(o  o  o  o)>~%  `---------'")
  "Original submarine art, authored facing right.")

(defparameter +sub-mask+
  (format nil "      tt~%  bbbbfbbbb~%tbe  e  e  ebb~%  fffffffffff")
  "The role of each cell of +SUB-ART+, line for line.")

(defparameter +sub-roles+
  '((#\b :submarine) (#\t :submarine) (#\f :muted) (#\e :fg))
  "%RESOLVE-ROLES roles for +SUB-MASK+: a yellow hull and tower, a muted keel
and deck, and light portholes.")

(defparameter +sub-threat+ '(:grip :body :effect nil :prey nil :alarm t)
  "The submarine harms no fish, but creatures that sense threats notice it, so a
school within its sense range scatters.")

(defparameter +sonar-threat+ '(:grip :body :effect stun-effect :prey nil :alarm nil)
  "A sonar ring stuns every live fish its bounding box covers (STUN-EFFECT).")

(defparameter +sonar-max-radius+ 12
  "How many columns the widest sonar ring reaches out from its centre.")

(defparameter +sonar-frames+
  (let ((height (nth-value 1 (sprite-dimensions +sub-art+))))
    (loop for radius from 1 to +sonar-max-radius+
          for line = (format nil "(~A)" (make-string (1- (* 2 radius))
                                                     :initial-element #\Space))
          collect (format nil "~{~A~^~%~}" (make-list height :initial-element line))))
  "The sonar ring as it widens, one frame per radius from 1 to
+SONAR-MAX-RADIUS+: a `(' and a `)' 2*radius columns apart on every row of the
submarine. Built once and shared by every ring.")
