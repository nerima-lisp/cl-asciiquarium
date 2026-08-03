;;;; src/art-guests-data.lisp -- special-guest art and their numeric
;;;; constants (cooldown/arc/segment tuning). Pure data; art-guests.lisp
;;;; holds the DEFINE-OFF-SCREEN-GUEST macro, the four factories it
;;;; generates from this data, and the two hand-written factories
;;;; (MAKE-ANCHOR, MAKE-MONSTER-SEGMENT) that don't fit its shape.
(in-package #:cl-asciiquarium)

(defparameter +ship-art+
  ;; The hull's baseline is spelled with hyphens, not a run of `=' -- 7 or
  ;; more consecutive `=' characters reads as a git merge-conflict marker to
  ;; the org's pre-commit hook (and to a human skimming a diff); an earlier
  ;; draft of this line used nine and tripped it on this repository's first
  ;; commit attempt.
  (format nil "    |~%   /|\\~%  / | \\~% /__|__\\~%-o-o-o-o-")
  "Original ship art, authored facing right, mast and hull.")

(defparameter +anchor-art+
  (format nil " _|_~%( o )~% \\_/")
  "Original anchor art, dropped straight down from a ship.")

(defparameter +anchor-dropped-ticks+ 30
  "How many ticks a dropped anchor stays in place (and interactive) before it
is winched back up and despawns.")

(defparameter +duck-line-art+
  (format nil "  _o)  _o)  _o)~% (___ (___ (___")
  "Original duck-line art: three ducks abreast, drawn as one sprite.")

(defparameter +dolphin-art+
  (format nil " __~%(__)o>~%  ``")
  "Original dolphin art, authored facing right: an arched back, a blowhole,
and a tail fluke.")

(defparameter +dolphin-arc-amplitude+ 3
  "How many rows a dolphin's leap carries it above and below its baseline; see
DOLPHIN-TICK in update.lisp.")

(defparameter +dolphin-arc-period+ 24
  "How many ticks one full leap cycle (up and back down) takes; see
DOLPHIN-TICK in update.lisp.")

(defparameter +sea-monster-head-art+
  (format nil " ___~%( o >~% `-'")
  "Original sea-monster head art, authored facing right: a single eye and an
open mouth.")

(defparameter +sea-monster-segment-art+ "^^^"
  "Original sea-monster body-segment art: a single wave-hump, echoing the
waterline's own `^^~~' motif so a trailing segment reads as part of the same
water surface the monster is breaking through.")

(defparameter +sea-monster-segment-count+ 4
  "How many :MONSTER-SEGMENT CREATUREs MAKE-SEA-MONSTER's caller (SPAWN-GUEST,
spawn.lisp) trails behind the head.")

(defparameter +sea-monster-segment-spacing+ 4
  "Horizontal distance, in columns, between consecutive sea-monster segments.")
