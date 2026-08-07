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
    (expect (getf (creature-data caught-fish) :dying) :to-be-truthy)
    (expect (creature-ttl caught-fish) :to-be +death-animation-ticks+)
    (expect (getf (creature-data safe-fish) :dying) :to-be-falsy)))
 (it
  "does not kill the same fish twice when it overlaps two predators"
  (let* ((world (tiny-world :width 40 :height 20))
         (shark-a
          (make-creature
           :world
           world
           :kind
           :shark
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
    (expect (creature-ttl fish) :to-be +death-animation-ticks+)))
 (it
  "removes a caught fish from the world after its death animation expires"
  (let* ((world (tiny-world :width 40 :height 20))
         (shark
          (make-creature
           :world
           world
           :kind
           :shark
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
           (list :target-depth 8 :dropped t)))
         (fish (make-fish world :species :dart :x 10 :y 8 :dx 0)))
    (cl-asciiquarium::%add-world-creature world anchor)
    (cl-asciiquarium::%add-world-creature world fish)
    (apply-collisions world)
    (expect (getf (creature-data fish) :dying) :to-be-truthy)))
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
           (list :target-depth 15 :dropped nil)))
         (fish (make-fish world :species :dart :x 10 :y 8 :dx 0)))
    (cl-asciiquarium::%add-world-creature world anchor)
    (cl-asciiquarium::%add-world-creature world fish)
    (apply-collisions world)
    (expect (getf (creature-data fish) :dying) :to-be-falsy))))

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
           (list :dropped t)))
         (anchor-fish (make-fish world :species :dart :x 5 :y 5 :dx 0))
         (shark-fish (make-fish world :species :dart :x 20 :y 5 :dx 0))
         (safe-fish (make-fish world :species :dart :x 45 :y 5 :dx 0)))
    (cl-asciiquarium::%set-world-creatures
     world
     (list anchor-fish shark safe-fish anchor shark-fish))
    (let ((before (copy-list (cl-asciiquarium::world-%creatures world))))
      (apply-collisions world)
      (expect (getf (creature-data anchor-fish) :dying) :to-be-truthy)
      (expect (getf (creature-data shark-fish) :dying) :to-be-truthy)
      (expect (getf (creature-data safe-fish) :dying) :to-be-falsy)
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
    (expect (getf (creature-data fish) :dying) :to-be-falsy)
    (setf (char frame 0) #\A)
    (setf (char frame 1) #\Newline)
    (apply-collisions world)
    (expect (getf (creature-data fish) :dying) :to-be-truthy)))
 (it
  "validates fish dimensions before scanning predators"
  (let* ((world (tiny-world :width 20 :height 10))
         (predator
          (make-creature
           :world
           world
           :kind
           :shark
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
    (expect (getf (creature-data fish) :dying) :to-be-falsy)
    (setf (char frame 0) #\F)
    (setf (char frame 1) #\Newline)
    (apply-collisions world)
    (expect (getf (creature-data fish) :dying) :to-be-truthy)))
 (it
  "keeps the one-time death conversion when multiple predators overlap"
  (let* ((world (tiny-world :width 30 :height 10))
         (shark-a
          (make-creature
           :world
           world
           :kind
           :shark
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
    (expect (getf (creature-data fish) :dying) :to-be-truthy)
    (expect (creature-ttl fish) :to-be +death-animation-ticks+)
    (expect (creature-art fish) :to-equal cl-asciiquarium::+fish-death-art+)
    (expect (entity-dx (creature-entity fish)) :to-be 0)
    (expect (entity-dy (creature-entity fish)) :to-be 0)
    (expect (getf (creature-data fish) :species) :to-be :test)))
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
    (expect (getf (creature-data overlapped) :dying) :to-be-truthy)
    (expect (getf (creature-data surviving) :dying) :to-be-falsy)))
 (it
  "refreshes cached position bounds between collision passes"
  (let* ((world (tiny-world :width 20 :height 10))
         (shark
          (make-creature
           :world
           world
           :kind
           :shark
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
    (expect (getf (creature-data fish) :dying) :to-be-falsy)
    (setf (entity-x (creature-entity fish)) 1)
    (apply-collisions world)
    (expect (getf (creature-data fish) :dying) :to-be-truthy))))

(describe "deterministic predator/prey scenario via a seeded shark spawn"
  (it "eventually spawns a shark and kills a fish placed in its path, given a fixed seed"
    (with-seeded-random-state (42)
      (let ((world (make-world :width 40 :height 10 :fish-count 0)))
        ;; Force an immediate shark spawn regardless of the random initial
        ;; cooldown, so this scenario is about the collision, not about how
        ;; long a shark's cooldown happens to draw.
        (setf (world-shark-cooldown world) 1)
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
           (list :dropped nil)))
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
    (expect (getf (creature-data fish) :dying) :to-be-falsy)
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
           (list :dropped nil)))
         (shark-fish (make-fish world :species :dart :x 0 :y 0 :dx 0))
         (anchor-fish (make-fish world :species :dart :x 10 :y 0 :dx 0)))
    (cl-asciiquarium::%set-world-creatures
     world
     (list shark anchor shark-fish anchor-fish))
    (expect (apply-collisions world) :to-be world)
    (expect (getf (creature-data shark-fish) :dying) :to-be-truthy)
    (expect (getf (creature-data anchor-fish) :dying) :to-be-falsy)
    (setf (creature-data anchor) (list :dropped t))
    (expect (apply-collisions world) :to-be world)
    (expect (getf (creature-data anchor-fish) :dying) :to-be-truthy)))
 (it
  "leaves dead fish outside cache and kill processing"
  (let* ((world (tiny-world :width 20 :height 10))
         (shark
          (make-creature
           :world
           world
           :kind
           :shark
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
    (setf (creature-ttl fish) 7
          (cl-asciiquarium::creature-collision-left fish) 91
          (cl-asciiquarium::creature-collision-top fish) 92
          (cl-asciiquarium::creature-collision-width fish) 93
          (cl-asciiquarium::creature-collision-height fish) 94)
    (expect (apply-collisions world) :to-be world)
    (expect (getf (creature-data fish) :dying) :to-be-truthy)
    (expect (creature-ttl fish) :to-be 7)
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
           (list :dropped t)))
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
    (setf (creature-ttl already-dying) 7)
    (expect (apply-collisions world) :to-be world)
    (expect (getf (creature-data shark-fish) :dying) :to-be-truthy)
    (expect (getf (creature-data anchor-fish) :dying) :to-be-truthy)
    (expect (getf (creature-data already-dying) :dying) :to-be-truthy)
    (expect (creature-ttl already-dying) :to-be 7)
    (expect (getf (creature-data safe-fish) :dying) :to-be-falsy))))
