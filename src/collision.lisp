;;;; src/collision.lisp -- the single collision pass.
;;;;
;;;; Per the project's interaction rule, only two things ever remove a fish:
;;;; the shark, and a dropped anchor directly above it. Every other creature
;;;; pair is deliberately non-interactive -- this file does not, and should
;;;; not, grow into an NxN interaction matrix between every creature kind.
(in-package #:cl-asciiquarium)


(defun apply-collisions (world)
  "Kill fish that overlap sharks or dropped anchors. Active predators and live
fish validate their mutable sprite caches once before the nested collision scan."
  (let ((creatures (world-%creatures world)))
    (unless (loop for creature in creatures
                  thereis (case (creature-kind creature)
                            (:shark t)
                            (:anchor (getf (creature-data creature) :dropped))))
      (return-from apply-collisions world))
    (dolist (creature creatures)
      (when (or (case (creature-kind creature)
                  (:shark t)
                  (:anchor (getf (creature-data creature) :dropped)))
                (alive-fish-p creature))
        (%ensure-creature-caches-current creature)))
    (dolist (predator creatures)
      (when (case (creature-kind predator)
              (:shark t)
              (:anchor (getf (creature-data predator) :dropped)))
        (multiple-value-bind (x y width height)
            (%creature-bounds-current predator)
          (dolist (fish creatures)
            (when (alive-fish-p fish)
              (multiple-value-bind (fish-x fish-y fish-width fish-height)
                  (%creature-bounds-current fish)
                (when (rects-overlap-p x y width height
                                       fish-x fish-y fish-width fish-height)
                  (kill-fish fish))))))))
    world))
