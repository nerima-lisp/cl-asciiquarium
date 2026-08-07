(in-package #:cl-asciiquarium/test)

(describe "world-resize"
  (it "updates the stored width and height"
    (let ((world (tiny-world :width 40 :height 20)))
      (world-resize world 60 30)
      (expect (world-width world) :to-be 60)
      (expect (world-height world) :to-be 30)))
  (it "clamps a creature that the shrink left outside the new bounds"
    (let* ((world (tiny-world :width 40 :height 20))
           (fish (make-fish world :species :dart :x 35 :y 15 :dx 0)))
      (world-add-creature world fish)
      (world-resize world 20 10)
      (expect (< (creature-x fish) 20) :to-be-truthy)
      (expect (< (creature-y fish) 10) :to-be-truthy)))
  (it "leaves a creature already inside the new bounds untouched"
    (let* ((world (tiny-world :width 40 :height 20))
           (fish (make-fish world :species :dart :x 5 :y 5 :dx 0)))
      (world-add-creature world fish)
      (world-resize world 60 30)
      (expect (creature-x fish) :to-be 5)
      (expect (creature-y fish) :to-be 5)))
  (it "regenerates the waterline art to span the new width"
    (let ((world (tiny-world :width 40 :height 20)))
      (world-resize world 15 20)
      (let ((waterline (find :waterline (world-creatures world) :key #'creature-kind)))
        (expect (sprite-width (creature-art waterline)) :to-be 15))))
  (it "continues advancing normally after a mid-run resize"
    (let* ((world (tiny-world :width 40 :height 20))
           (fish (make-fish world :species :dart :x 5 :y 5 :dx 1)))
      (world-add-creature world fish)
      (world-advance world)
      (world-resize world 60 30)
      (world-advance world)
      (expect (world-tick world) :to-be 2)
      (expect (creature-x fish) :to-be 7)))
  (it "signals invalid-dimensions for a non-positive size"
    (let ((world (tiny-world :width 40 :height 20)))
      (expect (lambda () (world-resize world 0 10)) :to-throw 'asciiquarium-invalid-dimensions))))
