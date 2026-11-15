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

(defun schedule-fish-before-tick (world)
  (loop for fish in (cl-asciiquarium::world-%creatures world)
        for data = (cl-asciiquarium::creature-data fish)
        when (cl-asciiquarium::alive-fish-p fish)
          collect (list fish (creature-y fish) (getf data :drift-y)
                        (let ((target (getf data :lure-target)))
                          (when (and target (cl-asciiquarium::alive-fish-p target)
                                     (> (getf data :lure-next) (1+ (world-tick world))))
                            target)))))

(defun schedule-effects (world before)
  (let ((observations nil))
    (dolist (entry before observations)
      (destructuring-bind (fish y drift-y target) entry
        (let ((data (cl-asciiquarium::creature-data fish)))
          (when (cl-asciiquarium::alive-fish-p fish)
            ;; Only PUSH-EFFECT changes an existing fish's drift origin.
            (when (and drift-y (< (getf data :drift-y) drift-y)
                       (< (creature-y fish) y)
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

(describe "ten-minute event schedule"
  ;; Three times the larger measured normal/coverage run for each seed,
  ;; including world creation; compilation and process startup are excluded.
  (it "shows every main event with seed 1"
    (:timeout-ms 2196)
    (expect (missing-schedule-events 1) :to-be nil))
  (it "shows every main event with seed 42"
    (:timeout-ms 2034)
    (expect (missing-schedule-events 42) :to-be nil))
  (it "shows every main event with seed 4242"
    (:timeout-ms 1158)
    (expect (missing-schedule-events 4242) :to-be nil)))
