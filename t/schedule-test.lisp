;;;; Natural event coverage over ten minutes at the default 20 ticks/second.
(in-package #:cl-asciiquarium/test)

(defparameter +schedule-events+
  '(:shark :predation :school :puffer :lantern :egg :chest :dinghy
    :sonar :hook :plume :tentacle :ink :anchor :rain :storm :flash
    :abyss :coral :moonlight :gull))

(defun schedule-observations (world)
  (let ((observations (list (cons (cl-asciiquarium::world-weather world) :world)
                            (cons (cl-asciiquarium::world-theme world) :world))))
    (dolist (creature (cl-asciiquarium::world-%creatures world) observations)
      (let ((kind (cl-asciiquarium::creature-kind creature))
            (data (cl-asciiquarium::creature-data creature)))
        (when (member kind '(:shark :egg :dinghy :sonar :hook :tentacle :ink :anchor :flash))
          (push (cons kind creature) observations))
        (when (eq kind :fish)
          (when (getf data :dying) (push (cons :predation creature) observations))
          (when (getf data :inflated) (push (cons :puffer creature) observations))
          (when (getf data :leader)
            (pushnew (cons :school (getf data :leader)) observations :test #'equal)))
        (when (and (eq kind :chest) (eq (getf data :state) :open))
          (push (cons :chest creature) observations))
        (when (and (eq kind :caught-fish)
                   (eq (cl-asciiquarium::creature-kind (getf data :captor)) :gull))
          (push (cons :gull creature) observations))))))

(defun schedule-steering-p (world fish)
  (or (getf (cl-asciiquarium::creature-data fish) :leader)
      (not (zerop (entity-dy (cl-asciiquarium::creature-entity fish))))
      (find :food (cl-asciiquarium::world-%creatures world)
            :key #'cl-asciiquarium::creature-kind)
      (find fish (cl-asciiquarium::world-%creatures world)
            :key (lambda (creature)
                   (getf (cl-asciiquarium::creature-data creature) :lure-target)))))

(defun schedule-fish-before-tick (world)
  (loop for fish in (cl-asciiquarium::world-%creatures world)
        for data = (cl-asciiquarium::creature-data fish)
        when (cl-asciiquarium::alive-fish-p fish)
          collect (list fish (creature-y fish) (not (schedule-steering-p world fish))
                        (let ((target (getf data :lure-target)))
                          (when (and target (cl-asciiquarium::alive-fish-p target)
                                     (> (getf data :lure-next) (1+ (world-tick world))))
                            target)))))

(defun schedule-effects (world before)
  (let ((observations nil))
    (dolist (entry before observations)
      (destructuring-bind (fish y unsteered target) entry
        (let ((data (cl-asciiquarium::creature-data fish)))
          (when (cl-asciiquarium::alive-fish-p fish)
            ;; No species filter: omit movement-ambiguous and clamp ticks.
            ;; Four scaled single-float epsilons cover subtraction rounding.
            (when (and unsteered
                       (not (schedule-steering-p world fish))
                       (> (creature-y fish) (world-swim-band world))
                       (< (abs (- (- y (creature-y fish))
                                  cl-asciiquarium::+plume-push-rows-per-tick+))
                          (* 4 single-float-epsilon (max 1 (abs y) (abs (creature-y fish)))))
                       (find-if
                        (lambda (plume)
                          (and (eq (cl-asciiquarium::creature-kind plume) :plume)
                               (multiple-value-call #'cl-asciiquarium::rects-overlap-p
                                 (creature-bounds fish) (creature-bounds plume))))
                        (cl-asciiquarium::world-%creatures world)))
              (push (cons :plume fish) observations))
            ;; Collision follows every creature tick. A shark's kill leaves
            ;; this living lantern's target set until the next tick.
            (when (and target (getf (cl-asciiquarium::creature-data target) :dying)
                       (null (getf data :lure-target)))
              (push (cons :lantern target) observations))))))))

(defun observe-schedule (seed)
  (with-seeded-random-state (seed)
    (let* ((started (get-internal-real-time))
           (world (make-world :width 80 :height 24))
           (advanced-at (get-internal-real-time))
           (previous nil)
           (counts (make-hash-table))
           (first-ticks (make-hash-table)))
      (labels ((record-observations (current)
                 (dolist (observation current)
                   (let ((event (car observation)))
                     (when (and (member event +schedule-events+)
                                (not (member observation previous :test #'equal)))
                       (incf (gethash event counts 0))
                       (unless (gethash event first-ticks)
                         (setf (gethash event first-ticks) (world-tick world))))))
                 (setf previous current)))
        (record-observations (schedule-observations world))
        (dotimes (tick 12000)
          (let ((before (schedule-fish-before-tick world)))
            (world-advance world)
            ;; Count entries, not ticks for which an event remains visible.
            (record-observations
             (nconc (schedule-observations world)
                    (schedule-effects world before))))))
      (let ((ended (get-internal-real-time)))
        (values (loop for event in +schedule-events+
                      collect (list event (gethash event first-ticks)
                                    (gethash event counts 0)))
                (/ (- ended started) (float internal-time-units-per-second))
                (/ (- ended advanced-at) (float internal-time-units-per-second)))))))

(defun missing-schedule-events (seed)
  (loop for (event first-tick count) in (observe-schedule seed)
        unless (and first-tick (plusp count)) collect event))

(describe "plume event observation"
  (it "sees the natural eel lift on seed 777 at tick one"
    (with-seeded-random-state (777)
      (let* ((world (make-world :width 80 :height 24))
             (before (schedule-fish-before-tick world)))
        (world-advance world)
        (expect (find-if (lambda (event)
                           (and (eq (car event) :plume)
                                (eq (getf (cl-asciiquarium::creature-data (cdr event)) :species)
                                    :eel)))
                         (schedule-effects world before))
                :to-be-truthy))))
  (it-each ((:eel) (:jelly)) "sees a real plume lift of ~S" (species)
    (with-seeded-random-state (7)
      (let* ((world (remove-octopus (remove-gulls
                                   (make-world :width 80 :height 24 :fish-count 0
                                               :shark-enabled-p nil))))
             (plume (cl-asciiquarium::find-creature-of-kind world :plume))
             (fish (make-fish world :species species :x (creature-x plume)
                              :y (+ 2 (creature-y plume)) :dx 0)))
        (cl-asciiquarium::%add-world-creature world fish)
        (when (getf (cl-asciiquarium::creature-data fish) :drift-phase)
          (setf (getf (cl-asciiquarium::creature-data fish) :drift-phase) 0))
        (let ((before (schedule-fish-before-tick world)))
          (world-advance world)
          (expect (cdr (assoc :plume (schedule-effects world before))) :to-be fish)))))
  (it-each ((:lantern) (:school)) "does not call ~S steering a plume lift" (steering)
    (with-seeded-random-state (7)
      (let* ((world (make-world :width 80 :height 24 :fish-count 0 :shark-enabled-p nil))
             (plume (cl-asciiquarium::find-creature-of-kind world :plume))
             (y (+ 3 (creature-y plume))))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (let ((fish (if (eq steering :school) (aref members 1)
                          (make-fish world :species :eel :x (creature-x plume) :y y :dx 0))))
            (setf (entity-x (cl-asciiquarium::creature-entity fish)) (creature-x plume)
                  (entity-y (cl-asciiquarium::creature-entity fish)) y)
            (when (eq steering :lantern)
              (cl-asciiquarium::%add-world-creature world fish))
            (let ((lantern (when (eq steering :lantern)
                             (make-fish world :species :lantern :x (creature-x plume)
                                        :y (- (+ y (* 0.5 (nth-value 1 (creature-dimensions fish))))
                                              cl-asciiquarium::+plume-push-rows-per-tick+)))))
              (if lantern
                  (progn
                    (setf (getf (cl-asciiquarium::creature-data lantern) :lure-target) fish)
                    (cl-asciiquarium::%add-world-creature world lantern))
                  (setf (entity-y (cl-asciiquarium::creature-entity leader))
                        (- y (getf (cl-asciiquarium::creature-data fish) :offset-y)
                           cl-asciiquarium::+plume-push-rows-per-tick+)))
              (let ((before (schedule-fish-before-tick world)))
                (if lantern
                    (cl-asciiquarium::lantern-pull lantern fish)
                    (cl-asciiquarium::school-tick world fish))
                (expect (< (abs (- (- y (creature-y fish))
                                   cl-asciiquarium::+plume-push-rows-per-tick+)) 0.00001)
                        :to-be-truthy)
                (expect (assoc :plume (schedule-effects world before)) :to-be nil)))))))))

(describe "ten-minute event schedule"
  ;; Three times each seed's largest completed observation across SBCL 2.6.6
  ;; and 2.6.8, normal/coverage and full-suite context; startup is excluded.
  (it "shows every main event with seed 1"
    (:timeout-ms 2769)
    (expect (missing-schedule-events 1) :to-be nil))
  (it "shows every main event with seed 42"
    (:timeout-ms 1689)
    (expect (missing-schedule-events 42) :to-be nil))
  (it "shows every main event with seed 4242"
    (:timeout-ms 1077)
    (expect (missing-schedule-events 4242) :to-be nil)))
