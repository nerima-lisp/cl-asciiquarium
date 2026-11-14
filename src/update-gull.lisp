;;;; src/update-gull.lisp -- a gull's flight: cruise, dive at a fish near the
;;;; surface, rise back to the sky with whatever it caught.
;;;;
;;;; State lives in the gull's data: :PHASE (:CRUISE, :DIVE, or :RISE),
;;;; :DIVE-READY-AT (an absolute tick), the dive's :TARGET fish, and the :PREY
;;;; it carries. The gull is a threat (+GULL-THREAT+) only during :DIVE.
(in-package #:cl-asciiquarium)

(defun captured-fish (world captor)
  "Return a :CAUGHT-FISH of WORLD that CATCH-EFFECT gave to CAPTOR, or NIL."
  (dolist (creature (world-%creatures world))
    (when (and (eq (creature-kind creature) :caught-fish)
               (eq (getf (creature-data creature) :captor) captor))
      (return creature))))

(defun gull-catch-effect (world gull fish)
  "The :EFFECT of a diving gull: CATCH-EFFECT on FISH, then disarm GULL so the
rest of this collision pass leaves any other fish under it alone."
  (catch-effect world gull fish)
  (setf (getf (creature-data gull) :threat) nil))

(defun gull-dive-target (world gull)
  "Return a live fish of WORLD within +GULL-DIVE-DEPTH+ rows below the
waterline whose columns, widened by one on each side, include GULL's beak."
  (let ((beak (+ (creature-x gull) +gull-beak-column+))
        (lowest (+ (world-waterline-row world) +gull-dive-depth+)))
    (dolist (creature (world-%creatures world))
      (when (and (alive-fish-p creature) (<= (creature-y creature) lowest))
        (let ((x (creature-x creature)))
          (when (<= (1- x) beak (+ x (creature-dimensions creature)))
            (return creature)))))))

(defun maybe-start-gull-dive (world gull)
  (let ((data (creature-data gull)))
    (when (>= (world-tick world) (getf data :dive-ready-at))
      (let ((target (gull-dive-target world gull)))
        (when (and target (zerop (random +gull-dive-odds+)))
          (setf (getf data :phase) :dive
                (getf data :target) target)
          (let ((entity (creature-entity gull)))
            (setf (entity-dx entity) 0
                  (entity-dy entity) 1))
          (arm-threat world gull +gull-threat+))))))

(defun start-gull-rise (gull)
  (let ((data (creature-data gull)))
    (setf (getf data :phase) :rise
          (getf data :target) nil
          (getf data :threat) nil
          (entity-dy (creature-entity gull)) -1)))

(defun gull-dive-tick (world gull)
  (let* ((data (creature-data gull))
         (entity (creature-entity gull))
         (target (getf data :target))
         (prey (captured-fish world gull)))
    (cond (prey
           (setf (getf data :prey) prey
                 (getf data :dive-ready-at) (+ (world-tick world) +gull-dive-cooldown-ticks+))
           (start-gull-rise gull))
          ;; A zero DY means the gull already spent one tick (and one
          ;; collision pass) at the bottom of its dive without a catch.
          ((or (not (alive-fish-p target)) (zerop (entity-dy entity)))
           (start-gull-rise gull))
          (t
           (when (>= (entity-y entity) (+ (world-waterline-row world) +gull-dive-depth+))
             (setf (entity-dy entity) 0))
           (incf (entity-x entity)
                 (clamp (- (+ (creature-x target) (* 0.5f0 (creature-dimensions target)))
                           (+ (entity-x entity) (* 0.5f0 (creature-dimensions gull))))
                        -1.0f0 1.0f0))))))

(defun gull-rise-tick (world gull)
  (let* ((data (creature-data gull))
         (entity (creature-entity gull))
         (sky-y (gull-sky-row world (getf data :slot))))
    (when (<= (entity-y entity) sky-y)
      (setf (entity-y entity) sky-y
            (entity-dy entity) 0
            (entity-dx entity) (getf data :cruise-dx)
            (getf data :phase) :cruise)
      (let ((prey (getf data :prey)))
        (when prey
          (setf (creature-removep prey) t
                (getf data :prey) nil))))))

(defun gull-tick (world gull)
  "The :TICK of a gull: leave at night (the :MOONLIGHT theme) or when a resize
leaves fewer than +GULL-MIN-SKY-ROWS+ sky rows, otherwise advance its :PHASE.
A cruising gull keeps to its slot's row of the current sky."
  (if (or (eq (world-theme world) :moonlight)
          (< (world-waterline-row world) +gull-min-sky-rows+))
      (setf (creature-removep gull) t)
      (let ((data (creature-data gull)))
        (ecase (getf data :phase)
          (:cruise
           (setf (entity-y (creature-entity gull)) (gull-sky-row world (getf data :slot)))
           (maybe-start-gull-dive world gull))
          (:dive (gull-dive-tick world gull))
          (:rise (gull-rise-tick world gull))))))
