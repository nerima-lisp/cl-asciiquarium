;;;; src/art-fisher-data.lisp -- the fisher's boat art and mask, the hook's
;;;; threat row, and the fishing tuning. Pure data; art-fisher.lisp builds the
;;;; boat, line, hook, and cheer from it, and update-fisher.lisp runs them.
(in-package #:cl-asciiquarium)

(defparameter +fisher-art+
  (format nil "  o  /~% /|\\/~%\\____/")
  "Original fisher art, authored facing right: the fisher holding a rod over
a small boat. The rod tip is the top right corner.")

(defparameter +fisher-mask+
  (format nil "  e  t~% bbbt~%ffffff")
  "Mask for +FISHER-ART+: head e, body b, rod t, hull f.")

(defparameter +fisher-colors+ '(:fg :castle :sandhi :accent)
  "The (BODY FIN TAIL EYE) color set of the fisher: figure, hull, rod, head.")

(defparameter +fisher-boat-rise+ 2
  "Rows the boat's top sits above the waterline, so its hull is on the water.
Its :BOAT-RISE for the storm sway (BOAT-SWAY-ROW, update-weather.lisp).")

(defparameter +fisher-head-column+ 2
  "Column of the fisher's head in the right-facing art.")

(defparameter +fishing-line-glyph+ "│")

(defparameter +fishing-hook-art+ "J")

(defparameter +fisher-cheer-art+ "!")

(defparameter +hook-threat+ '(:grip :body :effect hook-catch-effect :prey nil :alarm nil)
  "The :THREAT row a hook carries while it fishes: it catches one fish that
touches it and alarms nobody.")

(defparameter +fisher-boat-speed+ 0.5f0
  "Columns per tick the boat moves while arriving and leaving.")

(defparameter +fishing-line-speed+ 0.5f0
  "Rows per tick the hook sinks and is reeled up.")

(defparameter +fisher-wait-ticks+ 80
  "Ticks the hook rests on the bottom before it is reeled up empty.")

(defparameter +fisher-cheer-ticks+ 30
  "Ticks the `!' stays above the fisher after a catch; the boat waits as long.")
