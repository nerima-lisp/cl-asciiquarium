(in-package #:cl-asciiquarium/test)

(defun school-test-world (&key (width 160) (height 30))
  (let ((world (make-world :width width :height height :fish-count 0
                           :shark-enabled-p nil :hud-visible-p nil)))
    (setf (cl-asciiquarium::world-guest-cooldown world) most-positive-fixnum)
    world))

(defun school-in-formation-p (leader members)
  (loop for fish across members
        for data = (cl-asciiquarium::creature-data fish)
        always (and (<= (abs (- (creature-x fish) (creature-x leader)
                               (getf data :offset-x))) 1)
                    (<= (abs (- (creature-y fish) (creature-y leader)
                               (getf data :offset-y))) 1))))

(describe "a school of six fish"
  (it "spawns six live fish of one species in their relative positions"
    (with-seeded-random-state (42)
      (let ((world (school-test-world)))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (expect (length members) :to-be 6)
          (expect (count-if #'cl-asciiquarium::alive-fish-p
                            (cl-asciiquarium::world-%creatures world)) :to-be 6)
          (expect (loop for fish across members
                        always (and (eq (getf (cl-asciiquarium::creature-data fish) :species)
                                        (getf (cl-asciiquarium::creature-data leader) :species))
                                    (eq (getf (cl-asciiquarium::creature-data fish) :leader)
                                        leader))) :to-be-truthy)
          (expect (school-in-formation-p leader members) :to-be-truthy)))))
  (it "scatters every member for 30 ticks at 26 columns and regroups within 60"
    (with-seeded-random-state (42)
      (let ((world (school-test-world)))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (let* ((right (loop for fish across members
                              maximize (+ (floor (creature-x fish))
                                          (creature-dimensions fish))))
                 (shark (make-shark world :facing :left)))
            (setf (entity-x (cl-asciiquarium::creature-entity shark)) (+ right 27)
                  (entity-y (cl-asciiquarium::creature-entity shark)) 0
                  (entity-dx (cl-asciiquarium::creature-entity shark)) 0
                  (getf (cl-asciiquarium::creature-data shark) :tick) nil)
            (cl-asciiquarium::%add-world-creature world shark)
            (apply-collisions world)
            (expect (loop for fish across members
                          always (zerop (getf (cl-asciiquarium::creature-data fish)
                                             :scatter-until))) :to-be-truthy)
            (decf (entity-x (cl-asciiquarium::creature-entity shark)))
            (apply-collisions world)
            (expect (loop for fish across members
                          always (= 30 (getf (cl-asciiquarium::creature-data fish)
                                             :scatter-until))) :to-be-truthy)
            (cl-asciiquarium::%set-world-creatures
             world (remove shark (cl-asciiquarium::world-%creatures world)))
            (dotimes (tick 29) (world-advance world))
            (expect (loop for fish across members
                          always (and (= 30 (getf (cl-asciiquarium::creature-data fish)
                                                  :scatter-until))
                                      (not (zerop (entity-dy
                                                   (cl-asciiquarium::creature-entity fish))))))
                    :to-be-truthy)
            (expect (school-in-formation-p leader members) :to-be nil)
            (world-advance world)
            (expect (loop for fish across members
                          always (and (zerop (getf (cl-asciiquarium::creature-data fish)
                                                   :scatter-until))
                                      (zerop (entity-dy
                                              (cl-asciiquarium::creature-entity fish)))))
                    :to-be-truthy)
            (dotimes (tick 60) (world-advance world))
            (expect (school-in-formation-p leader members) :to-be-truthy))))))
  (it "returns surviving members to normal fish when the leader is eaten"
    (with-seeded-random-state (71)
      (let ((world (school-test-world)))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (cl-asciiquarium::school-scatter world leader nil)
          (cl-asciiquarium::eat-effect world nil leader)
          (world-advance world)
          (expect (count-if #'cl-asciiquarium::alive-fish-p members) :to-be 5)
          (loop for index from 1 below (length members)
                for fish = (aref members index)
                for data = (cl-asciiquarium::creature-data fish)
                for entity = (cl-asciiquarium::creature-entity fish)
                do (expect (null (getf data :leader)) :to-be-truthy)
                   (expect (getf data :sense) :to-be nil)
                   (expect (getf data :tick) :to-be (getf data :school-tick))
                   (expect (entity-dx entity) :to-be (getf data :school-dx))
                   (expect (entity-dy entity) :to-be 0)
                   (expect (cl-tty-kit:entity-on-exit entity) :to-be (getf data :school-on-exit)))))))
  (it "crosses once from off screen and lets every member leave at the far edge"
    (let ((left-seen nil) (right-seen nil))
      (dolist (seed '(1 2 3 4 5 6 7 8))
        (with-seeded-random-state (seed)
          (let ((world (school-test-world :width 40 :height 12)))
            (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
              (let ((rightward (eq (creature-facing leader) :right))
                    (visible (make-array 6 :initial-element nil)))
                (if rightward (setf right-seen t) (setf left-seen t))
                (expect (loop for fish across members
                              always (if rightward
                                         (<= (+ (creature-x fish)
                                                (creature-dimensions fish)) 0)
                                         (>= (creature-x fish) 40))) :to-be-truthy)
                (dotimes (tick 400)
                  (let ((before (map 'vector #'creature-x members)))
                    (world-advance world)
                    (loop for fish across members for index from 0
                          for x = (creature-x fish)
                          do (expect (if rightward (>= x (aref before index))
                                         (<= x (aref before index))) :to-be-truthy)
                             (when (and (< x 40) (> (+ x (creature-dimensions fish)) 0))
                               (setf (aref visible index) t)))))
                (expect (every #'identity visible) :to-be-truthy)
                (expect (every #'cl-asciiquarium::creature-removep members) :to-be-truthy)
                (expect (loop for fish across members
                              never (member fish (cl-asciiquarium::world-%creatures world)))
                        :to-be-truthy)
                (expect (loop for fish across members
                              always (if rightward (>= (creature-x fish) 40)
                                         (<= (+ (creature-x fish)
                                                (creature-dimensions fish)) 0)))
                        :to-be-truthy))))))
      (expect left-seen :to-be-truthy)
      (expect right-seen :to-be-truthy)))
  (it "lets c add six fish with six free slots and none with five"
    (with-seeded-random-state (42)
      (let ((world (school-test-world)))
        (dotimes (index 2)
          (cl-asciiquarium::%add-world-creature
           world (make-fish world :species :dart :x 60 :y 10)))
        (setf (cl-asciiquarium::world-max-fish world) 7)
        (world-apply-key-events world (decode-input "c"))
        (expect (count-if #'cl-asciiquarium::alive-fish-p
                          (cl-asciiquarium::world-%creatures world)) :to-be 2)
        (setf (cl-asciiquarium::world-max-fish world) 8)
        (world-apply-key-events world (decode-input "c"))
        (expect (count-if #'cl-asciiquarium::alive-fish-p
                          (cl-asciiquarium::world-%creatures world)) :to-be 8)
        (expect (count-if (lambda (fish)
                            (getf (cl-asciiquarium::creature-data fish) :leader))
                          (cl-asciiquarium::world-%creatures world)) :to-be 6))))
  (it "dissolves the school after the minus key removes its leader"
    (with-seeded-random-state (42)
      (let ((world (school-test-world)))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (setf (cl-asciiquarium::world-fish-count world) 6)
          (world-apply-key-events world (decode-input "-"))
          (expect (cl-asciiquarium::creature-removep leader) :to-be-truthy)
          (world-advance world)
          (expect (null (member leader (cl-asciiquarium::world-%creatures world))) :to-be-truthy)
          (expect (count-if #'cl-asciiquarium::alive-fish-p
                            (cl-asciiquarium::world-%creatures world)) :to-be 5)
          (loop for index from 1 below 6
                for fish = (aref members index)
                for data = (cl-asciiquarium::creature-data fish)
                do (expect (null (getf data :leader)) :to-be-truthy)
                   (expect (getf data :tick) :to-be (getf data :school-tick))
                   (expect (cl-tty-kit:entity-on-exit
                            (cl-asciiquarium::creature-entity fish))
                           :to-be (getf data :school-on-exit)))))))
  (it "does not translate the school by a wrap distance after a resize"
    (with-seeded-random-state (42)
      (let ((world (school-test-world)))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (declare (ignore leader))
          (dotimes (tick 100) (world-advance world))
          (world-resize world 40 30)
          (dotimes (tick 10)
            (let ((before (map 'vector #'creature-x members)))
              (world-advance world)
              (loop for fish across members for index from 0
                    do (expect (<= (abs (- (creature-x fish) (aref before index)))
                                   (+ (abs (getf (cl-asciiquarium::creature-data fish)
                                                 :school-dx)) 1.01f0))
                               :to-be-truthy))))))))
  (it "lets core replenishment fill a shortage after the school departs"
    (with-seeded-random-state (42)
      (let ((world (school-test-world :width 40 :height 12)))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (declare (ignore leader))
          ;; Keep offspring from satisfying the refill target in this scenario.
          (loop for fish across members
                do (setf (getf (cl-asciiquarium::creature-data fish) :mate-ready-at) 1000))
          (setf (cl-asciiquarium::world-fish-count world) 1)
          (cl-asciiquarium::schedule-fish-refill world)
          (dotimes (tick 400) (world-advance world))
          (expect (every #'cl-asciiquarium::creature-removep members) :to-be-truthy)
          (expect (count-if #'cl-asciiquarium::alive-fish-p
                            (cl-asciiquarium::world-%creatures world)) :to-be 1)
          (expect (cl-asciiquarium::world-refill-at world) :to-be 0)))))
  (it "keeps entering from the same side after c then minus removes the leader"
    (with-seeded-random-state (5)
      (let ((world (school-test-world :width 40 :height 12)))
        (world-apply-key-events world (decode-input "c"))
        (let* ((leader (find-if #'cl-asciiquarium::alive-fish-p
                                (cl-asciiquarium::world-%creatures world)))
               (members (getf (cl-asciiquarium::creature-data leader) :school-members))
               (followers (subseq members 1)))
          (expect (creature-facing leader) :to-be :left)
          (expect (every (lambda (fish) (>= (creature-x fish) 40)) followers)
                  :to-be-truthy)
          (setf (cl-asciiquarium::world-fish-count world) 6)
          (world-apply-key-events world (decode-input "-"))
          (loop repeat 120
                until (every (lambda (fish) (< (creature-x fish) 40)) followers)
                do (let ((before (map 'vector #'creature-x followers)))
                     (world-advance world)
                     (loop for fish across followers for index from 0
                           for dx = (entity-dx (cl-asciiquarium::creature-entity fish))
                           do (expect (<= (abs (- (creature-x fish)
                                                 (aref before index) dx))
                                          0.001f0) :to-be-truthy))))
          (expect (every (lambda (fish) (and (<= 0 (creature-x fish)) (< (creature-x fish) 40))) followers)
                  :to-be-truthy)
          (expect (every #'cl-asciiquarium::alive-fish-p followers) :to-be-truthy)
          (expect (every (lambda (fish)
                           (null (getf (cl-asciiquarium::creature-data fish) :leader)))
                         followers) :to-be-truthy)))))

  (it "never slides backward while scattering and rejoining in either direction"
    (let ((left-seen nil) (right-seen nil))
      (dolist (seed '(1 2 3 4 5 6 7 8))
        (with-seeded-random-state (seed)
          (let ((world (school-test-world)))
            (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
              (let ((rightward (eq (creature-facing leader) :right)))
                (if rightward (setf right-seen t) (setf left-seen t))
                (cl-asciiquarium::school-scatter world leader nil)
                (dotimes (tick 90)
                  (let ((before (map 'vector #'creature-x members)))
                    (world-advance world)
                    (loop for fish across members for index from 0
                          do (expect (if rightward
                                         (> (creature-x fish) (aref before index))
                                         (< (creature-x fish) (aref before index)))
                                     :to-be-truthy))))
                (expect (school-in-formation-p leader members) :to-be-truthy))))))
      (expect left-seen :to-be-truthy)
      (expect right-seen :to-be-truthy))))
