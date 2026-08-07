;;;; src/collision.lisp -- the single collision pass.
;;;;
;;;; Per the project's interaction rule, only two things ever remove a fish:
;;;; the shark, and a dropped anchor directly above it. Every other creature
;;;; pair is deliberately non-interactive -- this file does not, and should
;;;; not, grow into an NxN interaction matrix between every creature kind.
(in-package #:cl-asciiquarium)

(declaim (inline %cache-collision-bounds %cached-collision-overlap-p))

(defun %cache-collision-bounds (creature)
  (multiple-value-bind (left top width height) (%creature-bounds-current creature)
    (setf (creature-collision-left creature) left
          (creature-collision-top creature) top
          (creature-collision-width creature) width
          (creature-collision-height creature) height))
  creature)

(defun %cached-collision-overlap-p (first second)
  (let ((first-left (creature-collision-left first))
        (first-top (creature-collision-top first))
        (first-width (creature-collision-width first))
        (first-height (creature-collision-height first))
        (second-left (creature-collision-left second))
        (second-top (creature-collision-top second))
        (second-width (creature-collision-width second))
        (second-height (creature-collision-height second)))
    (and (< first-left (+ second-left second-width))
         (< second-left (+ first-left first-width))
         (< first-top (+ second-top second-height))
         (< second-top (+ first-top first-height)))))

(defun apply-collisions (world)
  "Kill fish that overlap sharks or dropped anchors, caching each participant bounds once per pass."
  (let ((creatures (world-%creatures world))
        (predators (world-collision-predators world)))
    (unless (%world-has-active-predator-p world)
      (return-from apply-collisions world))
    (dolist (creature creatures)
      (when (alive-fish-p creature)
        (%cache-collision-bounds creature)))
    (dolist (predator predators)
      (when (%active-predator-p predator)
        (%cache-collision-bounds predator)
        (dolist (candidate creatures)
          (when (and (alive-fish-p candidate)
                     (%cached-collision-overlap-p predator candidate))
            (kill-fish candidate)))))
    world))
