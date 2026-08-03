(in-package #:cl-asciiquarium/test)

(describe "apply-collisions: shark versus fish"
  (it "kills an alive fish overlapping a shark, leaving a non-overlapping fish alone"
    (let* ((world (tiny-world :width 40 :height 20))
           (shark (make-creature :world world :kind :shark :frames (list "=<{(o.o)}==>")
                                  :x 10 :y 5 :dx 0 :dy 0 :policy :none))
           (caught-fish (make-fish world :species :dart :x 12 :y 5 :dx 0))
           (safe-fish (make-fish world :species :dart :x 30 :y 5 :dx 0)))
      (push shark (world-creatures world))
      (push caught-fish (world-creatures world))
      (push safe-fish (world-creatures world))
      (apply-collisions world)
      (expect (getf (creature-data caught-fish) :dying) :to-be-truthy)
      (expect (creature-ttl caught-fish) :to-be +death-animation-ticks+)
      (expect (getf (creature-data safe-fish) :dying) :to-be-falsy)))
  (it "does not kill the same fish twice when it overlaps two predators"
    (let* ((world (tiny-world :width 40 :height 20))
           (shark-a (make-creature :world world :kind :shark :frames (list "=<{(o.o)}==>")
                                    :x 10 :y 5 :dx 0 :dy 0 :policy :none))
           (shark-b (make-creature :world world :kind :shark :frames (list "=<{(o.o)}==>")
                                    :x 11 :y 5 :dx 0 :dy 0 :policy :none))
           (fish (make-fish world :species :dart :x 12 :y 5 :dx 0)))
      (push shark-a (world-creatures world))
      (push shark-b (world-creatures world))
      (push fish (world-creatures world))
      (apply-collisions world)
      (expect (creature-ttl fish) :to-be +death-animation-ticks+)))
  (it "removes a caught fish from the world after its death animation expires"
    (let* ((world (tiny-world :width 40 :height 20))
           (shark (make-creature :world world :kind :shark :frames (list "=<{(o.o)}==>")
                                  :x 10 :y 5 :dx 0 :dy 0 :policy :none))
           (fish (make-fish world :species :dart :x 12 :y 5 :dx 0)))
      (push shark (world-creatures world))
      (push fish (world-creatures world))
      (dotimes (i (1+ +death-animation-ticks+)) (world-advance world))
      (expect (member fish (world-creatures world)) :to-be-falsy))))

(describe "apply-collisions: dropped anchor versus fish"
  (it "kills a fish directly beneath a dropped anchor"
    (let* ((world (tiny-world :width 40 :height 20))
           (anchor (make-creature :world world :kind :anchor :frames (list "( o )")
                                  :x 10 :y 8 :dx 0 :dy 0 :policy :none
                                  :data (list :target-depth 8 :dropped t)))
           (fish (make-fish world :species :dart :x 10 :y 8 :dx 0)))
      (push anchor (world-creatures world))
      (push fish (world-creatures world))
      (apply-collisions world)
      (expect (getf (creature-data fish) :dying) :to-be-truthy)))
  (it "does not kill a fish beneath an anchor that has not been dropped yet"
    (let* ((world (tiny-world :width 40 :height 20))
           (anchor (make-creature :world world :kind :anchor :frames (list "( o )")
                                  :x 10 :y 8 :dx 0 :dy 1 :policy :none
                                  :data (list :target-depth 15 :dropped nil)))
           (fish (make-fish world :species :dart :x 10 :y 8 :dx 0)))
      (push anchor (world-creatures world))
      (push fish (world-creatures world))
      (apply-collisions world)
      (expect (getf (creature-data fish) :dying) :to-be-falsy))))
(describe "apply-collisions: single outer scan semantics"
  (it "handles interleaved predator kinds without changing creature order"
    (let* ((world (tiny-world :width 60 :height 20))
           (shark (make-creature :world world :kind :shark :frames (list "SSS")
                                 :x 20 :y 5 :dx 0 :dy 0 :policy :none))
           (anchor (make-creature :world world :kind :anchor :frames (list "AAA")
                                  :x 5 :y 5 :dx 0 :dy 0 :policy :none
                                  :data (list :dropped t)))
           (anchor-fish (make-fish world :species :dart :x 5 :y 5 :dx 0))
           (shark-fish (make-fish world :species :dart :x 20 :y 5 :dx 0))
           (safe-fish (make-fish world :species :dart :x 45 :y 5 :dx 0)))
      (setf (world-creatures world)
            (list anchor-fish shark safe-fish anchor shark-fish))
      (let ((before (copy-list (world-creatures world))))
        (apply-collisions world)
        (expect (getf (creature-data anchor-fish) :dying) :to-be-truthy)
        (expect (getf (creature-data shark-fish) :dying) :to-be-truthy)
        (expect (getf (creature-data safe-fish) :dying) :to-be-falsy)
        (expect (every (function eq) before (world-creatures world))
                :to-be-truthy)))))

(describe "apply-collisions: validated bounds cache"
          (it "uses dimensions rebuilt after a case-only and structural direct frame mutation"
              (let* ((world (tiny-world :width 20 :height 10))
                     (predator (make-creature :world world :kind :shark :frames (list "aa ")
                                              :x 0 :y 0 :dx 0 :dy 0 :policy :none))
                     (fish (make-creature :world world :kind :fish :frames (list "f")
                                          :x 0 :y 1 :dx 1 :dy 0 :policy :none
                                          :data (list :species :test)))
                     (frame (aref (creature-frames predator) 0)))
                (setf (world-creatures world) (list predator fish))
                (apply-collisions world)
                (expect (getf (creature-data fish) :dying) :to-be-falsy)
                (setf (char frame 0) #\A)
                (setf (char frame 1) #\Newline)
                (apply-collisions world)
                (expect (getf (creature-data fish) :dying) :to-be-truthy)))

          (it "validates fish dimensions before scanning predators"
              (let* ((world (tiny-world :width 20 :height 10))
                     (predator (make-creature :world world :kind :shark :frames (list "p")
                                              :x 0 :y 1 :dx 0 :dy 0 :policy :none))
                     (fish (make-creature :world world :kind :fish :frames (list "ff ")
                                          :x 0 :y 0 :dx 1 :dy 0 :policy :none
                                          :data (list :species :test)))
                     (frame (aref (creature-frames fish) 0)))
                (setf (world-creatures world) (list predator fish))
                (apply-collisions world)
                (expect (getf (creature-data fish) :dying) :to-be-falsy)
                (setf (char frame 0) #\F)
                (setf (char frame 1) #\Newline)
                (apply-collisions world)
                (expect (getf (creature-data fish) :dying) :to-be-truthy)))
          (it "keeps the one-time death conversion when multiple predators overlap"
              (let* ((world (tiny-world :width 30 :height 10))
                     (shark-a (make-creature :world world :kind :shark :frames (list "SSS")
                                             :x 5 :y 3 :dx 0 :dy 0 :policy :none))
                     (shark-b (make-creature :world world :kind :shark :frames (list "SSS")
                                             :x 5 :y 3 :dx 0 :dy 0 :policy :none))
                     (fish (make-creature :world world :kind :fish :frames (list "fff")
                                          :x 5 :y 3 :dx 2 :dy 1 :policy :none
                                          :data (list :species :test))))
                (setf (world-creatures world) (list shark-a fish shark-b))
                (apply-collisions world)
                (expect (getf (creature-data fish) :dying) :to-be-truthy)
                (expect (creature-ttl fish) :to-be +death-animation-ticks+)
                (expect (creature-art fish) :to-equal cl-asciiquarium::+fish-death-art+)
                (expect (entity-dx (creature-entity fish)) :to-be 0)
                (expect (entity-dy (creature-entity fish)) :to-be 0)
                (expect (getf (creature-data fish) :species) :to-be :test))))

(describe "deterministic predator/prey scenario via a seeded shark spawn"
  (it "eventually spawns a shark and kills a fish placed in its path, given a fixed seed"
    (with-seeded-random-state (42)
      (let ((world (make-world :width 40 :height 10 :fish-count 0)))
        ;; Force an immediate shark spawn regardless of the random initial
        ;; cooldown, so this scenario is about the collision, not about how
        ;; long a shark's cooldown happens to draw.
        (setf (world-shark-cooldown world) 1)
        (let ((fish (make-fish world :species :dart :x 20 :y 4 :dx 0)))
          (push fish (world-creatures world))
          (dotimes (i 200)
            (unless (member fish (world-creatures world))
              (return))
            (world-advance world))
          (expect (member fish (world-creatures world)) :to-be-falsy))))))
