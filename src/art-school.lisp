(in-package #:cl-asciiquarium)

(defparameter +school-species+ #(:dart :guppy :clown))
(defparameter +school-offsets+ #((0 . 0) (-1 . -1) (-1 . 1)
                                (-2 . -2) (-2 . 2) (-3 . 0)))
(defparameter +school-sense+ '(26 nil school-scatter))
(defparameter +school-scatter-ticks+ 30)
(defparameter +school-rejoin-columns+ 1.0f0)
(defparameter +school-rejoin-rows+ 0.5f0)

(defun spawn-school-now (world)
  (let* ((species (aref +school-species+ (random (length +school-species+))))
         (leader (make-fish world :species species))
         (members (make-array (length +school-offsets+)))
         (facing (creature-facing leader))
         (dx (entity-dx (creature-entity leader)))
         (spacing (+ 2 (creature-dimensions leader)))
         (x (off-screen-entry facing (creature-dimensions leader)
                              (world-width world) (abs dx))))
    (multiple-value-bind (top bottom)
        (fish-swim-limits world (nth-value 1 (creature-dimensions leader)))
      (let ((y (floor (+ top bottom) 2)))
        (dotimes (index (length members))
          (let* ((offset (aref +school-offsets+ index))
                 (offset-x (* spacing (car offset) (if (eq facing :right) 1 -1)))
                 (offset-y (- (clamp (+ y (cdr offset)) top bottom) y))
                 (fish (if (zerop index) leader
                           (make-fish world :species species :facing facing :dx dx
                                           :x (+ x offset-x) :y (+ y offset-y))))
                 (data (creature-data fish))
                 (entity (creature-entity fish)))
            (setf (aref members index) fish
                  (entity-x entity) (+ x offset-x)
                  (entity-y entity) (+ y offset-y)
                  (creature-data fish)
                  (list* :leader leader :school-members members
                         :offset-x offset-x :offset-y offset-y
                         :school-dx dx :school-tick (getf data :tick)
                         :school-on-exit (lambda (moving edge)
                           (when (exit-edge-in-travel-direction-p moving edge)
                             (wrap-creature fish world edge)))
                         :school-departed nil :scatter-until 0
                         :scatter-dx (* (- index 2.5f0) 0.1f0 (if (eq facing :right) -1 1))
                         :scatter-dy (if (evenp index) -0.3f0 0.3f0)
                         :sense +school-sense+ data)
                  (getf (creature-data fish) :tick) 'school-tick
                  (entity-on-exit entity)
                  (lambda (moving edge) (school-exit world fish moving edge))))))
      ;; The leader must tick before the followers read its new position.
      (loop for index downfrom (1- (length members)) to 0
            do (%add-world-creature world (aref members index))))
    (values leader members)))
