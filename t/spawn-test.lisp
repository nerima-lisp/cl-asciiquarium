(in-package #:cl-asciiquarium/test)

(describe "maybe-spawn-shark"
  (it "spawns nothing while the cooldown is still counting down"
    (let ((world (tiny-world :width 40 :height 20)))
      (setf (world-shark-cooldown world) 5)
      (maybe-spawn-shark world)
      (expect (find :shark (world-creatures world) :key #'creature-kind) :to-be-null)
      (expect (world-shark-cooldown world) :to-be 4)))
  (it "spawns a shark and resets the cooldown once it reaches zero"
    (seeded 7
      (lambda ()
        (let ((world (tiny-world :width 40 :height 20)))
          (setf (world-shark-cooldown world) 1)
          (maybe-spawn-shark world)
          (expect (find :shark (world-creatures world) :key #'creature-kind) :to-be-truthy)
          (expect (> (world-shark-cooldown world) 0) :to-be-truthy))))))

(describe "maybe-spawn-guest"
  (it "spawns nothing while the cooldown is still counting down"
    (let ((world (tiny-world :width 40 :height 20)))
      (setf (world-guest-cooldown world) 5)
      (maybe-spawn-guest world)
      (expect (world-creatures world) :to-be-null)
      (expect (world-guest-cooldown world) :to-be 4))))

(describe "deterministic special-guest spawn scenario, given a fixed seed"
  (it "spawns one of the two known guest kinds the moment its cooldown reaches zero"
    (seeded 3
      (lambda ()
        (let ((world (tiny-world :width 40 :height 20)))
          (setf (world-guest-cooldown world) 1)
          (maybe-spawn-guest world)
          (expect (member (creature-kind (first (world-creatures world))) '(:ship :duck-line))
                  :to-be-truthy)))))
  (it "spawns the identical guest kind given the identical seed, twice in a row"
    (flet ((spawned-kind (seed)
             (seeded seed
               (lambda ()
                 (let ((world (tiny-world :width 40 :height 20)))
                   (setf (world-guest-cooldown world) 1)
                   (maybe-spawn-guest world)
                   (creature-kind (first (world-creatures world))))))))
      (expect (spawned-kind 11) :to-be (spawned-kind 11))))
  (it "a ship eventually drops an anchor while advancing the world"
    (seeded 3
      (lambda ()
        (let* ((world (make-world :width 40 :height 20 :fish-count 0))
               (ship (make-ship world)))
          (push ship (world-creatures world))
          (dotimes (i 100)
            (world-advance world))
          (expect (find :anchor (world-creatures world) :key #'creature-kind) :to-be-truthy))))))

(describe "maybe-emit-bubble"
  (it "does not emit while the per-fish timer is still counting down"
    (let* ((world (tiny-world :width 40 :height 20))
           (fish (make-fish world :species :dart :x 5 :y 5 :dx 0)))
      (setf (getf (creature-data fish) :bubble-timer) 5)
      (maybe-emit-bubble world fish)
      (expect (find :bubble (world-creatures world) :key #'creature-kind) :to-be-null)
      (expect (getf (creature-data fish) :bubble-timer) :to-be 4)))
  (it "emits a bubble and resets the timer once it reaches zero"
    (seeded 9
      (lambda ()
        (let* ((world (tiny-world :width 40 :height 20))
               (fish (make-fish world :species :dart :x 5 :y 5 :dx 0)))
          (setf (getf (creature-data fish) :bubble-timer) 1)
          (maybe-emit-bubble world fish)
          (expect (find :bubble (world-creatures world) :key #'creature-kind) :to-be-truthy)
          (expect (> (getf (creature-data fish) :bubble-timer) 0) :to-be-truthy))))))
