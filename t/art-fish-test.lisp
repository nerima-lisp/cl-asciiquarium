;;;; t/art-fish-test.lisp
(in-package #:cl-asciiquarium/test)

(describe "make-fish"
  (it "signals unknown-species for an unrecognized species keyword"
    (let ((world (tiny-world)))
      (expect (lambda () (make-fish world :species :nonexistent-species))
              :to-throw 'asciiquarium-unknown-species)))

  (it "builds the requested species, ignoring any random default"
    (let* ((world (tiny-world))
           (fish (make-fish world :species :puffer :x 3 :y 4 :dx 0)))
      (expect (creature-kind fish) :to-be :fish)
      (expect (getf (creature-data fish) :species) :to-be :puffer)))

  (it "positions the fish at the given x and y"
    (let* ((world (tiny-world))
           (fish (make-fish world :species :puffer :x 3 :y 4 :dx 0)))
      (expect (creature-x fish) :to-be 3)
      (expect (creature-y fish) :to-be 4)))

  (it "defaults to one of the known species and a lane inside the world, given a seed"
    (with-seeded-random-state (13)
      (let* ((world (tiny-world :width 40 :height 20))
             (fish (make-fish world)))
        (expect (member (getf (creature-data fish) :species) '(:dart :puffer :ribbon :angel :guppy))
                :to-be-truthy)
        (expect (<= 0 (creature-y fish) (world-height world)) :to-be-truthy))))

  (it-each ((:right) (:left))
      "an explicit :facing ~A is honored regardless of the random default"
      (facing)
    (let* ((world (tiny-world))
           (fish (make-fish world :species :dart :facing facing)))
      (expect (creature-facing fish) :to-be facing)))

  (it "lets an explicit :dx win for velocity even when :facing differs"
    (let* ((world (tiny-world))
           (fish (make-fish world :species :dart :facing :left :dx 1)))
      (expect (creature-facing fish) :to-be :left)
      (expect (entity-dx (creature-entity fish)) :to-be 1)))

  (it "uses a single-float velocity for generated movement"
    (let* ((world (tiny-world))
           (fish (make-fish world :species :dart)))
      (expect (typep (entity-dx (creature-entity fish)) 'single-float)
              :to-be-truthy))))

(describe "fish species color variation"
  (it "paints every individual with a style, none of them monochrome by default"
    (with-seeded-random-state (21)
      (let* ((world (tiny-world))
             (fish (make-fish world :species :guppy)))
        (expect (creature-style fish) :to-be-truthy))))
  (it "draws at least two different colors across many individuals of one species, given a seed"
    ;; :guppy's palette (art-fish.lisp) has three colors; spawning enough
    ;; individuals should hit more than one of them well before any
    ;; reasonable person would call that a coincidence.
    (with-seeded-random-state (17)
      (let* ((world (tiny-world))
             (styles (loop repeat 30 collect (creature-style (make-fish world :species :guppy)))))
        (expect (> (length (remove-duplicates styles :test #'equalp)) 1) :to-be-truthy)))))
(describe "make-fish sprite ownership"
  (it "does not expose mutable sprite frames through the public getter"
    (let ((cl-asciiquarium::*monochrome* t))
      (let* ((world (tiny-world))
             (fish (make-fish world :species :dart :x 3 :y 4 :dx 0 :facing :right))
             (original (creature-art fish))
             (frames (creature-frames fish)))
        (setf (char (aref frames 0) 0) #\X)
        (expect (creature-art fish) :to-equal original)))))
