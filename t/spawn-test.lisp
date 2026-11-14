(in-package #:cl-asciiquarium/test)

(describe "maybe-spawn-shark"
  (it "spawns nothing while the cooldown is still counting down"
    (let ((world (tiny-world :width 40 :height 20)))
      (setf (cl-asciiquarium::world-shark-cooldown world) 5)
      (cl-asciiquarium::maybe-spawn-shark world)
      (expect (find :shark (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-null)
      (expect (cl-asciiquarium::world-shark-cooldown world) :to-be 4)))
  (it "spawns a shark and resets the cooldown once it reaches zero"
    (with-seeded-random-state (7)
      (let ((world (tiny-world :width 40 :height 20)))
        (setf (cl-asciiquarium::world-shark-cooldown world) 1)
        (cl-asciiquarium::maybe-spawn-shark world)
        (expect (find :shark (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-truthy)
        (expect (plusp (cl-asciiquarium::world-shark-cooldown world)) :to-be-truthy)))))

(describe "anchor fall-then-rest state machine"
  (it "stops descending at target depth, enters :rest, arms its threat, and schedules the rise"
    (let* ((world (tiny-world :width 40 :height 20))
           (anchor (cl-asciiquarium::make-anchor world (make-ship world :facing :right))))
      (setf (getf (cl-asciiquarium::creature-data anchor) :target-depth) 8
            (entity-y (cl-asciiquarium::creature-entity anchor)) 5)
      (cl-asciiquarium::%add-world-creature world anchor)
      (dotimes (i 3) (world-advance world))
      (with-soft-assertions
        (expect (creature-y anchor) :to-be 8)
        (expect (getf (cl-asciiquarium::creature-data anchor) :phase) :to-be :rest)
        (expect (entity-dy (cl-asciiquarium::creature-entity anchor)) :to-be 0)
        (expect (getf (cl-asciiquarium::creature-data anchor) :rise-at)
                :to-be (+ (world-tick world) cl-asciiquarium::+anchor-rest-ticks+))
        (expect (cl-asciiquarium::creature-ttl anchor) :to-be-null)
        (expect (cl-asciiquarium::world-active-predator-count world) :to-be 1))
      (world-advance world)
      (expect (cl-asciiquarium::world-active-predator-count world) :to-be 1))))

(describe "deterministic special-guest spawn scenario, given a fixed seed"
  (it "spawns one of the two known guest kinds the moment its cooldown reaches zero"
    (with-seeded-random-state (3)
      (let ((world (tiny-world :width 40 :height 20)))
        (setf (cl-asciiquarium::world-guest-cooldown world) 1)
        (cl-asciiquarium::maybe-spawn-guest world)
        (expect (member (cl-asciiquarium::creature-kind (first (cl-asciiquarium::world-%creatures world))) '(:ship :duck-line))
                :to-be-truthy))))
  (it "spawns the identical guest kind given the identical seed, twice in a row"
    (flet ((spawned-kind (seed)
             (with-seeded-random-state (seed)
               (let ((world (tiny-world :width 40 :height 20)))
                 (setf (cl-asciiquarium::world-guest-cooldown world) 1)
                 (cl-asciiquarium::maybe-spawn-guest world)
                 (cl-asciiquarium::creature-kind (first (cl-asciiquarium::world-%creatures world)))))))
      (expect (spawned-kind 11) :to-be (spawned-kind 11))))
  (it "drops an anchor only once at its scheduled tick"
    (let* ((world (tiny-world :width 40 :height 20))
           (ship (make-ship world)))
      (setf (getf (cl-asciiquarium::creature-data ship) :drop-tick) 3)
      (setf (world-tick world) 2)
      (cl-asciiquarium::maybe-drop-anchor world ship)
      (expect (count :anchor (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 0)
      (expect (getf (cl-asciiquarium::creature-data ship) :anchor-dropped) :to-be-falsy)
      (setf (world-tick world) 3)
      (cl-asciiquarium::maybe-drop-anchor world ship)
      (expect (count :anchor (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 1)
      (expect (getf (cl-asciiquarium::creature-data ship) :anchor-dropped) :to-be-truthy)
      (cl-asciiquarium::maybe-drop-anchor world ship)
      (expect (count :anchor (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 1)
      (expect (count :chain (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 1)))
  (it "a ship eventually drops an anchor while advancing the world"
    ;; The anchor is hauled up +ANCHOR-REST-TICKS+ after it settles (see
    ;; update-anchor.lisp), so this stops advancing the moment one appears
    ;; rather than running the full budget and checking only at the end --
    ;; a fixed-length run can easily outlast the anchor's own lifetime and
    ;; find it already gone, which is exactly what this scenario intends to
    ;; rule out.
    (with-seeded-random-state (3)
      (let* ((world (make-world :width 40 :height 20 :fish-count 0))
             (ship (make-ship world)))
        (cl-asciiquarium::%add-world-creature world ship)
        (dotimes (i 100)
          (when (find :anchor (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind)
            (return))
          (world-advance world))
        (expect (find :anchor (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-truthy)))))

(describe "off-screen crossing factories position and aim consistently by facing"
  (it-each ((make-shark :right) (make-shark :left)
            (make-ship :right) (make-ship :left)
            (make-duck-line :right) (make-duck-line :left)
            (make-dolphin :right) (make-dolphin :left)
            (make-sea-monster :right) (make-sea-monster :left))
      "~A facing ~A starts off the correct edge, moving inward"
      (constructor facing)
    (let* ((world (tiny-world :width 40 :height 20))
           (creature (funcall constructor world :facing facing)))
      (expect (creature-facing creature) :to-be facing)
      (if (eq facing :right)
          (expect (minusp (creature-x creature)) :to-be-truthy)
          (expect (>= (creature-x creature) (world-width world)) :to-be-truthy))
      (expect (if (eq facing :right)
                  (plusp (entity-dx (cl-asciiquarium::creature-entity creature)))
                  (minusp (entity-dx (cl-asciiquarium::creature-entity creature))))
              :to-be-truthy))))

(describe "off-screen crossing factory velocities"
  (it-each ((make-shark) (make-ship) (make-duck-line) (make-dolphin) (make-sea-monster))
      "~A uses a single-float velocity on the per-frame movement path"
      (constructor)
    (let ((creature (funcall constructor (tiny-world :width 40 :height 20))))
      (expect (typep (entity-dx (cl-asciiquarium::creature-entity creature)) 'single-float)
              :to-be-truthy))))

(describe "define-off-screen-guest's clause validation"
  ;; %PARSE-OFF-SCREEN-GUEST-CLAUSES (art-guests.lisp) is the macro-expansion-
  ;; time parser DEFINE-OFF-SCREEN-GUEST's four call sites already go through
  ;; cleanly; these two cases are what proves its error paths -- an unknown
  ;; clause keyword, and a missing required one -- actually fire, rather than
  ;; only existing in source and never being exercised.
  (it "signals an error naming an unrecognized clause keyword"
    (signals error
      (cl-asciiquarium::%parse-off-screen-guest-clauses
       'make-test-guest '(:bogus 1 :kind :test :art "x" :color :white :z 1 :speed 1 :y 0))))
  (it "signals an error when a required clause is missing"
    (signals error
      (cl-asciiquarium::%parse-off-screen-guest-clauses
       'make-test-guest '(:art "x" :color :white :z 1 :speed 1 :y 0)))))

(describe "make-dolphin's leap arc"
  (it "starts exactly at its randomly chosen baseline row"
    (let* ((world (tiny-world :width 40 :height 20))
           (dolphin (make-dolphin world :facing :right)))
      (expect (creature-y dolphin) :to-be (getf (cl-asciiquarium::creature-data dolphin) :baseline-y))))
  (it "leaves its baseline partway through one arc period, unlike a constant-velocity creature"
    (let* ((world (tiny-world :width 60 :height 30))
           (dolphin (make-dolphin world :facing :right))
           (baseline (getf (cl-asciiquarium::creature-data dolphin) :baseline-y)))
      (cl-asciiquarium::%add-world-creature world dolphin)
      (dotimes (i (round (/ +dolphin-arc-period+ 4))) (world-advance world))
      (expect (/= (creature-y dolphin) baseline) :to-be-truthy)))
  (it "returns to its baseline row after exactly one full arc period"
    (let* ((world (tiny-world :width 60 :height 30))
           (dolphin (make-dolphin world :facing :right))
           (baseline (getf (cl-asciiquarium::creature-data dolphin) :baseline-y)))
      (cl-asciiquarium::%add-world-creature world dolphin)
      (dotimes (i +dolphin-arc-period+) (world-advance world))
      (expect (creature-y dolphin) :to-be baseline))))

(describe "make-sea-monster and sea-monster-segments"
  (it "returns a :sea-monster head"
    (let* ((world (tiny-world :width 40 :height 20))
           (leader (make-sea-monster world :facing :right)))
      (expect (cl-asciiquarium::creature-kind leader) :to-be :sea-monster)))
  (it "builds +sea-monster-segment-count+ trailing :monster-segment creatures"
    (let* ((world (tiny-world :width 40 :height 20))
           (leader (make-sea-monster world :facing :right))
           (segments (sea-monster-segments world leader)))
      (expect (length segments) :to-be +sea-monster-segment-count+)
      (expect (every (lambda (s) (eq (cl-asciiquarium::creature-kind s) :monster-segment)) segments) :to-be-truthy)))
  (it "positions every segment behind the head, opposite its direction of travel"
    (let* ((world (tiny-world :width 40 :height 20))
           (leader (make-sea-monster world :facing :right))
           (segments (sea-monster-segments world leader)))
      (dolist (segment segments)
        (expect (< (creature-x segment) (creature-x leader)) :to-be-truthy))))
  (it "keeps a constant offset from the head once both have ticked together"
    ;; Segments are pushed after (so ticked before, per SPAWN-GUEST-NOW's own
    ;; push order) the head in the shared creature list every tick, so a
    ;; segment always tracks the head's position from one tick prior rather
    ;; than its just-moved position this same tick (see MONSTER-SEGMENT-TICK's
    ;; docstring) -- a constant one-tick lag, not a growing one, which is what
    ;; this checks: the offset is identical across two consecutive ticks.
    (let* ((world (tiny-world :width 60 :height 20))
           (leader (make-sea-monster world :facing :right))
           (segment (first (sea-monster-segments world leader))))
      (cl-asciiquarium::%add-world-creature world leader)
      (cl-asciiquarium::%add-world-creature world segment)
      (world-advance world)
      (let ((offset-1 (- (creature-x segment) (creature-x leader))))
        (world-advance world)
        (expect (- (creature-x segment) (creature-x leader)) :to-be offset-1))))
  (it "despawns every segment one tick after the head exits the world"
    (let* ((world (tiny-world :width 20 :height 20))
           (leader (make-sea-monster world :facing :right)))
      (cl-asciiquarium::%add-world-creature world leader)
      (dolist (segment (sea-monster-segments world leader))
        (cl-asciiquarium::%add-world-creature world segment))
      (setf (entity-x (cl-asciiquarium::creature-entity leader)) (1- (world-width world)))
      (setf (entity-dx (cl-asciiquarium::creature-entity leader)) 1)
      (world-advance world)
      (world-advance world)
      (expect (find :sea-monster (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-null)
      (expect (find :monster-segment (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-null))))

(describe "random-guest-kind"
  (it "only ever returns one of the four known guest kinds, given many draws"
    (with-seeded-random-state (23)
      (dotimes (i 50)
        (expect (member (cl-asciiquarium::random-guest-kind) '(:ship :duck-line :dolphin :sea-monster))
                :to-be-truthy)))))

(describe "maybe-spawn-shark with sharks disabled"
  (it "never spawns a shark, and never even counts the cooldown down"
    (let ((world (tiny-world :width 40 :height 20)))
      (setf (world-shark-enabled-p world) nil)
      (setf (cl-asciiquarium::world-shark-cooldown world) 1)
      (dotimes (i 10) (cl-asciiquarium::maybe-spawn-shark world))
      (expect (find :shark (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-null)
      (expect (cl-asciiquarium::world-shark-cooldown world) :to-be 1))))

(describe "spawn-shark-now and spawn-guest-now: immediate, cooldown-independent spawns"
  (it "spawn-shark-now pushes a shark and resets the cooldown regardless of how much was left"
    (let ((world (tiny-world :width 40 :height 20)))
      (setf (cl-asciiquarium::world-shark-cooldown world) 999)
      (spawn-shark-now world)
      (expect (find :shark (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-truthy)
      (expect (/= (cl-asciiquarium::world-shark-cooldown world) 999) :to-be-truthy)))
  (it "spawn-guest-now pushes the requested guest kind immediately"
    (let ((world (tiny-world :width 40 :height 20)))
      (spawn-guest-now world :duck-line)
      (expect (find :duck-line (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-truthy)))
  (it "spawn-guest-now on :sea-monster pushes the head and every trailing segment"
    (let ((world (tiny-world :width 40 :height 20)))
      (spawn-guest-now world :sea-monster)
      (expect (find :sea-monster (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-truthy)
      (expect (count :monster-segment (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind)
              :to-be +sea-monster-segment-count+))))

(describe "maybe-emit-bubble"
  (it "does not emit while the per-fish timer is still counting down"
    (let* ((world (tiny-world :width 40 :height 20))
           (fish (make-fish world :species :dart :x 5 :y 5 :dx 0)))
      (setf (getf (cl-asciiquarium::creature-data fish) :bubble-timer) 5)
      (cl-asciiquarium::maybe-emit-bubble world fish)
      (expect (find :bubble (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-null)
      (expect (getf (cl-asciiquarium::creature-data fish) :bubble-timer) :to-be 4)))
  (it "emits a bubble and resets the timer once it reaches zero"
    (with-seeded-random-state (9)
      (let* ((world (tiny-world :width 40 :height 20))
             (fish (make-fish world :species :dart :x 5 :y 5 :dx 0)))
        (setf (getf (cl-asciiquarium::creature-data fish) :bubble-timer) 1)
        (cl-asciiquarium::maybe-emit-bubble world fish)
        (expect (find :bubble (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-truthy)
        (expect (plusp (getf (cl-asciiquarium::creature-data fish) :bubble-timer)) :to-be-truthy)))))

(defun live-fish (world)
  (remove-if-not #'cl-asciiquarium::alive-fish-p (cl-asciiquarium::world-%creatures world)))

(defun refill-world ()
  "An 80x24 world of three fish with no automatic shark."
  (remove-octopus (make-world :width 80 :height 24 :fish-count 3 :shark-enabled-p nil)))

(describe "refilling fish taken out of play"
  (it "adds one fish at a screen edge exactly 90 ticks after one is eaten"
    (with-seeded-random-state (42)
      (let* ((world (refill-world))
             (before (live-fish world)))
        (cl-asciiquarium::eat-effect world nil (first before))
        (dotimes (i 89) (world-advance world))
        (expect (length (live-fish world)) :to-be 2)
        (world-advance world)
        (let ((added (set-difference (live-fish world) before)))
          (with-soft-assertions
            (expect (length (live-fish world)) :to-be 3)
            (expect (length added) :to-be 1)
            (expect (member (creature-x (first added))
                            (list 0 (- (world-width world)
                                       (creature-dimensions (first added)))))
                    :to-be-truthy)
            (expect (cl-asciiquarium::world-refill-at world) :to-be 0))))))
  (it "keeps refilling every 90 ticks until the target count is back"
    (with-seeded-random-state (42)
      (let* ((world (refill-world))
             (before (live-fish world)))
        (cl-asciiquarium::eat-effect world nil (first before))
        (cl-asciiquarium::eat-effect world nil (second before))
        (expect (cl-asciiquarium::world-refill-at world) :to-be 90)
        (dotimes (i 90) (world-advance world))
        (expect (length (live-fish world)) :to-be 2)
        (expect (cl-asciiquarium::world-refill-at world) :to-be 180)
        (dotimes (i 90) (world-advance world))
        (expect (length (live-fish world)) :to-be 3))))
  (it "does not refill once the - key has lowered the target to the live count"
    (with-seeded-random-state (42)
      (let* ((world (refill-world)))
        (cl-asciiquarium::eat-effect world nil (first (live-fish world)))
        (dolist (event (decode-input "-"))
          (world-apply-key-event world event))
        (expect (world-fish-count world) :to-be 2)
        (expect (length (live-fish world)) :to-be 2)
        (dotimes (i 100) (world-advance world))
        (expect (length (live-fish world)) :to-be 2)
        (expect (cl-asciiquarium::world-refill-at world) :to-be 0)))))

(defvar *probe-spawn-ticks* nil)

(defun probe-spawn (world)
  (push (world-tick world) *probe-spawn-ticks*))

(defun probe-ship-spawn (world)
  (spawn-guest-now world :ship))

(defun ship-count (world)
  (count :ship (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind))

(describe "the automatic event table"
  (it "fires a row first at its :first tick, then reschedules it within :every"
    (let* ((cl-asciiquarium::*auto-events*
             '((:id :probe :big nil :every (50 60) :first 3 :spawn probe-spawn)))
           (*probe-spawn-ticks* nil)
           (world (tiny-world :width 40 :height 20)))
      (expect (equalp (cl-asciiquarium::world-event-due world) #(3)) :to-be-truthy)
      (dotimes (i 2) (world-advance world))
      (expect *probe-spawn-ticks* :to-be nil)
      (world-advance world)
      (expect *probe-spawn-ticks* :to-equal '(3))
      (expect (<= 53 (svref (cl-asciiquarium::world-event-due world) 0) 63) :to-be-truthy)))
  (it "holds a due big event back while two are on screen, while a key still adds a third"
    (with-seeded-random-state (6)
      (let* ((cl-asciiquarium::*auto-events*
               '((:id :probe :big t :every (50 60) :first 1 :spawn probe-ship-spawn)))
             (world (tiny-world :width 40 :height 20)))
        (dotimes (i 2) (cl-asciiquarium::%add-world-creature world (make-ship world)))
        (world-advance world)
        (expect (ship-count world) :to-be 2)
        (expect (<= 51 (svref (cl-asciiquarium::world-event-due world) 0) 61) :to-be-truthy)
        (spawn-guest-now world :ship)
        (expect (ship-count world) :to-be 3))))
  (it "lets a due big event through while fewer than two are on screen"
    (with-seeded-random-state (6)
      (let* ((cl-asciiquarium::*auto-events*
               '((:id :probe :big t :every (50 60) :first 1 :spawn probe-ship-spawn)))
             (world (tiny-world :width 40 :height 20)))
        (cl-asciiquarium::%add-world-creature world (make-ship world))
        (world-advance world)
        (expect (ship-count world) :to-be 2)))))

(describe "maybe-spawn-guest and the big-event cap"
  (flet ((ship-drawing-seed ()
           (loop for seed from 0
                 when (eq (with-seeded-random-state (seed) (cl-asciiquarium::random-guest-kind))
                          :ship)
                   return seed)))
    (it-each ((0 1) (1 2) (2 2))
        "with ~D ships on screen, a drawn ship leaves ~D"
        (present expected)
      (let ((world (tiny-world :width 40 :height 20)))
        (dotimes (i present) (cl-asciiquarium::%add-world-creature world (make-ship world)))
        (with-seeded-random-state ((ship-drawing-seed))
          (setf (cl-asciiquarium::world-guest-cooldown world) 1)
          (cl-asciiquarium::maybe-spawn-guest world))
        (expect (ship-count world) :to-be expected)
        (expect (plusp (cl-asciiquarium::world-guest-cooldown world)) :to-be-truthy)))))

(defun school-fish-count (world)
  (count-if (lambda (creature) (getf (cl-asciiquarium::creature-data creature) :leader))
            (cl-asciiquarium::world-%creatures world)))

(defun courting-fish (world)
  (remove-if-not (lambda (creature)
                   (eq (getf (cl-asciiquarium::creature-data creature) :threat)
                       cl-asciiquarium::+courting-threat+))
                 (cl-asciiquarium::world-%creatures world)))

(describe "P3 integration: schools, courting, and cleanup"
  (it-each (("c") ("C"))
      "the ~A key spawns a school of six"
      (key)
    (with-seeded-random-state (12)
      (let ((world (make-world :width 80 :height 24 :fish-count 0 :shark-enabled-p nil)))
        (dolist (event (decode-input key))
          (world-apply-key-event world event))
        (expect (school-fish-count world) :to-be 6))))
  (it "fires the default :school row first at tick 600"
    (with-seeded-random-state (12)
      (let ((world (make-world :width 80 :height 24 :fish-count 0 :shark-enabled-p nil)))
        (setf (cl-asciiquarium::world-guest-cooldown world) 1000000)
        (dotimes (i 599) (world-advance world))
        (expect (school-fish-count world) :to-be 0)
        (world-advance world)
        (expect (school-fish-count world) :to-be 6))))
  (it "picks a courting fish only on ticks that are multiples of 50"
    (with-seeded-random-state (12)
      (let ((world (make-world :width 80 :height 24 :fish-count 3 :shark-enabled-p nil)))
        (dotimes (i 49) (world-advance world))
        (expect (courting-fish world) :to-be nil)
        (world-advance world)
        (expect (length (courting-fish world)) :to-be 1))))
  (it "clears eggs, fry, hearts, and lantern glows on r"
    (with-seeded-random-state (12)
      (let* ((world (make-world :width 80 :height 24 :fish-count 0 :shark-enabled-p nil))
             (fry (cl-asciiquarium::make-egg world :dart 10 10)))
        (setf (cl-asciiquarium::creature-kind fry) :fry)
        (dolist (creature (list (cl-asciiquarium::make-egg world :dart 20 10)
                                fry
                                (cl-asciiquarium::make-heart world 30 10)
                                (make-creature :world world :kind :lantern-glow :frames (list "*")
                                               :x 40 :y 10 :policy :none)))
          (cl-asciiquarium::%add-world-creature world creature))
        (dolist (event (decode-input "r"))
          (world-apply-key-event world event))
        (expect (intersection '(:egg :fry :heart :lantern-glow)
                              (mapcar #'cl-asciiquarium::creature-kind
                                      (cl-asciiquarium::world-%creatures world)))
                :to-be nil)))))

(describe "P3 integration: a school only spawns when it fits under max-fish"
  (it "the c key on a full tank adds no fish and says why"
    (with-seeded-random-state (12)
      (let ((world (make-world :width 80 :height 24 :fish-count 25 :max-fish 30
                               :shark-enabled-p nil)))
        (dolist (event (decode-input "c"))
          (world-apply-key-event world event))
        (expect (length (live-fish world)) :to-be 25)
        (expect (cl-asciiquarium::world-notification world)
                :to-equal cl-asciiquarium::+school-no-room-message+))))
  (it "the c key spawns when the school exactly fits"
    (with-seeded-random-state (12)
      (let ((world (make-world :width 80 :height 24 :fish-count 24 :max-fish 30
                               :shark-enabled-p nil)))
        (dolist (event (decode-input "c"))
          (world-apply-key-event world event))
        (expect (length (live-fish world)) :to-be 30))))
  (it "the automatic :school row on a full tank adds no fish and reschedules"
    (with-seeded-random-state (12)
      (let ((world (remove-octopus (make-world :width 80 :height 24 :fish-count 30 :max-fish 30
                                               :shark-enabled-p nil))))
        (setf (cl-asciiquarium::world-guest-cooldown world) 1000000)
        (dotimes (i 600) (world-advance world))
        (expect (school-fish-count world) :to-be 0)
        (expect (> (svref (cl-asciiquarium::world-event-due world) 0) 600) :to-be-truthy)))))

(describe "world-decrease-fish-count releases what held the removed fish"
  (it "marks the removed fish removep and stops its behaviour"
    (with-seeded-random-state (12)
      (let* ((world (make-world :width 80 :height 24 :fish-count 1 :shark-enabled-p nil))
             (fish (first (live-fish world))))
        (world-decrease-fish-count world)
        (expect (cl-asciiquarium::creature-removep fish) :to-be t)
        (expect (getf (cl-asciiquarium::creature-data fish) :tick) :to-be nil)))))
