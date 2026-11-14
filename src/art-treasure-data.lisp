;;;; src/art-treasure-data.lisp -- the open treasure chest, the diver, and the
;;;; diver's dinghy. Pure data; art-treasure.lisp builds the creatures. Masks
;;;; follow art-decor-data.lisp: each has its art's exact line shape.
(in-package #:cl-asciiquarium)

(defparameter +chest-open-art+ (format nil "   _____~%  /____/~% |$$$$$$|~% |______|")
  "The treasure chest with its lid raised, one row taller than +CHEST-ART+.")

(defparameter +chest-open-mask+ (format nil "   kkkkk~%  kkkkkk~% wggggggw~% wwwwwwww")
  "k the lid, w chest wood, g gold.")

(defparameter +chest-closed-frames+ (list +chest-art+))

(defparameter +chest-closed-masks+ (list +chest-mask+))

(defparameter +chest-open-frames+ (list +chest-open-art+))

(defparameter +chest-open-masks+ (list +chest-open-mask+))

(defparameter +diver-art+ (format nil " _~%(o)~%/#\\~%/ \\")
  "The diver on the rope, empty-handed.")

(defparameter +diver-mask+ (format nil " f~%fef~%bbb~%b b")
  "b the suit, f the snorkel and helmet, e the visor.")

(defparameter +diver-carrying-art+ (format nil " _~%(o)~%/#\\$~%/ \\")
  "The diver climbing back with a gold coin in hand, held toward the chest.")

(defparameter +diver-carrying-mask+ (format nil " f~%fef~%bbbg~%b b")
  "As +DIVER-MASK+, g the coin.")

(defparameter +diver-frames+ (list " " +diver-art+ +diver-carrying-art+)
  "Frame 0 hides the diver (in the dinghy), 1 is the diver on the rope, 2 the
diver carrying the coin. DIVER-TICK picks the frame from the dinghy's phase.")

(defparameter +diver-masks+ (list " " +diver-mask+ +diver-carrying-mask+))

(defparameter +diver-roles+ '((#\b :fg) (#\f :accent) (#\e :window) (#\g :gold)))

(defparameter +dinghy-art+ (format nil "  _o_~%\\_____/")
  "The diver's dinghy, its boatman in the middle.")

(defparameter +dinghy-mask+ (format nil "  beb~%fffffff")
  "b the boatman, e the boatman's face, f the wooden hull.")

(defparameter +dinghy-roles+ '((#\b :fg) (#\e :window) (#\f :chest-wood)))
