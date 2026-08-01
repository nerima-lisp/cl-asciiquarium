;;;; src/collision.lisp -- the single collision pass.
;;;;
;;;; Per the project's interaction rule, only two things ever remove a fish:
;;;; the shark, and a dropped anchor directly above it. Every other creature
;;;; pair is deliberately non-interactive -- this file does not, and should
;;;; not, grow into an NxN interaction matrix between every creature kind.
(in-package #:cl-asciiquarium)

(defun apply-collisions (world)
  "Kill every alive fish overlapping a shark or a dropped anchor in WORLD,
returning WORLD. A simple double loop over WORLD-CREATURES is enough: the
population is small (single digits of predators/anchors against a similarly
small fish count), so there is no need for spatial partitioning here."
  (let ((creatures (world-creatures world)))
    (dolist (predator creatures)
      (when (eq (creature-kind predator) :shark)
        (dolist (fish creatures)
          (when (and (%alive-fish-p fish) (creatures-overlap-p predator fish))
            (%kill-fish fish)))))
    (dolist (anchor creatures)
      (when (and (eq (creature-kind anchor) :anchor) (getf (creature-data anchor) :dropped))
        (dolist (fish creatures)
          (when (and (%alive-fish-p fish) (creatures-overlap-p anchor fish))
            (%kill-fish fish)))))
    world))
