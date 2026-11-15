;;;; src/update-vent.lisp -- what the vent's plume does to a fish (it pushes it
;;;; upward) and the crab's walk. The push itself is the collision pass applying
;;;; +PLUME-THREAT+.
(in-package #:cl-asciiquarium)

(defparameter +plume-push-rows-per-tick+ 0.2f0
  "How far the plume lifts an overlapping fish each tick.")

(defun push-effect (world plume fish)
  "Lift FISH +PLUME-PUSH-ROWS-PER-TICK+ rows, stopping at the top of WORLD's
swim band. The push runs after every creature's tick, so what a fish's tick
derives from its row is lifted here too: a drifting fish's drift origin
(FISH-DRIFT-TICK resets the row from it) and a lantern's glow (placed by
UPDATE-LANTERN-GLOW), which would otherwise trail the lantern by a tick."
  (declare (ignore plume))
  (let* ((top (world-swim-band world))
         (data (creature-data fish))
         (entity (creature-entity fish))
         (old-y (entity-y entity))
         (new-y (max top (- old-y +plume-push-rows-per-tick+)))
         (glow (getf data :glow)))
    (setf (entity-y entity) new-y)
    (when (getf data :drift-phase)
      (setf (getf data :drift-y) (max top (- (getf data :drift-y) +plume-push-rows-per-tick+))))
    (when glow
      (incf (entity-y (creature-entity glow)) (- new-y old-y)))))

(defun crab-tick (world crab)
  "Turn CRAB around once it has walked into either screen edge."
  (let* ((entity (creature-entity crab))
         (dx (entity-dx entity))
         (x (entity-x entity)))
    (when (if (minusp dx)
              (<= x 0)
              (>= (+ x (creature-dimensions crab)) (world-width world)))
      (setf (entity-dx entity) (- dx)))))
