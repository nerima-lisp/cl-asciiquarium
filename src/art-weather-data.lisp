;;;; src/art-weather-data.lisp -- the glyphs, cloud motif, and color roles
;;;; of the weather sheets and the lightning flash. Pure data; art-weather.lisp
;;;; lays them out for a screen size. Every symbol outside ASCII has an
;;;; --ascii stand-in in +ASCII-SUBSTITUTIONS+ (palette.lisp).
(in-package #:cl-asciiquarium)

(defparameter +rain-drop-glyph+ #\')

(defparameter +rain-ripple-glyph+ #\∘)

(defparameter +storm-drop-glyph+ #\/)

(defparameter +storm-chop-glyph+ #\^)

(defparameter +storm-cloud-motif+
  '("  .--.     .-~-.    "
    ".(    ).  (     )   ")
  "The two rows of the storm's cloud band, repeated across the screen width.")

(defparameter +storm-cloud-mask-motif+
  '("  cccc     ccccc    "
    "cccccccc  ccccccc   ")
  "The cloud band's mask: each cloud is filled, so it hides the sun or moon
behind it.")

(defparameter +rain-sheet-roles+
  '((#\r "#9DB7C9") (#\o :waterhi))
  "r a raindrop, o a ripple on the water.")

(defparameter +storm-sheet-roles+
  '((#\c "#7A8494" "#262C36") (#\r "#B8C6D4") (#\w :waterhi))
  "c the dark cloud band, r slanted rain, w the choppy crests on the waterline.")

(defparameter +flash-roles+
  '((#\w "#F4F8FF" "#F4F8FF" :reverse) (#\z "#FFE08A" "#F4F8FF"))
  "w the white sky of a lightning flash, z the bolt.")
