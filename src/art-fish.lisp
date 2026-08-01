;;;; src/art-fish.lisp -- original fish species art and the fish factory.
;;;;
;;;; Three species, deliberately: the scope discipline in the project brief
;;;; asks that a creature type be cut rather than left to balloon, and three
;;;; well-behaved species plus one predator and two special guests is the
;;;; line this repository draws. All art below is original, authored for this
;;;; repository -- none of it is copied from the classic Perl `asciiquarium`.
;;;; Every species is authored facing right; MIRROR-SPRITE-TEXT (geometry.lisp)
;;;; produces the left-facing form, so there is exactly one drawing per
;;;; species rather than a left/right pair to keep in sync by hand.
(in-package #:cl-asciiquarium)

(defparameter +fish-species+
  (list
   (list :name :dart
         :art (format nil "  __~%>=(('>~%  ``")
         :color :bright-cyan)
   (list :name :puffer
         :art (format nil " .--.~%((o o))=>~%  `--'")
         :color :bright-yellow)
   (list :name :ribbon
         :art (format nil "  ..-.~%=<(o)===>~%  `-'")
         :color :bright-magenta))
  "Three original fish species: NAME identifies it, ART is its facing-right
sprite text, COLOR a cl-tty-kit NAMED-COLOR keyword for its foreground.")

(defun %fish-species (name)
  (or (find name +fish-species+ :key (lambda (entry) (getf entry :name)))
      (error 'unknown-species :name name)))

(defparameter +fish-death-art+
  (format nil " .-.~%(x x)~% `-'")
  "The brief death-animation frame a fish switches to when the shark or a
dropped anchor catches it. A single frame is enough: DEATH-ANIMATION-TICKS
below controls how long it stays on screen before being removed.")

(defparameter +death-animation-ticks+ 6
  "How many ticks a caught fish's death frame stays visible before removal.")

(defun random-between (low high)
  "Return a random integer in the inclusive range [LOW, HIGH], drawn from the
ambient CL:*RANDOM-STATE* so callers (and tests, via SB-EXT:SEED-RANDOM-STATE)
control reproducibility by binding *RANDOM-STATE*, never by this function
holding its own generator."
  (+ low (random (1+ (- high low)))))

(defun make-fish (world &key species x y dx)
  "Create a fish CREATURE in WORLD. SPECIES defaults to a random one of
+FISH-SPECIES+; X, Y, and DX default to a random position and lane inside
WORLD's swimmable band (below the waterline, above the seaweed) moving at a
random speed in a random direction."
  (let* ((entry (if species
                     (%fish-species species)
                     (nth (random (length +fish-species+)) +fish-species+)))
         (art (getf entry :art))
         (color (getf entry :color))
         (width (world-width world))
         (height (world-height world))
         (lane-top 3)
         (lane-bottom (max lane-top (- height 4)))
         (facing (if (zerop (random 2)) :left :right))
         (speed (+ 1/3 (/ (random 4) 6))))
    (make-creature :world world
                    :kind :fish
                    :frames (list art)
                    :facing facing
                    :style (make-style (style-fg (named-color color)))
                    :z 5
                    :policy :wrap
                    :x (or x (random (max 1 width)))
                    :y (or y (random-between lane-top lane-bottom))
                    :dx (or dx (if (eq facing :right) speed (- speed)))
                    :data (list :species (getf entry :name) :bubble-timer (random-between 20 60)))))

(defun %kill-fish (fish)
  "Convert a live FISH creature into its brief death animation, in place.
Idempotent: a fish already dying (checked via its :DYING data flag) is left
alone, so a fish inside more than one predator's bounding box in the same
tick is only killed once."
  (unless (getf (creature-data fish) :dying)
    (setf (creature-data fish) (list* :dying t (creature-data fish)))
    (setf (creature-frames fish) (vector +fish-death-art+))
    (setf (creature-frame-index fish) 0)
    (setf (creature-ttl fish) +death-animation-ticks+)
    (setf (entity-dx (creature-entity fish)) 0)
    (setf (entity-dy (creature-entity fish)) 0)))

(defun %alive-fish-p (creature)
  "True for a fish CREATURE not already in its death animation."
  (and (eq (creature-kind creature) :fish)
       (not (getf (creature-data creature) :dying))))
