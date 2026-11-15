;;;; src/art-vent-data.lisp -- the vent's bubble plume and the crab on the
;;;; sand: their art, color roles, and the plume's threat row. Pure data;
;;;; art-vent.lisp holds the factories, update-vent.lisp the motion and the
;;;; plume's push.
(in-package #:cl-asciiquarium)

(defparameter +plume-half-width+ 4
  "How many columns the plume reaches on each side of the vent's mouth.")

(defparameter +plume-frame-count+ 4
  "How many frames the plume's rising-bubble loop has. Each bubble stream
repeats every +PLUME-FRAME-COUNT+ rows, so the last frame leads back into the
first.")

(defparameter +plume-frame-period+ 3
  "How many ticks each plume frame shows, so a bubble rises one row per
+PLUME-FRAME-PERIOD+ ticks.")

(defparameter +plume-stream-phases+ '(nil 1 nil 3 0 2 nil 0 nil)
  "One entry per plume column, left to right: NIL for a column without a
bubble stream, otherwise the row phase of that column's stream, so the
streams do not rise in step.")

(defparameter +plume-glyphs+ ".oO"
  "Bubble glyphs from the bottom third of the plume to the top third:
bubbles grow as they rise.")

(defparameter +plume-roles+ '((#\m :bubble))
  "The plume paints every bubble in the theme's bubble color.")

(defparameter +plume-threat+ '(:grip :body :effect push-effect :prey nil :alarm nil)
  "The :THREAT row (see collision.lisp) the plume carries: every fish
overlapping it is pushed upward by PUSH-EFFECT and stays alive.")

(defparameter +crab-frames+
  (list (format nil "(\\/)  (\\/)~% \\(o..o)/~%  /\\  /\\")
        (format nil "(\\/)  (\\/)~% \\(o..o)/~%  \\/  \\/"))
  "The crab's two walking frames, claws up and legs alternating. The art is
symmetric, so a crab walking left uses it unmirrored.")

(defparameter +crab-mask+ (format nil "bbbb  bbbb~% bbebbebb~%  ff  ff")
  "b the crab's body, e its eyes, f its legs; shared by both frames.")

(defparameter +crab-roles+ '((#\b :crab) (#\e :fg) (#\f :crab)))
