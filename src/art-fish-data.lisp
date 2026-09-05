;;;; src/art-fish-data.lisp -- original fish species art: the
;;;; FISH-SPECIES-ENTRY shape and its five-entry table, plus the shared
;;;; death-animation frame every species switches to when caught. Pure data;
;;;; art-fish.lisp holds the logic that reads it (species lookup, color
;;;; choice, and the MAKE-FISH/KILL-FISH factory and mutator).
;;;;
;;;; The five fish species and their art are defined here. All art below is
;;;; original to this repository; none is copied from the classic Perl
;;;; `asciiquarium`.
;;;; Every species is authored facing right; MIRROR-SPRITE-TEXT (geometry.lisp)
;;;; produces the left-facing form, so there is exactly one drawing per
;;;; species rather than a left/right pair to keep in sync by hand.
(in-package #:cl-asciiquarium)

(defstruct (fish-species-entry (:constructor make-fish-species-entry (name art colors)))
  "One entry of +FISH-SPECIES+: NAME identifies it, ART is its facing-right
sprite text, COLORS a non-empty list of cl-tty-kit NAMED-COLOR keywords one of
which MAKE-FISH picks at random for a spawned individual's foreground -- so two
fish of the same species need not be identically colored. A struct rather than
a plist so a typo'd slot (:COLOUR for :COLORS, say) is a compile-time error
instead of a silently NIL GETF."
  (name nil :type keyword)
  (art "" :type string)
  (colors nil :type list))

(defparameter +fish-species+
  (list
   (make-fish-species-entry :dart (format nil "  __~%>=(('>~%  ``")
                             '(:bright-cyan :cyan))
   (make-fish-species-entry :puffer (format nil " .--.~%((o o))=>~%  `--'")
                             '(:bright-yellow :yellow))
   (make-fish-species-entry :ribbon (format nil "  ..-.~%=<(o)===>~%  `-'")
                             '(:bright-magenta :magenta))
   (make-fish-species-entry :angel (format nil "  /\\~%<((*>~%  \\/")
                             '(:bright-red :red :bright-yellow))
   (make-fish-species-entry :guppy (format nil " _~%>=(o)>~% `")
                             '(:bright-green :green :bright-blue)))
  "The five original fish species this repository draws.")

(defparameter +fish-death-art+
  (format nil " .-.~%(x x)~% `-'")
  "The brief death-animation frame a fish switches to when the shark or a
dropped anchor catches it. A single frame is enough: DEATH-ANIMATION-TICKS
below controls how long it stays on screen before being removed.")

(defparameter +death-animation-ticks+ 6
  "How many ticks a caught fish's death frame stays visible before removal.")
