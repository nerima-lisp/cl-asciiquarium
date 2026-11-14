(in-package #:cl-asciiquarium/test)

(defun octopus-test-world (&key (width 160) (height 30))
  ;; 160 columns keep the vent (and its plume) clear of fish placed right of the rock.
  (let ((world (make-world :width width :height height :fish-count 0
                           :shark-enabled-p nil :hud-visible-p nil)))
    (setf (cl-asciiquarium::world-guest-cooldown world) most-positive-fixnum)
    world))

(defun first-of-kind (world kind)
  (cl-asciiquarium::find-creature-of-kind world kind))

(defun octopus-data (world)
  (cl-asciiquarium::creature-data (first-of-kind world :octopus)))

(defun place-test-fish (world x y)
  "Add a motionless :DART fish with its top-left corner at (X, Y)."
  (let ((fish (make-fish world :species :dart :x x :y y :dx 0)))
    (setf (entity-y (cl-asciiquarium::creature-entity fish)) y)
    (cl-asciiquarium::%add-world-creature world fish)
    fish))

(defun fish-width (world)
  (creature-dimensions (make-fish world :species :dart :x 0 :y 0 :dx 0)))

(defun place-test-shark (world x y)
  "Add a motionless, non-steering shark at (X, Y)."
  (let ((shark (make-shark world :facing :left)))
    (setf (entity-x (cl-asciiquarium::creature-entity shark)) x
          (entity-y (cl-asciiquarium::creature-entity shark)) y
          (entity-dx (cl-asciiquarium::creature-entity shark)) 0
          (getf (cl-asciiquarium::creature-data shark) :tick) nil)
    (cl-asciiquarium::%add-world-creature world shark)
    shark))

(defun advance-until (world predicate limit)
  "Advance WORLD until PREDICATE holds, at most LIMIT ticks; return the number
of ticks taken, or NIL."
  (loop for ticks from 1 to limit
        do (world-advance world)
        when (funcall predicate) return ticks))

(defun in-world-p (world creature)
  (member creature (cl-asciiquarium::world-%creatures world)))

(defun sprite-shapes-match-p (art mask)
  (equal (mapcar #'length (cl-asciiquarium::split-sprite-lines art))
         (mapcar #'length (cl-asciiquarium::split-sprite-lines mask))))

(defun bytes-consed-by (thunk)
  (dotimes (i 100) (funcall thunk))
  (let ((before (sb-ext:get-bytes-consed)))
    (dotimes (i 10000) (funcall thunk))
    (- (sb-ext:get-bytes-consed) before)))

(describe "the octopus under the rock"
  (it "peeks over the rock from behind it, built without drawing a random number"
    (with-seeded-random-state (3)
      (let* ((world (octopus-test-world))
             (rock (first-of-kind world :rock))
             (octopus (first-of-kind world :octopus))
             (copy (make-random-state *random-state*)))
        (expect (eq (getf (cl-asciiquarium::creature-data octopus) :rock) rock) :to-be-truthy)
        (expect (creature-y octopus) :to-be (- (creature-y rock) 2))
        (expect (creature-x octopus) :to-be (+ (creature-x rock) 2))
        (expect (< (cl-asciiquarium::creature-z octopus) (cl-asciiquarium::creature-z rock))
                :to-be-truthy)
        (cl-asciiquarium::make-octopus world rock)
        (expect (random 1000000) :to-be (random 1000000 copy)))))

  (it "catches a fish 12 columns right of the rock, drags it in, and schedules a refill"
    (with-seeded-random-state (5)
      (let* ((world (octopus-test-world))
             (rock (first-of-kind world :rock))
             (fish (place-test-fish world (+ (creature-x rock) 10 12) (1- (creature-y rock)))))
        (expect (advance-until world (lambda () (first-of-kind world :tentacle)) 1) :to-be 1)
        (let ((tentacle (first-of-kind world :tentacle)))
          (expect (creature-facing tentacle) :to-be :right)
          (expect (creature-y tentacle)
                  :to-be (+ (creature-y fish) (floor (nth-value 1 (creature-dimensions fish)) 2)))
          (expect (getf (octopus-data world) :phase) :to-be :reach)
          (expect (advance-until world (lambda () (eq (cl-asciiquarium::creature-kind fish) :caught-fish)) 20)
                  :to-be-truthy)
          (expect (first-of-kind world :ink) :to-be nil)
          (expect (plusp (cl-asciiquarium::world-refill-at world)) :to-be-truthy)
          (let ((caught-x (creature-x fish))
                (caught-length (getf (cl-asciiquarium::creature-data tentacle) :length)))
            (dotimes (tick 3) (world-advance world))
            (with-soft-assertions
              (expect (getf (cl-asciiquarium::creature-data tentacle) :retracting) :to-be-truthy)
              (expect (< (getf (cl-asciiquarium::creature-data tentacle) :length) caught-length)
                      :to-be-truthy)
              (expect (< (creature-x fish) caught-x) :to-be-truthy)))
          (expect (advance-until world (lambda () (not (in-world-p world fish))) 20)
                  :to-be-truthy)
          (expect (in-world-p world tentacle) :to-be nil)
          (world-advance world)
          (expect (getf (octopus-data world) :phase) :to-be :peek)))))

  (it "drags a fish caught on the left of the rock toward it"
    (with-seeded-random-state (6)
      (let* ((world (octopus-test-world))
             (rock (first-of-kind world :rock))
             (fish (place-test-fish world (- (creature-x rock) 5 (fish-width world))
                                    (1- (creature-y rock)))))
        (world-advance world)
        (expect (creature-facing (first-of-kind world :tentacle)) :to-be :left)
        (expect (advance-until world (lambda () (eq (cl-asciiquarium::creature-kind fish) :caught-fish)) 20)
                :to-be-truthy)
        (let ((caught-x (creature-x fish)))
          (dotimes (tick 3) (world-advance world))
          (expect (> (creature-x fish) caught-x) :to-be-truthy))
        (expect (advance-until world (lambda () (not (in-world-p world fish))) 20)
                :to-be-truthy))))

  (it "reaches for no fish 13 columns from the rock or 7 rows above it"
    (with-seeded-random-state (7)
      (let* ((world (octopus-test-world))
             (rock (first-of-kind world :rock))
             (far (place-test-fish world (+ (creature-x rock) 10 13) (1- (creature-y rock))))
             (high (place-test-fish world (+ (creature-x rock) 10 1)
                                    (- (creature-y rock) 7
                                       (nth-value 1 (creature-dimensions
                                                     (make-fish world :species :dart
                                                                      :x 0 :y 0 :dx 0)))))))
        (expect (advance-until world (lambda () (first-of-kind world :tentacle)) 40)
                :to-be nil)
        (expect (and (cl-asciiquarium::alive-fish-p far) (cl-asciiquarium::alive-fish-p high))
                :to-be-truthy))))

  (it "reaches for no fish right above the rock"
    (with-seeded-random-state (7)
      (let* ((world (octopus-test-world))
             (rock (first-of-kind world :rock))
             (above (place-test-fish world (creature-x rock)
                                     (- (creature-y rock)
                                        (nth-value 1 (creature-dimensions
                                                      (make-fish world :species :dart
                                                                       :x 0 :y 0 :dx 0)))))))
        (expect (advance-until world (lambda () (first-of-kind world :tentacle)) 40)
                :to-be nil)
        (expect (cl-asciiquarium::alive-fish-p above) :to-be-truthy))))

  (it "catches nothing with an empty tentacle on the tick it is removed"
    (with-seeded-random-state (8)
      (let* ((world (octopus-test-world))
             (rock (first-of-kind world :rock))
             (fish (place-test-fish world (+ (creature-x rock) 10 12) (1- (creature-y rock)))))
        (world-advance world)
        (setf (cl-asciiquarium::creature-removep fish) t)
        (let* ((tentacle (first-of-kind world :tentacle))
               (data (cl-asciiquarium::creature-data tentacle)))
          (expect (advance-until world (lambda () (and (getf data :retracting)
                                                       (= (getf data :length) 1)))
                                 40)
                  :to-be-truthy)
          (let ((late (place-test-fish world (getf data :base) (creature-y tentacle))))
            (world-advance world)
            (with-soft-assertions
              (expect (in-world-p world tentacle) :to-be nil)
              (expect (cl-asciiquarium::alive-fish-p late) :to-be-truthy)))))))

  (it "retracts an empty tentacle at its full length"
    (with-seeded-random-state (8)
      (let* ((world (octopus-test-world))
             (rock (first-of-kind world :rock))
             (fish (place-test-fish world (+ (creature-x rock) 10 12) (1- (creature-y rock)))))
        (world-advance world)
        (setf (cl-asciiquarium::creature-removep fish) t)
        (let ((tentacle (first-of-kind world :tentacle)))
          (expect (advance-until world (lambda () (getf (cl-asciiquarium::creature-data tentacle)
                                                        :retracting))
                                 20)
                  :to-be 16)
          (expect (getf (cl-asciiquarium::creature-data tentacle) :length)
                  :to-be cl-asciiquarium::+tentacle-max-length+)
          (expect (advance-until world (lambda () (not (in-world-p world tentacle))) 20)
                  :to-be 16)))))

  (it "lets a caught fish leave with its tentacle when a resize discards the background"
    (with-seeded-random-state (9)
      (let* ((world (octopus-test-world))
             (rock (first-of-kind world :rock))
             (octopus (first-of-kind world :octopus))
             (fish (place-test-fish world (+ (creature-x rock) 10 3) (1- (creature-y rock)))))
        (expect (advance-until world (lambda () (eq (cl-asciiquarium::creature-kind fish) :caught-fish)) 20)
                :to-be-truthy)
        (world-resize world 160 30)
        (world-advance world)
        (expect (in-world-p world fish) :to-be nil)
        (expect (in-world-p world octopus) :to-be nil)
        (expect (eq (first-of-kind world :octopus) octopus) :to-be nil)
        (expect (getf (octopus-data world) :rock) :to-be (first-of-kind world :rock))))))

(describe "the octopus's ink"
  (it "inks and hides when a shark comes near, reaches for nothing for 50 ticks, then peeks"
    (with-seeded-random-state (11)
      (let* ((world (octopus-test-world))
             (rock (first-of-kind world :rock))
             (octopus (first-of-kind world :octopus))
             (shark (place-test-shark world (- (creature-x rock) 20) (- (creature-y rock) 3))))
        (world-advance world)
        (expect (getf (octopus-data world) :phase) :to-be :inked)
        (expect (creature-y octopus) :to-be (1+ (creature-y rock)))
        (let ((ink (first-of-kind world :ink)))
          (expect (cl-asciiquarium::creature-frame-index ink) :to-be 0)
          (setf (cl-asciiquarium::creature-removep shark) t)
          (place-test-fish world (+ (creature-x rock) 10 6) (1- (creature-y rock)))
          (dotimes (tick 49)
            (world-advance world)
            (expect (first-of-kind world :tentacle) :to-be nil))
          (expect (in-world-p world ink) :to-be-truthy)
          (expect (cl-asciiquarium::creature-frame-index ink) :to-be 2)
          (world-advance world)
          (expect (in-world-p world ink) :to-be nil)
          (expect (first-of-kind world :ink) :to-be nil)
          (expect (getf (octopus-data world) :phase) :to-be :peek)
          (expect (creature-y octopus) :to-be (- (creature-y rock) 2))
          (expect (advance-until world (lambda () (first-of-kind world :tentacle)) 11)
                  :to-be-truthy)))))

  (it "pulls back a tentacle that is out when it inks, and inks only once"
    (with-seeded-random-state (12)
      (let* ((world (octopus-test-world))
             (rock (first-of-kind world :rock))
             (fish (place-test-fish world (+ (creature-x rock) 10 12) (1- (creature-y rock)))))
        (world-advance world)
        (let ((tentacle (first-of-kind world :tentacle)))
          (place-test-shark world (- (creature-x rock) 20) (- (creature-y rock) 3))
          (world-advance world)
          (expect (getf (cl-asciiquarium::creature-data tentacle) :retracting) :to-be-truthy)
          (dotimes (tick 5) (world-advance world))
          (expect (count :ink (cl-asciiquarium::world-%creatures world)
                         :key #'cl-asciiquarium::creature-kind)
                  :to-be 1)
          (expect (advance-until world (lambda () (not (in-world-p world tentacle))) 10)
                  :to-be-truthy)
          (expect (getf (octopus-data world) :phase) :to-be :inked)
          (expect (cl-asciiquarium::alive-fish-p fish) :to-be-truthy))))))

(describe "a tentacle as a threat"
  (it "scatters a school within 26 columns"
    (with-seeded-random-state (42)
      (let ((world (octopus-test-world :width 160)))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (let ((right (loop for fish across members
                             maximize (+ (floor (creature-x fish)) (creature-dimensions fish))))
                (tentacle (cl-asciiquarium::make-tentacle
                           world (first-of-kind world :octopus) :right 0)))
            (apply-collisions world)
            (expect (zerop (getf (cl-asciiquarium::creature-data leader) :scatter-until))
                    :to-be-truthy)
            (setf (entity-x (cl-asciiquarium::creature-entity tentacle)) (+ right 20)
                  (entity-y (cl-asciiquarium::creature-entity tentacle)) (creature-y leader))
            (cl-asciiquarium::%add-world-creature world tentacle)
            (apply-collisions world)
            (expect (loop for fish across members
                          always (plusp (getf (cl-asciiquarium::creature-data fish)
                                              :scatter-until)))
                    :to-be-truthy)
            (expect (getf (octopus-data world) :phase) :to-be :peek)))))))

(describe "octopus allocation"
  (it "conses nothing while it peeks, hides, senses, grows and retracts a tentacle, or inks"
    (with-seeded-random-state (13)
      (let* ((world (octopus-test-world))
             (rock (first-of-kind world :rock))
             (octopus (first-of-kind world :octopus))
             (data (cl-asciiquarium::creature-data octopus))
             (fish (place-test-fish world 0 (1- (creature-y rock))))
             (tentacle (cl-asciiquarium::make-tentacle world octopus :right (creature-y rock)))
             (tentacle-data (cl-asciiquarium::creature-data tentacle)))
        (dotimes (i 5) (place-test-fish world (* i 2) (- (creature-y rock) 5)))
        (setf (cl-asciiquarium::creature-data fish)
              (list* :offset-x 0 (cl-asciiquarium::creature-data fish)))
        (expect (bytes-consed-by (lambda ()
                                   (setf (getf data :reach-next) 0)
                                   (cl-asciiquarium::octopus-tick world octopus)))
                :to-be 0)
        (expect (getf data :phase) :to-be :peek)
        (expect (bytes-consed-by (lambda ()
                                   (setf (getf tentacle-data :length) 5
                                         (getf tentacle-data :retracting) nil
                                         (getf tentacle-data :holding) nil)
                                   (cl-asciiquarium::tentacle-tick world tentacle)
                                   (setf (getf tentacle-data :retracting) t
                                         (getf tentacle-data :holding) fish)
                                   (cl-asciiquarium::tentacle-tick world tentacle)))
                :to-be 0)
        (expect (getf tentacle-data :length) :to-be 5)
        (place-test-shark world (- (creature-x rock) 20) (- (creature-y rock) 3))
        (cl-asciiquarium::%add-world-creature world tentacle)
        (expect (bytes-consed-by (lambda () (apply-collisions world))) :to-be 0)
        (expect (getf data :phase) :to-be :inked)
        (setf (getf data :ink-until) most-positive-fixnum)
        (expect (bytes-consed-by (lambda () (cl-asciiquarium::octopus-tick world octopus)))
                :to-be 0)
        (let ((ink (first-of-kind world :ink)))
          (expect (bytes-consed-by (lambda ()
                                     (setf (cl-asciiquarium::creature-ttl ink) 50)
                                     (cl-asciiquarium::tick-creature world ink 160 30)))
                  :to-be 0))))))

(describe "octopus art"
  (it "gives every octopus, tentacle, and ink frame a mask of its own shape"
    (expect (sprite-shapes-match-p cl-asciiquarium::+octopus-art+ cl-asciiquarium::+octopus-mask+)
            :to-be-truthy)
    (expect (every #'sprite-shapes-match-p cl-asciiquarium::+tentacle-frames+
                   cl-asciiquarium::+tentacle-masks+)
            :to-be-truthy)
    (expect (mapcar #'length cl-asciiquarium::+tentacle-frames+)
            :to-equal (loop for length from 1 to cl-asciiquarium::+tentacle-max-length+
                            collect length))
    (expect (every #'sprite-shapes-match-p cl-asciiquarium::+ink-frames+
                   cl-asciiquarium::+ink-masks+)
            :to-be-truthy)))
