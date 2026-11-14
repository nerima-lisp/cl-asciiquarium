;;;; src/art-octopus-data.lisp -- the octopus under the rock, its tentacle,
;;;; and its ink cloud: art, masks, color roles, and the tentacle's threat
;;;; row. Pure data; art-octopus.lisp builds the creatures from it.
(in-package #:cl-asciiquarium)

(defparameter +octopus-art+ (format nil " .--.~%(o  o)")
  "The octopus's head, the only part that peeks over the rock.")

(defparameter +octopus-mask+ (format nil " bbbb~%be  eb")
  "b the octopus, e its eyes.")

(defparameter +octopus-roles+ '((#\b :octopus) (#\e :fg)))

(defparameter +tentacle-max-length+ 16
  "The longest a tentacle grows, counting the columns tucked under the rock.")

(defparameter +tentacle-frames+
  (loop for length from 1 to +tentacle-max-length+
        collect (let ((line (make-string length)))
                  (dotimes (column length line)
                    (setf (char line column) (if (evenp column) #\( #\))))))
  "One frame per tentacle length, 1 to +TENTACLE-MAX-LENGTH+ columns of the
wavy ()() line, so growing or retracting only changes the frame index.")

(defparameter +tentacle-masks+
  (mapcar (lambda (frame) (make-string (length frame) :initial-element #\o))
          +tentacle-frames+))

(defparameter +tentacle-roles+ '((#\o :octopus)))

(defparameter +tentacle-threat+
  '(:grip (:front 1) :effect tentacle-catch-effect :prey nil :alarm t)
  "The :THREAT row (see collision.lisp) of a tentacle: its tip catches any
species (TENTACLE-CATCH-EFFECT), and creatures that sense threats notice it.")

(defparameter +ink-frames+
  (list (format nil " ▒▒▒▒▒▒ ~%▒▒▒▒▒▒▒▒~% ▒▒▒▒▒▒ ")
        (format nil "  ▒ ▒▒  ~%▒ ▒▒ ▒ ▒~%  ▒▒ ▒  ")
        (format nil "   ▒    ~% ▒   ▒  ~%    ▒   "))
  "The ink cloud, densest first: it thins out frame by frame.")

(defparameter +ink-masks+ (mapcar (lambda (frame) (%glyph-mask frame #\i)) +ink-frames+))

(defparameter +ink-roles+ '((#\i :ink)))
