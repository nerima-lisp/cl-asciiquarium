(in-package #:cl-asciiquarium)

(defun school-scatter (world sensor threat)
  (declare (ignore threat))
  (let* ((leader (getf (creature-data sensor) :leader))
         (members (getf (creature-data leader) :school-members))
         (until (+ (world-tick world) +school-scatter-ticks+)))
    (loop for fish across members
          when (alive-fish-p fish)
            do (let ((data (creature-data fish))
                     (entity (creature-entity fish)))
                 (setf (getf data :scatter-until) until
                       (entity-dx entity) (+ (getf data :school-dx)
                                             (getf data :scatter-dx))
                       (entity-dy entity) (getf data :scatter-dy))))))

(defun leave-school (fish &optional departing)
  (let ((data (creature-data fish))
        (entity (creature-entity fish)))
    (setf (getf data :leader) nil
          (getf data :school-members) nil
          (getf data :sense) nil
          (getf data :tick) (getf data :school-tick)
          (entity-dx entity) (getf data :school-dx)
          (entity-dy entity) 0)
    ;; A crossing ends at the far edge; a lost leader leaves ordinary fish.
    (unless departing
      (setf (entity-on-exit entity) (getf data :school-on-exit)))))

(defun school-exit (world fish entity edge)
  ;; ENTITY-TICK tests a point; a leftward fish still has its body to cross.
  (when (and (exit-edge-in-travel-direction-p entity edge)
             (or (not (eq edge :left))
                 (<= (+ (entity-x entity) (creature-dimensions fish)) 0)))
    (setf (getf (creature-data fish) :school-departed) t
          (creature-removep fish) t)
    (fish-stop-behaviour fish)
    (schedule-fish-refill world)))

(defun school-tick (world fish)
  (let* ((data (creature-data fish))
         (leader (getf data :leader))
         (entity (creature-entity fish)))
    (when (not (alive-fish-p leader))
      (leave-school fish (getf (creature-data leader) :school-departed))
      (funcall (getf data :tick) world fish)
      (return-from school-tick))
    (when (and (plusp (getf data :scatter-until))
               (>= (world-tick world) (getf data :scatter-until)))
      (setf (getf data :scatter-until) 0
            (entity-dx entity) (getf data :school-dx)
            (entity-dy entity) 0))
    (when (and (not (eq fish leader)) (zerop (getf data :scatter-until)))
      (incf (entity-x entity)
            (clamp (- (+ (creature-x leader) (getf data :offset-x))
                      (creature-x fish))
                   (- +school-rejoin-columns+) +school-rejoin-columns+))
      (incf (entity-y entity)
            (clamp (- (+ (creature-y leader) (getf data :offset-y))
                      (creature-y fish))
                   (- +school-rejoin-rows+) +school-rejoin-rows+)))
    (multiple-value-bind (top bottom)
        (fish-swim-limits world (nth-value 1 (%creature-dimensions-current fish)))
      (when (eq fish leader)
        (let ((low top) (high bottom))
          (loop for member across (getf data :school-members)
                for offset = (getf (creature-data member) :offset-y)
                do (setf top (max top (- low offset))
                         bottom (min bottom (- high offset))))))
      (setf (entity-y entity) (clamp (creature-y fish) top bottom)))
    (funcall (getf data :school-tick) world fish)))
