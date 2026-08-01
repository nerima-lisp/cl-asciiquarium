;;;; src/art-guests.lisp -- special guests: a ship that drops an anchor, and a
;;;; line of ducks. These are the two special guests this v1 implements (see
;;;; docs/src/project/roadmap.md for the two explicitly cut: dolphins and a
;;;; sea monster). Per the interaction rule in the project brief, only the
;;;; ship's anchor is interactive (it can remove a fish directly beneath it);
;;;; the duck line is purely decorative.
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

(defun make-ship (world)
  "Create a ship CREATURE crossing WORLD at waterline level. Its :DROP-TICK
data entry is the absolute WORLD-TICK at which %MAYBE-DROP-ANCHOR (below)
creates its anchor, computed here so the drop lands near mid-screen regardless
of which edge the ship started from."
  (let* ((width (world-width world))
         (art-width (sprite-width +ship-art+))
         (facing (if (zerop (random 2)) :left :right))
         (speed 1/2)
         (start-x (if (eq facing :right) (- art-width) width))
         (travel-to-midpoint (round (/ (abs (- (/ width 2) start-x)) speed))))
    (make-creature :world world
                    :kind :ship
                    :frames (list +ship-art+)
                    :facing facing
                    :style (make-style (style-fg (named-color :white)))
                    :z 7
                    :policy :despawn
                    :x start-x
                    :y (max 0 (1- +waterline-row+))
                    :dx (if (eq facing :right) speed (- speed))
                    :data (list :drop-tick (+ (world-tick world) travel-to-midpoint)
                                :anchor-dropped nil))))

(defun %maybe-drop-anchor (world ship)
  "Create the anchor CREATURE once SHIP reaches its scheduled :DROP-TICK, in
WORLD. Guarded by :ANCHOR-DROPPED so a ship drops at most one anchor."
  (when (and (not (getf (creature-data ship) :anchor-dropped))
             (>= (world-tick world) (getf (creature-data ship) :drop-tick)))
    (setf (getf (creature-data ship) :anchor-dropped) t)
    (push (%make-anchor world ship) (world-creatures world))))

(defun %make-anchor (world ship)
  "Create an anchor CREATURE falling from SHIP's current position. It falls
(policy :NONE; its descent is stopped explicitly, see %ANCHOR-TICK below) to a
random :TARGET-DEPTH row, then stops and becomes :DROPPED (active for
COLLISION.LISP) for +ANCHOR-DROPPED-TICKS+ before despawning."
  (let* ((height (world-height world))
         (target-depth (random-between (+ +waterline-row+ 3)
                                        (max (+ +waterline-row+ 4) (- height 3)))))
    (make-creature :world world
                    :kind :anchor
                    :frames (list +anchor-art+)
                    :style (make-style (style-fg (named-color :bright-black)))
                    :z 3
                    :policy :none
                    :x (+ (creature-x ship) (round (/ (sprite-width +ship-art+) 2)))
                    :y +waterline-row+
                    :dx 0 :dy 1
                    :data (list :target-depth target-depth :dropped nil))))

(defparameter +anchor-dropped-ticks+ 30
  "How many ticks a dropped anchor stays in place (and interactive) before it
is winched back up and despawns.")

(defun %anchor-tick (anchor)
  "Advance ANCHOR's fall-then-settle state machine by one tick: once it
reaches its :TARGET-DEPTH, stop its descent, mark it :DROPPED, and start its
+ANCHOR-DROPPED-TICKS+ countdown."
  (let ((data (creature-data anchor)))
    (when (and (not (getf data :dropped))
               (>= (creature-y anchor) (getf data :target-depth)))
      (setf (entity-dy (creature-entity anchor)) 0)
      (setf (getf (creature-data anchor) :dropped) t)
      (setf (creature-ttl anchor) +anchor-dropped-ticks+))))

(defparameter +duck-line-art+
  (format nil "  _o)  _o)  _o)~% (___ (___ (___")
  "Original duck-line art: three ducks abreast, drawn as one sprite.")

(defun make-duck-line (world)
  "Create a decorative line-of-ducks CREATURE crossing WORLD near the
waterline. Purely decorative: it never participates in COLLISION.LISP."
  (let* ((width (world-width world))
         (art-width (sprite-width +duck-line-art+))
         (facing (if (zerop (random 2)) :left :right))
         (speed 1/2))
    (make-creature :world world
                    :kind :duck-line
                    :frames (list +duck-line-art+)
                    :facing facing
                    :style (make-style (style-fg (named-color :yellow)))
                    :z 7
                    :policy :despawn
                    :x (if (eq facing :right) (- art-width) width)
                    :y (max 0 (1- +waterline-row+))
                    :dx (if (eq facing :right) speed (- speed))
                    :data nil)))
