;;;; t/p3-integration-test.lisp -- seeded runs of the real WORLD-ADVANCE in
;;;; which P3's parts (collision rows and refill, the shark, schools, brood,
;;;; puffer and lantern) act on one another. Each test asserts a behaviour no
;;;; single part's unit tests can see.
(in-package #:cl-asciiquarium/test)

(defun p3-live-fish-count (world)
  (count-if #'cl-asciiquarium::alive-fish-p (cl-asciiquarium::world-%creatures world)))

(defun p3-quiet-guests (world)
  (setf (cl-asciiquarium::world-guest-cooldown world) most-positive-fixnum)
  (remove-gulls (remove-octopus world)))

(defun p3-in-world-p (world creature)
  (and (member creature (cl-asciiquarium::world-%creatures world) :test #'eq) t))

(describe "P3 integration"
  (it "keeps live fish at or below max-fish when the automatic school arrives"
    ;; The :school row of *AUTO-EVENTS* fires at tick 600 and adds six fish
    ;; whatever the population; spec principle 3 caps fish at max-fish.
    (with-seeded-random-state (7)
      (let ((world (p3-quiet-guests
                    (make-world :width 120 :height 30 :fish-count 30 :max-fish 30
                                :shark-enabled-p nil :hud-visible-p nil)))
            (most 0))
        (dotimes (tick 700)
          (world-advance world)
          (setf most (max most (p3-live-fish-count world))))
        ;; Non-vacuity: the school row did run inside the window.
        (expect (> (svref (cl-asciiquarium::world-event-due world) 0) 600) :to-be-truthy)
        ;; Guards the school's room check: a school of 6 on a full tank of 30
        ;; would make MOST 36.
        (expect (<= most (cl-asciiquarium::world-max-fish world)) :to-be-truthy))))

  (it "lets a school lose members to the shark, releases orphans, and refills to fish-count"
    (with-seeded-random-state (7)
      (let* ((world (p3-quiet-guests
                     (make-world :width 120 :height 30 :fish-count 12 :max-fish 30
                                 :hud-visible-p nil)))
             (target (cl-asciiquarium::world-fish-count world))
             (stale-followers 0)
             (forgotten-refills 0)
             (most 0)
             (fewest most-positive-fixnum))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (flet ((step-and-check ()
                   (let ((orphans
                           (loop for fish in (cl-asciiquarium::world-%creatures world)
                                 for school-leader = (getf (cl-asciiquarium::creature-data fish)
                                                           :leader)
                                 when (and school-leader
                                           (cl-asciiquarium::alive-fish-p fish)
                                           (not (cl-asciiquarium::alive-fish-p school-leader)))
                                   collect fish)))
                     (world-advance world)
                     ;; A follower whose leader died must leave the school on
                     ;; its very next tick.
                     (dolist (fish orphans)
                       (when (and (cl-asciiquarium::alive-fish-p fish)
                                  (getf (cl-asciiquarium::creature-data fish) :leader))
                         (incf stale-followers)))
                     (let ((live (p3-live-fish-count world)))
                       (setf most (max most live)
                             fewest (min fewest live))
                       ;; A shortfall always has a refill pending.
                       (when (and (< live target)
                                  (zerop (cl-asciiquarium::world-refill-at world)))
                         (incf forgotten-refills))))))
            (dotimes (tick 1500) (step-and-check))
            ;; Non-vacuity: the shark took the leader and the tank went short.
            (expect (cl-asciiquarium::alive-fish-p leader) :to-be nil)
            (expect (> (count-if-not #'cl-asciiquarium::alive-fish-p members) 1) :to-be-truthy)
            (expect (< fewest target) :to-be-truthy)
            (expect stale-followers :to-be 0)
            (expect forgotten-refills :to-be 0)
            (expect (<= most (cl-asciiquarium::world-max-fish world)) :to-be-truthy)
            ;; With no new sharks, and once every passing school has left (its
            ;; fish count as live while it crosses, then leave), the tank is
            ;; one fish short per missing fish, refilled one per
            ;; +REFILL-DELAY-TICKS+ from the pending REFILL-AT.
            (setf (cl-asciiquarium::world-shark-enabled-p world) nil)
            (labels ((visitors-p ()
                       (find-if (lambda (creature)
                                  (or (eq (cl-asciiquarium::creature-kind creature) :shark)
                                      (cl-asciiquarium::school-visitor-p creature)))
                                (cl-asciiquarium::world-%creatures world)))
                     (deadline ()
                       (+ (cl-asciiquarium::world-refill-at world)
                          (* cl-asciiquarium::+refill-delay-ticks+
                             (1- (- target (p3-live-fish-count world))))))
                     (school-due ()
                       (svref (cl-asciiquarium::world-event-due world) 0)))
              ;; Wait out the sharks and every school that would cross before
              ;; the refills finish.
              (loop repeat 5000
                    while (or (visitors-p) (>= (deadline) (school-due)))
                    do (step-and-check))
              (expect (visitors-p) :to-be nil))
            (let* ((missing (- target (p3-live-fish-count world)))
                   (refill-at (cl-asciiquarium::world-refill-at world))
                   (deadline (+ refill-at
                                (* cl-asciiquarium::+refill-delay-ticks+ (1- missing)))))
              ;; Non-vacuity: the tank is short, a refill is pending, and no
              ;; school is due before the deadline to mask the shortfall.
              (expect (plusp missing) :to-be-truthy)
              (expect (plusp refill-at) :to-be-truthy)
              (expect (< deadline (svref (cl-asciiquarium::world-event-due world) 0))
                      :to-be-truthy)
              ;; Fry growing up may add fish too, so the deadline is a bound.
              (loop while (and (< (world-tick world) deadline)
                               (< (p3-live-fish-count world) target))
                    do (step-and-check))
              (expect (>= (p3-live-fish-count world) target) :to-be-truthy))
            (expect (<= most (cl-asciiquarium::world-max-fish world)) :to-be-truthy)
            (expect stale-followers :to-be 0)
            (expect forgotten-refills :to-be 0))))))

  (it "refills a resident after 90 ticks while a school is still present"
    (with-seeded-random-state (7)
      (let* ((world (p3-quiet-guests
                     (make-world :width 120 :height 30 :fish-count 6 :max-fish 30
                                 :shark-enabled-p nil :hud-visible-p nil)))
             (resident (first (live-fish world))))
        (cl-asciiquarium::spawn-school-now world)
        (cl-asciiquarium::eat-effect world nil resident)
        (dotimes (tick 89) (world-advance world))
        (expect (school-fish-count world) :to-be 6)
        (expect (p3-live-fish-count world) :to-be 11)
        (world-advance world)
        (expect (school-fish-count world) :to-be 6)
        (expect (p3-live-fish-count world) :to-be 12)
        (expect (cl-asciiquarium::world-refill-at world) :to-be 0))))

  (it "restores 18 residents within 180 ticks alongside a school of six"
    (with-seeded-random-state (7)
      (let* ((world (p3-quiet-guests
                     (make-world :width 120 :height 30 :fish-count 18 :max-fish 30
                                 :shark-enabled-p nil :hud-visible-p nil)))
             (residents (live-fish world)))
        (dolist (fish residents)
          ;; This refill fixture accounts only for the two explicit losses.
          (when (eq (getf (cl-asciiquarium::creature-data fish) :species) :lantern)
            (setf (getf (cl-asciiquarium::creature-data fish) :lure-next)
                  most-positive-fixnum)))
        (cl-asciiquarium::spawn-school-now world)
        (dolist (fish (subseq residents 0 2))
          (cl-asciiquarium::eat-effect world nil fish))
        (dotimes (tick 180)
          (world-advance world)
          (expect (<= (p3-live-fish-count world) 30) :to-be-truthy))
        (expect (school-fish-count world) :to-be 6)
        (expect (count-if-not #'cl-asciiquarium::school-visitor-p (live-fish world))
                :to-be 18))))

  (it "keeps a refill pending while departing followers leave a short tank"
    (with-seeded-random-state (1)
      (let* ((world (p3-quiet-guests
                     (make-world :width 120 :height 30 :fish-count 26 :max-fish 30
                                 :shark-enabled-p nil :hud-visible-p nil)))
             (residents (live-fish world)))
        (dolist (fish (subseq residents 0 2))
          (cl-asciiquarium::eat-effect world nil fish))
        (expect (cl-asciiquarium::spawn-school-if-room world) :to-be t)
        (dotimes (tick 270)
          (world-advance world)
          (expect (<= (p3-live-fish-count world) 30) :to-be-truthy))
        (expect (school-fish-count world) :to-be 0)
        (expect (count-if #'cl-asciiquarium::school-visitor-p (live-fish world))
                :to-be 5)
        (expect (count-if-not #'cl-asciiquarium::school-visitor-p (live-fish world))
                :to-be 25)
        (expect (cl-asciiquarium::world-refill-at world) :to-be 360)
        (loop repeat 180
              until (and (notany #'cl-asciiquarium::school-visitor-p (live-fish world))
                         (= (p3-live-fish-count world) 26))
              do (world-advance world)
                 (expect (<= (p3-live-fish-count world) 30) :to-be-truthy))
        (expect (notany #'cl-asciiquarium::school-visitor-p (live-fish world))
                :to-be-truthy)
        (expect (p3-live-fish-count world) :to-be 26)
        (expect (cl-asciiquarium::world-refill-at world) :to-be 0))))

  (it "counts surviving followers as residents when their leader is eaten"
    (with-seeded-random-state (1)
      (let* ((world (p3-quiet-guests
                     (make-world :width 120 :height 30 :fish-count 18 :max-fish 30
                                 :shark-enabled-p nil :hud-visible-p nil)))
             (residents (live-fish world)))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (dolist (fish (subseq residents 0 6))
            (cl-asciiquarium::eat-effect world nil fish))
          (cl-asciiquarium::eat-effect world nil leader)
          (world-advance world)
          (loop for fish across members
                unless (eq fish leader)
                  do (expect (cl-asciiquarium::school-visitor-p fish) :to-be-falsy)
                     (expect (getf (cl-asciiquarium::creature-data fish) :school-departed)
                             :to-be-falsy))
          (expect (p3-live-fish-count world) :to-be 17)
          (dotimes (tick 89) (world-advance world))
          (expect (p3-live-fish-count world) :to-be 18)
          (expect (cl-asciiquarium::world-refill-at world) :to-be 0)))))

  (it "lets departing followers leave the opposite edge without scheduling a refill"
    (with-seeded-random-state (1)
      (let ((world (p3-quiet-guests
                    (make-world :width 120 :height 30 :fish-count 0 :max-fish 30
                                :shark-enabled-p nil :hud-visible-p nil))))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (let ((direction (signum (entity-dx (cl-asciiquarium::creature-entity leader))))
                (saw-departing nil))
            (loop repeat 500
                  until (every #'cl-asciiquarium::creature-removep members)
                  do (world-advance world)
                     (expect (cl-asciiquarium::world-refill-at world) :to-be 0)
                     (loop for fish across members
                           for data = (cl-asciiquarium::creature-data fish)
                           when (and (cl-asciiquarium::alive-fish-p fish)
                                     (getf data :school-departed))
                             do (setf saw-departing t)
                                (expect (getf data :leader) :to-be nil)
                                (expect (cl-asciiquarium::school-visitor-p fish) :to-be-truthy)))
            (expect saw-departing :to-be-truthy)
            (expect (every #'cl-asciiquarium::creature-removep members) :to-be-truthy)
            (loop for fish across members
                  do (expect (cl-asciiquarium::school-visitor-p fish) :to-be-falsy)
                     (expect (if (plusp direction)
                                 (>= (creature-x fish) (world-width world))
                                 (<= (+ (creature-x fish) (creature-dimensions fish)) 0))
                             :to-be-truthy)))))))

  (it "preserves a passing school and clears the glow of a resident removed by minus"
    (with-soft-assertions
      (with-seeded-random-state (7)
        (let ((world (p3-quiet-guests
                      (make-world :width 160 :height 30 :fish-count 0
                                  :shark-enabled-p nil :hud-visible-p nil))))
          (setf (cl-asciiquarium::world-fish-count world) 6)
          (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
            (cl-asciiquarium::world-decrease-fish-count world)
            ;; A school-only tank has no resident to remove.
            (expect (cl-asciiquarium::alive-fish-p leader) :to-be-truthy)
            (dotimes (tick 5) (world-advance world))
            (expect (p3-in-world-p world leader) :to-be t)
            (expect (loop for index from 1 below (length members)
                          for data = (cl-asciiquarium::creature-data (aref members index))
                          always (eq (getf data :leader) leader))
                    :to-be-truthy)))
        (let ((world (p3-quiet-guests
                      (make-world :width 160 :height 30 :fish-count 0 :theme :moonlight
                                  :shark-enabled-p nil :hud-visible-p nil))))
          (setf (cl-asciiquarium::world-fish-count world) 1)
          (let ((lantern (make-fish world :species :lantern)))
            (cl-asciiquarium::%add-world-creature world lantern)
            (world-advance world)
            ;; Precondition: under moonlight the lantern has its glow.
            (expect (count :lantern-glow (cl-asciiquarium::world-%creatures world)
                           :key #'cl-asciiquarium::creature-kind)
                    :to-be 1)
            (cl-asciiquarium::world-decrease-fish-count world)
            (expect (cl-asciiquarium::creature-removep lantern) :to-be t)
            (dotimes (tick 5) (world-advance world))
            (expect (p3-in-world-p world lantern) :to-be nil)
            ;; Guards removal by `-': were the lantern deleted without REMOVEP,
            ;; the glow would stay on screen forever.
            (expect (count :lantern-glow (cl-asciiquarium::world-%creatures world)
                           :key #'cl-asciiquarium::creature-kind)
                    :to-be 0)))))))

(defun p3-light-gap (lantern fish)
  "Columns plus rows between LANTERN's light and FISH's center."
  (multiple-value-bind (light-x light-y) (cl-asciiquarium::lantern-light-position lantern)
    (multiple-value-bind (width height) (creature-dimensions fish)
      (+ (abs (- light-x (+ (creature-x fish) (* 0.5f0 width))))
         (abs (- light-y (+ (creature-y fish) (* 0.5f0 height))))))))

(defun p3-school-orphans (members)
  "Live MEMBERS still naming a leader that is no longer a live fish."
  (remove-if-not (lambda (fish)
                   (let ((leader (getf (cl-asciiquarium::creature-data fish) :leader)))
                     (and (cl-asciiquarium::alive-fish-p fish)
                          leader
                          (or (not (cl-asciiquarium::alive-fish-p leader))
                              (cl-asciiquarium::creature-removep leader)))))
                 (coerce members 'list)))

(defun p3-in-swim-band-p (world members)
  "True when every live member sits inside the swim band for its height."
  (every (lambda (fish)
           (or (not (cl-asciiquarium::alive-fish-p fish))
               (multiple-value-bind (top bottom)
                   (cl-asciiquarium::fish-swim-limits
                    world (nth-value 1 (creature-dimensions fish)))
                 (<= top (creature-y fish) bottom))))
         members))

(describe "resident decrease with a passing school"
  (it-each ((0) (2)) "preserves the school after minus with ~D missing residents" (losses)
    (with-seeded-random-state (7)
      (let* ((world (p3-quiet-guests
                    (make-world :width 120 :height 30 :fish-count 18 :max-fish 30
                                :shark-enabled-p nil :hud-visible-p nil)))
             (residents (live-fish world)))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          (dolist (fish (subseq residents 0 losses))
            (cl-asciiquarium::eat-effect world nil fish))
          (world-decrease-fish-count world)
          (expect (world-fish-count world) :to-be 17)
          (expect (cl-asciiquarium::alive-fish-p leader) :to-be-truthy)
          (expect (count-if-not #'cl-asciiquarium::school-visitor-p (live-fish world))
                  :to-be (min 17 (- 18 losses)))
          (world-advance world)
          (expect (every #'cl-asciiquarium::school-visitor-p members) :to-be-truthy)
          (loop repeat 200
                do (world-advance world)
                   (expect (<= (count-if-not #'cl-asciiquarium::school-visitor-p
                                            (live-fish world))
                               (world-fish-count world))
                           :to-be-truthy))
          (expect (count-if-not #'cl-asciiquarium::school-visitor-p (live-fish world))
                  :to-be 17))))))

(describe "P3 integration: lantern and school"
  (it "a school follower is pulled out of formation by a lantern and eaten"
    ;; The lantern waits 10 columns behind the school's last follower, so the
    ;; nearest prey in range is a follower and the leader is beyond the
    ;; 30-column lure range. A follower is the case the lure must win: each
    ;; tick SCHOOL-TICK pulls it back toward its slot by up to
    ;; +SCHOOL-REJOIN-COLUMNS+.
    (with-seeded-random-state (7)
      (let* ((small-p (lambda (species)
                        (cl-asciiquarium::fish-species-entry-small-p
                         (cl-asciiquarium::fish-species species))))
             (cl-asciiquarium::+school-species+
               (vector (find-if small-p cl-asciiquarium::+school-species+)))
             (world (p3-quiet-guests
                     (make-world :width 160 :height 30 :fish-count 0
                                 :shark-enabled-p nil :hud-visible-p nil))))
        (multiple-value-bind (leader members) (cl-asciiquarium::spawn-school-now world)
          ;; The school enters from off screen; let its tail get far enough in
          ;; that the lantern fits behind it without wrapping.
          (let ((tail (aref members (1- (length members)))))
            (loop repeat 400
                  until (multiple-value-bind (left top width) (creature-bounds tail)
                          (declare (ignore top))
                          (if (eq (creature-facing leader) :right)
                              (>= left 25)
                              (<= (+ left width) (- (world-width world) 25))))
                  do (world-advance world)))
          (let* ((facing (creature-facing leader))
                 (tail (aref members (1- (length members))))
                 (lantern (make-fish world :species :lantern :dx 0
                                           :facing (if (eq facing :right) :right :left)
                                           :x 0 :y (creature-y tail)))
                 (lantern-data (cl-asciiquarium::creature-data lantern)))
            (multiple-value-bind (tail-left tail-top tail-width) (creature-bounds tail)
              (declare (ignore tail-top))
              (setf (entity-x (cl-asciiquarium::creature-entity lantern))
                    (if (eq facing :right)
                        (- tail-left 10 (creature-dimensions lantern))
                        (+ tail-left tail-width 10))))
            (setf (getf lantern-data :lure-next) (world-tick world))
            (cl-asciiquarium::%add-world-creature world lantern)
            (world-advance world)
            (let ((target (getf lantern-data :lure-target)))
              ;; Non-vacuity: the lure picked a follower of a small species.
              (expect (find target members) :to-be-truthy)
              (expect (eq target leader) :to-be nil)
              (expect (getf (cl-asciiquarium::creature-data target) :leader) :to-be leader)
              (expect (funcall small-p (getf (cl-asciiquarium::creature-data target) :species))
                      :to-be-truthy)
              (let ((start-gap (p3-light-gap lantern target))
                    (closest nil)
                    (most-off-slot 0)
                    (school-valid t))
                ;; A follower may name a dead leader for the rest of the tick
                ;; in which the leader died, and must be released on the next.
                (flet ((advance-and-check ()
                         (let ((orphans (p3-school-orphans members)))
                           (world-advance world)
                           (unless (and (notany (lambda (fish)
                                                  (getf (cl-asciiquarium::creature-data fish)
                                                        :leader))
                                                orphans)
                                        (p3-in-swim-band-p world members))
                             (setf school-valid nil)))))
                  (loop repeat 239
                        until (dying-p target)
                        do (setf closest (p3-light-gap lantern target)
                                 most-off-slot
                                 (max most-off-slot
                                      (abs (- (creature-x target)
                                              (+ (creature-x leader)
                                                 (getf (cl-asciiquarium::creature-data target)
                                                       :offset-x))))))
                           (advance-and-check))
                  (expect (dying-p target) :to-be t)
                  (expect (< closest start-gap) :to-be-truthy)
                  ;; The lure held the follower further from its slot than one
                  ;; tick of formation correction could close.
                  (expect (> most-off-slot cl-asciiquarium::+school-rejoin-columns+) :to-be-truthy)
                  (expect (cl-asciiquarium::alive-fish-p leader) :to-be t)
                  (dotimes (tick 30) (advance-and-check))
                  (expect (p3-school-orphans members) :to-be nil)
                  (expect school-valid :to-be t))))))))))
