(in-package #:cl-asciiquarium/test)

(describe "maybe-spawn-shark"
  (it "spawns nothing while the cooldown is still counting down"
    (let ((world (tiny-world :width 40 :height 20)))
      (setf (world-shark-cooldown world) 5)
      (maybe-spawn-shark world)
      (expect (find :shark (world-creatures world) :key #'creature-kind) :to-be-null)
      (expect (world-shark-cooldown world) :to-be 4)))
  (it "spawns a shark and resets the cooldown once it reaches zero"
    (with-seeded-random-state (7)
      (let ((world (tiny-world :width 40 :height 20)))
        (setf (world-shark-cooldown world) 1)
        (maybe-spawn-shark world)
        (expect (find :shark (world-creatures world) :key #'creature-kind) :to-be-truthy)
        (expect (plusp (world-shark-cooldown world)) :to-be-truthy)))))

(describe "anchor fall-then-settle state machine"
  (it "stops descending, marks itself dropped, and starts its despawn countdown once it reaches target depth"
    (let* ((world (tiny-world :width 40 :height 20))
           (anchor (make-creature :world world :kind :anchor :frames (list "( o )")
                                  :x 10 :y 5 :dx 0 :dy 1 :policy :none
                                  :data (list :target-depth 8 :dropped nil))))
      (world-add-creature world anchor)
      (dotimes (i 3) (world-advance world))
      (with-soft-assertions
        (expect (creature-y anchor) :to-be 8)
        (expect (getf (creature-data anchor) :dropped) :to-be-truthy)
        (expect (entity-dy (creature-entity anchor)) :to-be 0)
        (expect (creature-ttl anchor) :to-be +anchor-dropped-ticks+)
        (expect (cl-asciiquarium::world-active-predator-count world) :to-be 1))
      (world-advance world)
      (expect (cl-asciiquarium::world-active-predator-count world) :to-be 1))))

(describe "spawn-guest-now"
  (it "adds one ship when requested explicitly"
    (let* ((world (tiny-world :width 40 :height 20))
           (before (length (world-creatures world))))
      (spawn-guest-now world :ship)
      (expect (world-creatures world) :to-have-length (1+ before))
      (expect (count :ship (world-creatures world) :key (function creature-kind)) :to-be 1))))

(describe "static spawned sprite ownership"
  (it "keeps each entity and public art result private"
    (let* ((world (tiny-world :width 80 :height 24))
           (first (make-ship world :facing :right))
           (second (make-ship world :facing :left))
           (art (creature-art first)))
      (setf (char art 0) #\X)
      (expect (creature-entity first) :not :to-be (creature-entity second))
      (expect (creature-art first) :not :to-equal art))))

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
                  (plusp (entity-dx (creature-entity creature)))
                  (minusp (entity-dx (creature-entity creature))))
              :to-be-truthy))))

(describe "off-screen crossing factory velocities"
  (it-each ((make-shark) (make-ship) (make-duck-line) (make-dolphin) (make-sea-monster))
      "~A uses a single-float velocity on the per-frame movement path"
      (constructor)
    (let ((creature (funcall constructor (tiny-world :width 40 :height 20))))
      (expect (typep (entity-dx (creature-entity creature)) 'single-float)
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
      (expect (creature-y dolphin) :to-be (getf (creature-data dolphin) :baseline-y))))
  (it "leaves its baseline partway through one arc period, unlike a constant-velocity creature"
    (let* ((world (tiny-world :width 60 :height 30))
           (dolphin (make-dolphin world :facing :right))
           (baseline (getf (creature-data dolphin) :baseline-y)))
      (world-add-creature world dolphin)
      (dotimes (i (round (/ +dolphin-arc-period+ 4))) (world-advance world))
      (expect (/= (creature-y dolphin) baseline) :to-be-truthy)))
  (it "returns to its baseline row after exactly one full arc period"
    (let* ((world (tiny-world :width 60 :height 30))
           (dolphin (make-dolphin world :facing :right))
           (baseline (getf (creature-data dolphin) :baseline-y)))
      (world-add-creature world dolphin)
      (dotimes (i +dolphin-arc-period+) (world-advance world))
      (expect (creature-y dolphin) :to-be baseline))))

(describe "make-sea-monster and sea-monster-segments"
  (it "returns a :sea-monster head"
    (let* ((world (tiny-world :width 40 :height 20))
           (leader (make-sea-monster world :facing :right)))
      (expect (creature-kind leader) :to-be :sea-monster)))
  (it "builds +sea-monster-segment-count+ trailing :monster-segment creatures"
    (let* ((world (tiny-world :width 40 :height 20))
           (leader (make-sea-monster world :facing :right))
           (segments (sea-monster-segments world leader)))
      (expect (length segments) :to-be +sea-monster-segment-count+)
      (expect (every (lambda (s) (eq (creature-kind s) :monster-segment)) segments) :to-be-truthy)))
  (it "positions every segment behind the head, opposite its direction of travel"
    (let* ((world (tiny-world :width 40 :height 20))
           (leader (make-sea-monster world :facing :right))
           (segments (sea-monster-segments world leader)))
      (dolist (segment segments)
        (expect (< (creature-x segment) (creature-x leader)) :to-be-truthy))))
  (it "positions every segment behind a left-facing head"
    (let* ((world (tiny-world :width 40 :height 20))
           (leader (make-sea-monster world :facing :left))
           (segments (sea-monster-segments world leader)))
      (dolist (segment segments)
        (expect (> (creature-x segment) (creature-x leader)) :to-be-truthy))))
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
      (world-add-creature world leader)
      (world-add-creature world segment)
      (world-advance world)
      (let ((offset-1 (- (creature-x segment) (creature-x leader))))
        (world-advance world)
        (expect (- (creature-x segment) (creature-x leader)) :to-be offset-1))))
  (it "despawns every segment one tick after the head exits the world"
    (let* ((world (tiny-world :width 20 :height 20))
           (leader (make-sea-monster world :facing :right)))
      (world-add-creature world leader)
      (dolist (segment (sea-monster-segments world leader))
        (world-add-creature world segment))
      (setf (entity-x (creature-entity leader)) (1- (world-width world)))
      (setf (entity-dx (creature-entity leader)) 1)
      (world-advance world)
      (world-advance world)
      (expect (find :sea-monster (world-creatures world) :key #'creature-kind) :to-be-null)
      (expect (find :monster-segment (world-creatures world) :key #'creature-kind) :to-be-null))))



(describe "random-guest-kind"
  (it "only ever returns one of the four known guest kinds, given many draws"
    (with-seeded-random-state (23)
      (dotimes (i 50)
        (expect (member (random-guest-kind) '(:ship :duck-line :dolphin :sea-monster))
                :to-be-truthy)))))

(describe "maybe-spawn-shark with sharks disabled"
  (it "never spawns a shark, and never even counts the cooldown down"
    (let ((world (tiny-world :width 40 :height 20)))
      (setf (world-shark-enabled-p world) nil)
      (setf (world-shark-cooldown world) 1)
      (dotimes (i 10) (maybe-spawn-shark world))
      (expect (find :shark (world-creatures world) :key #'creature-kind) :to-be-null)
      (expect (world-shark-cooldown world) :to-be 1))))

(describe "spawn-shark-now and spawn-guest-now: immediate, cooldown-independent spawns"
  (it "spawn-shark-now pushes a shark and resets the cooldown regardless of how much was left"
    (let ((world (tiny-world :width 40 :height 20)))
      (setf (world-shark-cooldown world) 999)
      (spawn-shark-now world)
      (expect (find :shark (world-creatures world) :key #'creature-kind) :to-be-truthy)
      (expect (/= (world-shark-cooldown world) 999) :to-be-truthy)))
  (it "spawn-guest-now pushes the requested guest kind immediately"
    (let ((world (tiny-world :width 40 :height 20)))
      (spawn-guest-now world :duck-line)
      (expect (find :duck-line (world-creatures world) :key #'creature-kind) :to-be-truthy)))
  (it "spawn-guest-now on :sea-monster pushes the head and every trailing segment"
    (let ((world (tiny-world :width 40 :height 20)))
      (spawn-guest-now world :sea-monster)
      (expect (find :sea-monster (world-creatures world) :key #'creature-kind) :to-be-truthy)
      (expect (count :monster-segment (world-creatures world) :key #'creature-kind)
              :to-be +sea-monster-segment-count+))))

(describe "maybe-emit-bubble"
  (it "does not emit while the per-fish timer is still counting down"
    (let* ((world (tiny-world :width 40 :height 20))
           (fish (make-fish world :species :dart :x 5 :y 5 :dx 0)))
      (setf (getf (creature-data fish) :bubble-timer) 5)
      (maybe-emit-bubble world fish)
      (expect (find :bubble (world-creatures world) :key #'creature-kind) :to-be-null)
      (expect (getf (creature-data fish) :bubble-timer) :to-be 4)))
  (it "emits a bubble and resets the timer once it reaches zero"
    (with-seeded-random-state (9)
      (let* ((world (tiny-world :width 40 :height 20))
             (fish (make-fish world :species :dart :x 5 :y 5 :dx 0)))
        (setf (getf (creature-data fish) :bubble-timer) 1)
        (maybe-emit-bubble world fish)
        (expect (find :bubble (world-creatures world) :key #'creature-kind) :to-be-truthy)
        (expect (plusp (getf (creature-data fish) :bubble-timer)) :to-be-truthy)))))
