;;;; src/art-fish.lisp -- the fish factory: species lookup, color choice, and
;;;; MAKE-FISH/KILL-FISH/ALIVE-FISH-P. The species table and death-animation
;;;; art itself are data, in art-fish-data.lisp.
(in-package #:cl-asciiquarium)

(defun fish-species (name)
  (or (find name +fish-species+ :key #'fish-species-entry-name)
      (error 'asciiquarium-unknown-species :name name)))

(defun random-species-color (entry)
  "Return one of ENTRY's COLORS, chosen uniformly at random from its palette."
  (let ((colors (fish-species-entry-colors entry)))
    (nth (random (length colors)) colors)))

(defun fish-facing-and-dx (facing dx)
  "Return (VALUES FACING DX) for MAKE-FISH: an explicit FACING or DX wins
outright for its own value, but when neither is given, both derive from one
random choice, so 'which way it faces' and 'which way it swims' agree by
construction rather than by separately-defaulted expressions happening to
agree. Passing one argument without the other is only for a test that wants
to check facing and motion independently; ordinary spawning always leaves
both NIL."
  (let* ((resolved-facing (or facing (random-facing)))
         (speed (+ 1/3 (/ (random 4) 6))))
    (values resolved-facing
            (or dx (if (eq resolved-facing :right) speed (- speed))))))

(defun make-fish (world &key species x y dx facing)
  "Create a fish CREATURE in WORLD. SPECIES defaults to a random one of
+FISH-SPECIES+; X, Y, DX, and FACING default to a random position, lane, and
direction inside WORLD's swimmable band (below the waterline, above the
seaweed); see FISH-FACING-AND-DX for how FACING and DX default together."
  (let* ((entry (if species
                     (fish-species species)
                     (nth (random (length +fish-species+)) +fish-species+)))
         (width (world-width world))
         (height (world-height world))
         (lane-top 3)
         (lane-bottom (max lane-top (- height 4))))
    (multiple-value-bind (facing dx) (fish-facing-and-dx facing dx)
      (make-creature :world world
                      :kind :fish
                      :frames (list (fish-species-entry-art entry))
                      :facing facing
                      :style (solid-style (random-species-color entry))
                      :z 5
                      :policy :wrap
                      :x (or x (random (max 1 width)))
                      :y (or y (random-between lane-top lane-bottom))
                      :dx dx
                      :data (list :species (fish-species-entry-name entry)
                                  :bubble-timer (random-between 20 60))))))

(defun kill-fish (fish)
  "Convert a live FISH creature into its brief death animation, in place.
Idempotent: a fish already dying (checked via its :DYING data flag) is left
alone, so a fish inside more than one predator's bounding box in the same
tick is only killed once."
  (unless (getf (creature-data fish) :dying)
    (setf (creature-data fish) (list* :dying t (creature-data fish)))
    (%set-creature-frames fish (vector +fish-death-art+))
    (setf (creature-frame-index fish) 0)
    (setf (creature-ttl fish) +death-animation-ticks+)
    (setf (entity-dx (creature-entity fish)) 0)
    (setf (entity-dy (creature-entity fish)) 0)))

(defun alive-fish-p (creature)
  "True for a fish CREATURE not already in its death animation."
  (and (eq (creature-kind creature) :fish)
       (not (getf (creature-data creature) :dying))))
