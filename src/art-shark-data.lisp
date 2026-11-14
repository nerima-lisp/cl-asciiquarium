;;;; src/art-shark-data.lisp -- the shark's threat row and its well-fed art.
;;;; Pure data; art-shark.lisp builds the shark from it.
(in-package #:cl-asciiquarium)

(defparameter +shark-threat+ '(:grip (:front 2) :effect shark-eat-effect :prey nil :alarm t)
  "The :THREAT row (see collision.lisp) every shark is created with: its mouth,
the leading two columns, eats any species (see SHARK-EAT-EFFECT), and creatures that sense threats
notice it.")

(defparameter +shark-big-art+
  (format nil "       /^\\~%==<{{(o..o)}}===>~%       \\_/")
  "Original art for a shark that has eaten +SHARK-MEALS-TO-GROW+ fish,
authored facing right like +SHARK-ART+ and drawn in the same single color.")
