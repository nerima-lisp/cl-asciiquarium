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
(describe "kill-fish"
  (it "does not restart an active death animation"
    (let* ((world (tiny-world))
           (fish (make-fish world :species :puffer :x 3 :y 4 :dx 1)))
      (cl-asciiquarium::kill-fish fish)
      (let ((data (copy-list (creature-data fish)))
            (ttl (creature-ttl fish))
            (frame-index (creature-frame-index fish))
            (dx (entity-dx (creature-entity fish)))
            (dy (entity-dy (creature-entity fish))))
        (cl-asciiquarium::kill-fish fish)
        (expect (creature-data fish) :to-equal data)
        (expect (creature-ttl fish) :to-be ttl)
        (expect (creature-frame-index fish) :to-be frame-index)
        (expect (entity-dx (creature-entity fish)) :to-be dx)
        (expect (entity-dy (creature-entity fish)) :to-be dy)))))

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
(describe "make-fish prepared sprite sharing"
  (it "shares a monochrome species prototype until public frame mutation"
    (let ((cl-asciiquarium::*monochrome* t)
          (cl-asciiquarium::*fish-sprite-prototypes*
            (make-hash-table :test #'eq)))
      (with-seeded-random-state (31)
        (let* ((world (tiny-world))
               (first
                 (make-fish world :species :dart :x 3 :y 4 :dx 0 :facing :right))
               (sibling
                 (make-fish world :species :dart :x 5 :y 4 :dx 0 :facing :right))
               (sibling-art
                 (copy-seq
                  (aref (cl-asciiquarium::creature-%frames sibling) 0))))
          (expect
            (cl-asciiquarium::creature-%prepared-frames first)
            :to-be
            (cl-asciiquarium::creature-%prepared-frames sibling))
          (expect
            (cl-asciiquarium::creature-%frames first)
            :to-be
            (cl-asciiquarium::creature-%frames sibling))
          (setf (char (aref (creature-frames first) 0) 0) #\X)
          (expect (creature-art first) :not :to-equal sibling-art)
          (expect
            (aref (cl-asciiquarium::creature-%frames sibling) 0)
            :to-equal
            sibling-art)
          (let ((future
                  (make-fish world :species :dart :x 7 :y 4 :dx 0 :facing :right)))
            (expect
              (cl-asciiquarium::creature-%prepared-frames future)
              :to-be
              (cl-asciiquarium::creature-%prepared-frames sibling))
            (expect
              (aref (cl-asciiquarium::creature-%frames future) 0)
              :to-equal
              sibling-art)))))))
