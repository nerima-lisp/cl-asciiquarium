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

(describe "deterministic predator/prey scenario via a seeded shark spawn"
  (it "eventually spawns a shark and kills a fish placed in its path, given a fixed seed"
    (seeded 42
      (lambda ()
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
            (expect (member fish (world-creatures world)) :to-be-falsy)))))))
