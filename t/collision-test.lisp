(in-package #:cl-asciiquarium/test)

(describe
 "apply-collisions: shark versus fish"
 (it
  "kills an alive fish overlapping a shark, leaving a non-overlapping fish alone"
  (let* ((world (tiny-world :width 40 :height 20))
         (shark
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "=<{(o.o)}==>")
           :x
           10
           :y
           5
           :dx
           0
           :dy
           0
           :policy
           :none))
         (caught-fish (make-fish world :species :dart :x 12 :y 5 :dx 0))
         (safe-fish (make-fish world :species :dart :x 30 :y 5 :dx 0)))
    (cl-asciiquarium::%add-world-creature world shark)
    (cl-asciiquarium::%add-world-creature world caught-fish)
    (cl-asciiquarium::%add-world-creature world safe-fish)
    (apply-collisions world)
    (expect (getf (cl-asciiquarium::creature-data caught-fish) :dying) :to-be-truthy)
    (expect (cl-asciiquarium::creature-ttl caught-fish) :to-be +death-animation-ticks+)
    (expect (getf (cl-asciiquarium::creature-data safe-fish) :dying) :to-be-falsy)))
 (it
  "does not kill the same fish twice when it overlaps two predators"
  (let* ((world (tiny-world :width 40 :height 20))
         (shark-a
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "=<{(o.o)}==>")
           :x
           10
           :y
           5
           :dx
           0
           :dy
           0
           :policy
           :none))
         (shark-b
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "=<{(o.o)}==>")
           :x
           11
           :y
           5
           :dx
           0
           :dy
           0
           :policy
           :none))
         (fish (make-fish world :species :dart :x 12 :y 5 :dx 0)))
    (cl-asciiquarium::%add-world-creature world shark-a)
    (cl-asciiquarium::%add-world-creature world shark-b)
    (cl-asciiquarium::%add-world-creature world fish)
    (apply-collisions world)
    (expect (cl-asciiquarium::creature-ttl fish) :to-be +death-animation-ticks+)))
 (it
  "removes a caught fish from the world after its death animation expires"
  (let* ((world (tiny-world :width 40 :height 20))
         (shark
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "=<{(o.o)}==>")
           :x
           10
           :y
           5
           :dx
           0
           :dy
           0
           :policy
           :none))
         (fish (make-fish world :species :dart :x 12 :y 5 :dx 0)))
    (cl-asciiquarium::%add-world-creature world shark)
    (cl-asciiquarium::%add-world-creature world fish)
    (dotimes (i (1+ +death-animation-ticks+))
      (world-advance world))
    (expect
     (member fish (cl-asciiquarium::world-%creatures world))
     :to-be-falsy))))

(describe
 "apply-collisions: dropped anchor versus fish"
 (it
  "kills a fish directly beneath a dropped anchor"
  (let* ((world (tiny-world :width 40 :height 20))
         (anchor
          (make-creature
           :world
           world
           :kind
           :anchor
           :frames
           (list "( o )")
           :x
           10
           :y
           8
           :dx
           0
           :dy
           0
           :policy
           :none
           :data
           (list :target-depth 8 :phase :rest :threat *body-eat-threat*)))
         (fish (make-fish world :species :dart :x 10 :y 8 :dx 0)))
    (cl-asciiquarium::%add-world-creature world anchor)
    (cl-asciiquarium::%add-world-creature world fish)
    (apply-collisions world)
    (expect (getf (cl-asciiquarium::creature-data fish) :dying) :to-be-truthy)))
 (it
  "does not kill a fish beneath an anchor that has not been dropped yet"
  (let* ((world (tiny-world :width 40 :height 20))
         (anchor
          (make-creature
           :world
           world
           :kind
           :anchor
           :frames
           (list "( o )")
           :x
           10
           :y
           8
           :dx
           0
           :dy
           1
           :policy
           :none
           :data
           (list :target-depth 15 :phase :fall)))
         (fish (make-fish world :species :dart :x 10 :y 8 :dx 0)))
    (cl-asciiquarium::%add-world-creature world anchor)
    (cl-asciiquarium::%add-world-creature world fish)
    (apply-collisions world)
    (expect (getf (cl-asciiquarium::creature-data fish) :dying) :to-be-falsy))))

(describe
 "apply-collisions: single outer scan semantics"
 (it
  "handles interleaved predator kinds without changing creature order"
  (let* ((world (tiny-world :width 60 :height 20))
         (shark
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "SSS")
           :x
           20
           :y
           5
           :dx
           0
           :dy
           0
           :policy
           :none))
         (anchor
          (make-creature
           :world
           world
           :kind
           :anchor
           :frames
           (list "AAA")
           :x
           5
           :y
           5
           :dx
           0
           :dy
           0
           :policy
           :none
           :data
           (list :phase :rest :threat *body-eat-threat*)))
         (anchor-fish (make-fish world :species :dart :x 5 :y 5 :dx 0))
         (shark-fish (make-fish world :species :dart :x 20 :y 5 :dx 0))
         (safe-fish (make-fish world :species :dart :x 45 :y 5 :dx 0)))
    (cl-asciiquarium::%set-world-creatures
     world
     (list anchor-fish shark safe-fish anchor shark-fish))
    (let ((before (copy-list (cl-asciiquarium::world-%creatures world))))
      (apply-collisions world)
      (expect (getf (cl-asciiquarium::creature-data anchor-fish) :dying) :to-be-truthy)
      (expect (getf (cl-asciiquarium::creature-data shark-fish) :dying) :to-be-truthy)
      (expect (getf (cl-asciiquarium::creature-data safe-fish) :dying) :to-be-falsy)
      (expect
       (every (function eq) before (cl-asciiquarium::world-%creatures world))
       :to-be-truthy)))))

(describe
 "apply-collisions: validated bounds cache"
 (it
  "uses dimensions rebuilt after a case-only and structural direct frame mutation"
  (let* ((world (tiny-world :width 20 :height 10))
         (predator
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "aa ")
           :x
           0
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none))
         (fish
          (make-creature
           :world
           world
           :kind
           :fish
           :frames
           (list "f")
           :x
           0
           :y
           1
           :dx
           1
           :dy
           0
           :policy
           :none
           :data
           (list :species :test)))
         (frame (aref (creature-frames predator) 0)))
    (cl-asciiquarium::%set-world-creatures world (list predator fish))
    (apply-collisions world)
    (expect (getf (cl-asciiquarium::creature-data fish) :dying) :to-be-falsy)
    (setf (char frame 0) #\A)
    (setf (char frame 1) #\Newline)
    (apply-collisions world)
    (expect (getf (cl-asciiquarium::creature-data fish) :dying) :to-be-truthy)))
 (it
  "validates fish dimensions before scanning predators"
  (let* ((world (tiny-world :width 20 :height 10))
         (predator
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "p")
           :x
           0
           :y
           1
           :dx
           0
           :dy
           0
           :policy
           :none))
         (fish
          (make-creature
           :world
           world
           :kind
           :fish
           :frames
           (list "ff ")
           :x
           0
           :y
           0
           :dx
           1
           :dy
           0
           :policy
           :none
           :data
           (list :species :test)))
         (frame (aref (creature-frames fish) 0)))
    (cl-asciiquarium::%set-world-creatures world (list predator fish))
    (apply-collisions world)
    (expect (getf (cl-asciiquarium::creature-data fish) :dying) :to-be-falsy)
    (setf (char frame 0) #\F)
    (setf (char frame 1) #\Newline)
    (apply-collisions world)
    (expect (getf (cl-asciiquarium::creature-data fish) :dying) :to-be-truthy)))
 (it
  "keeps the one-time death conversion when multiple predators overlap"
  (let* ((world (tiny-world :width 30 :height 10))
         (shark-a
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "SSS")
           :x
           5
           :y
           3
           :dx
           0
           :dy
           0
           :policy
           :none))
         (shark-b
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "SSS")
           :x
           5
           :y
           3
           :dx
           0
           :dy
           0
           :policy
           :none))
         (fish
          (make-creature
           :world
           world
           :kind
           :fish
           :frames
           (list "fff")
           :x
           5
           :y
           3
           :dx
           2
           :dy
           1
           :policy
           :none
           :data
           (list :species :test))))
    (cl-asciiquarium::%set-world-creatures world (list shark-a fish shark-b))
    (apply-collisions world)
    (expect (getf (cl-asciiquarium::creature-data fish) :dying) :to-be-truthy)
    (expect (cl-asciiquarium::creature-ttl fish) :to-be +death-animation-ticks+)
    (expect (creature-art fish) :to-equal cl-asciiquarium::+fish-death-art+)
    (expect (entity-dx (cl-asciiquarium::creature-entity fish)) :to-be 0)
    (expect (entity-dy (cl-asciiquarium::creature-entity fish)) :to-be 0)
    (expect (getf (cl-asciiquarium::creature-data fish) :species) :to-be :test)))
 (it
  "retains non-overlapping fish across a dense predator pass"
  (let* ((world (tiny-world :width 40 :height 12))
         (predators
          (loop for x in '(0 8 16 24)
                collect (make-creature
                         :world
                         world
                         :kind
                         :shark
                         :data
                         (list :threat *body-eat-threat*)
                         :frames
                         (list "SSS")
                         :x
                         x
                         :y
                         2
                         :dx
                         0
                         :dy
                         0
                         :policy
                         :none)))
         (overlapped
          (make-creature
           :world
           world
           :kind
           :fish
           :frames
           (list "fff")
           :x
           8
           :y
           2
           :dx
           1
           :dy
           0
           :policy
           :none
           :data
           (list :species :test)))
         (surviving
          (make-creature
           :world
           world
           :kind
           :fish
           :frames
           (list "fff")
           :x
           32
           :y
           9
           :dx
           1
           :dy
           0
           :policy
           :none
           :data
           (list :species :test))))
    (cl-asciiquarium::%set-world-creatures
     world
     (append predators (list overlapped surviving)))
    (apply-collisions world)
    (expect (getf (cl-asciiquarium::creature-data overlapped) :dying) :to-be-truthy)
    (expect (getf (cl-asciiquarium::creature-data surviving) :dying) :to-be-falsy)))
 (it
  "refreshes cached position bounds between collision passes"
  (let* ((world (tiny-world :width 20 :height 10))
         (shark
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "SSS")
           :x
           0
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none))
         (fish
          (make-creature
           :world
           world
           :kind
           :fish
           :frames
           (list "f")
           :x
           10
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none
           :data
           (list :species :test))))
    (cl-asciiquarium::%set-world-creatures world (list shark fish))
    (apply-collisions world)
    (expect (getf (cl-asciiquarium::creature-data fish) :dying) :to-be-falsy)
    (setf (entity-x (cl-asciiquarium::creature-entity fish)) 1)
    (apply-collisions world)
    (expect (getf (cl-asciiquarium::creature-data fish) :dying) :to-be-truthy))))

(describe "deterministic predator/prey scenario via a seeded shark spawn"
  (it "eventually spawns a shark and kills a fish placed in its path, given a fixed seed"
    (with-seeded-random-state (42)
      (let ((world (make-world :width 40 :height 10 :fish-count 0)))
        ;; Force an immediate shark spawn regardless of the random initial
        ;; cooldown, so this scenario is about the collision, not about how
        ;; long a shark's cooldown happens to draw.
        (setf (cl-asciiquarium::world-shark-cooldown world) 1)
        (let ((fish (make-fish world :species :dart :x 20 :y 4 :dx 0)))
          (cl-asciiquarium::%add-world-creature world fish)
          (dotimes (i 200)
            (unless (member fish (cl-asciiquarium::world-%creatures world))
              (return))
            (world-advance world))
          (expect (member fish (cl-asciiquarium::world-%creatures world)) :to-be-falsy))))))

(describe
 "apply-collisions: activation and ignored creatures"
 (it
  "returns the original world without active predators or cache mutation"
  (let* ((world (tiny-world :width 20 :height 10))
         (anchor
          (make-creature
           :world
           world
           :kind
           :anchor
           :frames
           (list "AAA")
           :x
           0
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none
           :data
           (list :phase :fall)))
         (fish
          (make-creature
           :world
           world
           :kind
           :fish
           :frames
           (list "f")
           :x
           0
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none
           :data
           (list :species :test))))
    (cl-asciiquarium::%set-world-creatures world (list anchor fish))
    (setf (cl-asciiquarium::creature-collision-left anchor) 71
          (cl-asciiquarium::creature-collision-left fish) 72)
    (expect (apply-collisions world) :to-be world)
    (expect (getf (cl-asciiquarium::creature-data fish) :dying) :to-be-falsy)
    (expect (cl-asciiquarium::creature-collision-left anchor) :to-be 71)
    (expect (cl-asciiquarium::creature-collision-left fish) :to-be 72)))
 (it
  "treats sharks as active and anchors as active only after dropping"
  (let* ((world (tiny-world :width 30 :height 10))
         (shark
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "SSS")
           :x
           0
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none))
         (anchor
          (make-creature
           :world
           world
           :kind
           :anchor
           :frames
           (list "AAA")
           :x
           10
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none
           :data
           (list :phase :fall)))
         (shark-fish (make-fish world :species :dart :x 0 :y 0 :dx 0))
         (anchor-fish (make-fish world :species :dart :x 10 :y 0 :dx 0)))
    (cl-asciiquarium::%set-world-creatures
     world
     (list shark anchor shark-fish anchor-fish))
    (expect (apply-collisions world) :to-be world)
    (expect (getf (cl-asciiquarium::creature-data shark-fish) :dying) :to-be-truthy)
    (expect (getf (cl-asciiquarium::creature-data anchor-fish) :dying) :to-be-falsy)
    (setf (cl-asciiquarium::creature-data anchor) (list :phase :rest :threat *body-eat-threat*))
    (expect (apply-collisions world) :to-be world)
    (expect (getf (cl-asciiquarium::creature-data anchor-fish) :dying) :to-be-truthy)))
 (it
  "leaves dead fish outside cache and kill processing"
  (let* ((world (tiny-world :width 20 :height 10))
         (shark
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "SSS")
           :x
           0
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none))
         (fish
          (make-creature
           :world
           world
           :kind
           :fish
           :frames
           (list "f")
           :x
           0
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none
           :data
           (list :species :test :dying t))))
    (cl-asciiquarium::%set-world-creatures world (list shark fish))
    (setf (cl-asciiquarium::creature-ttl fish) 7
          (cl-asciiquarium::creature-collision-left fish) 91
          (cl-asciiquarium::creature-collision-top fish) 92
          (cl-asciiquarium::creature-collision-width fish) 93
          (cl-asciiquarium::creature-collision-height fish) 94)
    (expect (apply-collisions world) :to-be world)
    (expect (getf (cl-asciiquarium::creature-data fish) :dying) :to-be-truthy)
    (expect (cl-asciiquarium::creature-ttl fish) :to-be 7)
    (expect (cl-asciiquarium::creature-collision-left fish) :to-be 91)
    (expect (cl-asciiquarium::creature-collision-top fish) :to-be 92)
    (expect (cl-asciiquarium::creature-collision-width fish) :to-be 93)
    (expect (cl-asciiquarium::creature-collision-height fish) :to-be 94))))

(describe
 "active-predator cache"
 (it
  "tracks internally managed predator additions"
  (let* ((world (tiny-world :width 20 :height 10))
         (shark
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "SSS")
           :x
           0
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none)))
    (expect (cl-asciiquarium::world-active-predator-count world) :to-be 0)
    (cl-asciiquarium::%add-world-creature world shark)
    (expect (cl-asciiquarium::world-active-predator-count world) :to-be 1)
    (expect (cl-asciiquarium::%world-has-active-predator-p world) :to-be-truthy))))

(describe
 "apply-collisions: multiple predator outcomes"
 (it
  "kills only live fish overlapping either active predator"
  (let* ((world (tiny-world :width 30 :height 10))
         (shark
          (make-creature
           :world
           world
           :kind
           :shark
           :data
           (list :threat *body-eat-threat*)
           :frames
           (list "SSS")
           :x
           0
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none))
         (anchor
          (make-creature
           :world
           world
           :kind
           :anchor
           :frames
           (list "AAA")
           :x
           10
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none
           :data
           (list :phase :rest :threat *body-eat-threat*)))
         (shark-fish (make-fish world :species :dart :x 0 :y 0 :dx 0))
         (anchor-fish (make-fish world :species :dart :x 10 :y 0 :dx 0))
         (already-dying
          (make-creature
           :world
           world
           :kind
           :fish
           :frames
           (list "f")
           :x
           0
           :y
           0
           :dx
           0
           :dy
           0
           :policy
           :none
           :data
           (list :species :test :dying t)))
         (safe-fish (make-fish world :species :dart :x 20 :y 0 :dx 0)))
    (cl-asciiquarium::%set-world-creatures
     world
     (list shark anchor shark-fish anchor-fish already-dying safe-fish))
    (setf (cl-asciiquarium::creature-ttl already-dying) 7)
    (expect (apply-collisions world) :to-be world)
    (expect (getf (cl-asciiquarium::creature-data shark-fish) :dying) :to-be-truthy)
    (expect (getf (cl-asciiquarium::creature-data anchor-fish) :dying) :to-be-truthy)
    (expect (getf (cl-asciiquarium::creature-data already-dying) :dying) :to-be-truthy)
    (expect (cl-asciiquarium::creature-ttl already-dying) :to-be 7)
    (expect (getf (cl-asciiquarium::creature-data safe-fish) :dying) :to-be-falsy))))

(defun threat-fixture (world row &key (frames (list "TTTTT")) (x 10) (y 5) (facing :right))
  "A motionless creature at X Y carrying the :THREAT row ROW."
  (make-creature :world world :kind :threat-fixture :frames frames :facing facing
                 :x x :y y :dx 0 :dy 0 :policy :none :data (list :threat row)))

(defun one-cell-fish (world x y)
  "A motionless one-cell live fish at X Y."
  (make-creature :world world :kind :fish :frames (list "f") :x x :y y
                 :dx 0 :dy 0 :policy :none :data (list :species :test :tick nil)))

(defun dying-p (fish)
  (and (getf (cl-asciiquarium::creature-data fish) :dying) t))

(defparameter *front-eat-threat*
  '(:grip (:front 2) :effect cl-asciiquarium::eat-effect :prey nil :alarm nil))

(defparameter *body-catch-threat*
  '(:grip :body :effect cl-asciiquarium::catch-effect :prey nil :alarm nil))

(defparameter *alarm-only-threat* '(:grip :body :effect nil :prey nil :alarm t))

(defvar *sense-calls* nil)

(defvar *allocation-sink* nil)

(defun record-sense-call (world sensor threat)
  (declare (ignore world))
  (push (cons sensor threat) *sense-calls*))

(describe "apply-collisions: grip rectangles"
  (it-each ((9 nil) (10 t) (14 t) (15 nil))
      "a :body grip over columns 10-14 takes a fish at column ~D: ~S"
      (x expected)
    (let* ((world (tiny-world :width 40 :height 20))
           (threat (threat-fixture world *body-eat-threat*))
           (fish (one-cell-fish world x 5)))
      (cl-asciiquarium::%set-world-creatures world (list threat fish))
      (apply-collisions world)
      (expect (dying-p fish) :to-be expected)))
  (it-each ((:right 12 nil) (:right 13 t) (:right 14 t) (:right 15 nil)
            (:left 9 nil) (:left 10 t) (:left 11 t) (:left 12 nil))
      "a (:front 2) grip facing ~S takes a fish at column ~D: ~S"
      (facing x expected)
    (let* ((world (tiny-world :width 40 :height 20))
           (threat (threat-fixture world *front-eat-threat* :facing facing))
           (fish (one-cell-fish world x 5)))
      (cl-asciiquarium::%set-world-creatures world (list threat fish))
      (apply-collisions world)
      (expect (dying-p fish) :to-be expected)))
  (it "takes only the listed species when the row names its prey"
    (let* ((world (tiny-world :width 40 :height 20))
           (threat (threat-fixture world '(:grip :body :effect cl-asciiquarium::eat-effect
                                           :prey (:guppy) :alarm nil)
                                   :frames (list "TTTTTTTTTTTTTTTTTTTT") :x 0))
           (dart (make-fish world :species :dart :x 2 :y 5 :dx 0))
           (guppy (make-fish world :species :guppy :x 10 :y 5 :dx 0)))
      (cl-asciiquarium::%set-world-creatures world (list threat dart guppy))
      (apply-collisions world)
      (expect (dying-p dart) :to-be nil)
      (expect (dying-p guppy) :to-be t))))

(describe "apply-collisions: effects"
  (it "eat kills the fish in place and schedules one refill"
    (let* ((world (tiny-world :width 40 :height 20))
           (threat (threat-fixture world *body-eat-threat*))
           (fish (make-fish world :species :dart :x 10 :y 5 :dx 0.5f0)))
      (cl-asciiquarium::%set-world-creatures world (list threat fish))
      (world-advance world)
      (with-soft-assertions
        (expect (cl-asciiquarium::creature-kind fish) :to-be :fish)
        (expect (dying-p fish) :to-be t)
        (expect (getf (cl-asciiquarium::creature-data fish) :tick) :to-be nil)
        (expect (entity-dx (cl-asciiquarium::creature-entity fish)) :to-be 0)
        (expect (cl-asciiquarium::creature-ttl fish) :to-be +death-animation-ticks+)
        (expect (cl-asciiquarium::world-refill-at world)
                :to-be (+ 1 cl-asciiquarium::+refill-delay-ticks+)))))
  (it "catch turns the fish into a :caught-fish that follows its captor and leaves with it"
    (let* ((world (tiny-world :width 40 :height 20))
           (threat (threat-fixture world *body-catch-threat*))
           (fish (make-fish world :species :dart :x 11 :y 5 :dx 0.5f0)))
      (cl-asciiquarium::%set-world-creatures world (list threat fish))
      (world-advance world)
      (with-soft-assertions
        (expect (cl-asciiquarium::creature-kind fish) :to-be :caught-fish)
        (expect (cl-asciiquarium::alive-fish-p fish) :to-be nil)
        (expect (getf (cl-asciiquarium::creature-data fish) :captor) :to-be threat)
        (expect (getf (cl-asciiquarium::creature-data fish) :tick)
                :to-be 'cl-asciiquarium::caught-fish-tick)
        (expect (entity-dx (cl-asciiquarium::creature-entity fish)) :to-be 0)
        (expect (cl-tty-kit:entity-on-exit (cl-asciiquarium::creature-entity fish)) :to-be nil)
        (expect (cl-asciiquarium::world-refill-at world)
                :to-be (+ 1 cl-asciiquarium::+refill-delay-ticks+)))
      (let ((offset-x (- (creature-x fish) (creature-x threat)))
            (offset-y (- (creature-y fish) (creature-y threat))))
        (setf (entity-x (cl-asciiquarium::creature-entity threat)) 20
              (entity-y (cl-asciiquarium::creature-entity threat)) 3)
        (world-advance world)
        (expect (list (- (creature-x fish) (creature-x threat))
                      (- (creature-y fish) (creature-y threat)))
                :to-equal (list offset-x offset-y)))
      (setf (cl-asciiquarium::creature-removep threat) t)
      (world-advance world)
      (expect (member fish (cl-asciiquarium::world-%creatures world)) :to-be-falsy)))
  (it "applies only the first removing effect when two threats grip one fish"
    (let* ((world (tiny-world :width 40 :height 20))
           (catcher (threat-fixture world *body-catch-threat*))
           (eater (threat-fixture world *body-eat-threat*))
           (fish (one-cell-fish world 12 5)))
      (cl-asciiquarium::%set-world-creatures world (list catcher eater fish))
      (apply-collisions world)
      (expect (cl-asciiquarium::creature-kind fish) :to-be :caught-fish)
      (expect (dying-p fish) :to-be nil)))
  (it "lets a threat that is itself a live fish skip itself"
    (let* ((world (tiny-world :width 40 :height 20))
           (lure (make-fish world :species :dart :x 10 :y 5 :dx 0)))
      (setf (cl-asciiquarium::creature-data lure)
            (list* :threat *body-eat-threat* (cl-asciiquarium::creature-data lure)))
      (cl-asciiquarium::%set-world-creatures world (list lure))
      (apply-collisions world)
      (expect (dying-p lure) :to-be nil))))

(describe "arm-threat"
  (it "opens the collision gate for a creature that becomes a threat after it was added"
    (let* ((world (tiny-world :width 40 :height 20))
           (lurker (make-creature :world world :kind :threat-fixture :frames (list "TTTTT")
                                  :x 10 :y 5 :policy :none :data (list :threat nil)))
           (fish (one-cell-fish world 12 5)))
      (cl-asciiquarium::%set-world-creatures world (list lurker fish))
      (world-advance world)
      (expect (dying-p fish) :to-be nil)
      (expect (cl-asciiquarium::world-active-predator-count world) :to-be 0)
      (cl-asciiquarium::arm-threat world lurker *body-eat-threat*)
      (world-advance world)
      (expect (dying-p fish) :to-be t))))

(describe "apply-collisions: sensing"
  (it-each ((18 1 t) (19 1 nil) (18 2 nil) (6 0 t) (5 0 nil))
      "calls the reaction of a (3 1) sensor at column ~D, ~D rows clear of the threat: ~S"
      (x rows-clear expected)
    (let* ((world (tiny-world :width 40 :height 20))
           (threat (threat-fixture world *alarm-only-threat*))
           (sensor (make-creature :world world :kind :sensor :frames (list "s")
                                  :x x :y (+ 5 1 rows-clear) :policy :none
                                  :data (list :sense '(3 1 record-sense-call))))
           (*sense-calls* nil))
      (cl-asciiquarium::%set-world-creatures world (list threat sensor))
      (apply-collisions world)
      (expect (equal *sense-calls* (and expected (list (cons sensor threat)))) :to-be-truthy)))
  (it "treats a NIL row range as unlimited and ignores threats without :alarm"
    (let* ((world (tiny-world :width 40 :height 40))
           (alarm (threat-fixture world *alarm-only-threat* :y 0))
           (quiet (threat-fixture world *body-eat-threat* :y 0 :x 30))
           (sensor (make-creature :world world :kind :sensor :frames (list "s")
                                  :x 12 :y 35 :policy :none
                                  :data (list :sense '(0 nil record-sense-call))))
           (*sense-calls* nil))
      (cl-asciiquarium::%set-world-creatures world (list alarm quiet sensor))
      (apply-collisions world)
      (expect (equal *sense-calls* (list (cons sensor alarm))) :to-be-truthy))))

(describe "apply-collisions: allocation"
  ;; SB-EXT:GET-BYTES-CONSED only moves when a thread's allocation region
  ;; fills, so a single small cons can read as zero. Ten thousand passes
  ;; would allocate well past one region if a pass consed at all.
  (flet ((bytes-consed-by-passes (world)
           (dotimes (i 100) (apply-collisions world))
           (let ((before (sb-ext:get-bytes-consed)))
             (dotimes (i 10000) (apply-collisions world))
             (- (sb-ext:get-bytes-consed) before))))
    (it "conses nothing on a tick with no threat"
      (with-seeded-random-state (5)
        (let ((world (make-world :width 80 :height 24 :fish-count 18 :shark-enabled-p nil)))
          (expect (bytes-consed-by-passes world) :to-be 0))))
    (it "conses nothing while a threat and a sensor are present but nothing is gripped"
      (with-seeded-random-state (5)
        (let ((world (make-world :width 80 :height 24 :fish-count 0 :shark-enabled-p nil)))
          (cl-asciiquarium::%add-world-creature
           world (threat-fixture world *alarm-only-threat* :x 0 :y 0))
          (cl-asciiquarium::%add-world-creature
           world (make-creature :world world :kind :sensor :frames (list "s") :x 50 :y 20
                                :policy :none :data (list :sense '(3 1 record-sense-call))))
          (cl-asciiquarium::%add-world-creature
           world (make-fish world :species :dart :x 60 :y 20 :dx 0))
          (expect (bytes-consed-by-passes world) :to-be 0))))
    (it "measures allocation: a consing control reads as nonzero"
      (let ((before (sb-ext:get-bytes-consed)))
        (dotimes (i 10000) (setf *allocation-sink* (list i)))
        (expect (plusp (- (sb-ext:get-bytes-consed) before)) :to-be-truthy)))))

(defvar *on-stop-calls* nil)

(defun record-on-stop (fish)
  (push fish *on-stop-calls*))

(describe "fish-stop-behaviour and :on-stop"
  (it "calls a fish's :on-stop exactly once, whether it is eaten, caught, or removed by -"
    (dolist (stop (list (lambda (world fish) (cl-asciiquarium::eat-effect world nil fish))
                        (lambda (world fish)
                          (cl-asciiquarium::catch-effect
                           world (threat-fixture world *body-catch-threat*) fish))
                        (lambda (world fish)
                          (declare (ignore fish))
                          (world-decrease-fish-count world))))
      (with-seeded-random-state (3)
        (let* ((world (make-world :width 40 :height 20 :fish-count 1 :shark-enabled-p nil))
               (fish (find-if #'cl-asciiquarium::alive-fish-p (cl-asciiquarium::world-%creatures world)))
               (*on-stop-calls* nil))
          (setf (getf (cl-asciiquarium::creature-data fish) :on-stop) 'record-on-stop)
          (funcall stop world fish)
          (cl-asciiquarium::fish-stop-behaviour fish)
          (expect *on-stop-calls* :to-equal (list fish))
          (expect (getf (cl-asciiquarium::creature-data fish) :on-stop) :to-be nil)))))
  (it "gives a lantern release-lantern-target as its :on-stop"
    (let ((world (tiny-world :width 40 :height 20)))
      (expect (getf (cl-asciiquarium::creature-data (make-fish world :species :lantern)) :on-stop)
              :to-be 'cl-asciiquarium::release-lantern-target))))
