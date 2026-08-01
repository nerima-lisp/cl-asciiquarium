(in-package #:cl-asciiquarium/test)

(describe "make-world"
  (it "signals invalid-dimensions for a non-positive width or height"
    (expect (lambda () (make-world :width 0 :height 10)) :to-throw 'invalid-dimensions)
    (expect (lambda () (make-world :width 10 :height -1)) :to-throw 'invalid-dimensions))
  (it "populates the background and the requested number of fish"
    (seeded 1
      (lambda ()
        (let ((world (make-world :width 40 :height 20 :fish-count 5)))
          (expect (world-width world) :to-be 40)
          (expect (world-height world) :to-be 20)
          (expect (world-tick world) :to-be 0)
          (expect (world-quitp world) :to-be-falsy)
          (expect (count :fish (world-creatures world) :key #'creature-kind) :to-be 5)
          (expect (count :waterline (world-creatures world) :key #'creature-kind) :to-be 1)
          (expect (count :castle (world-creatures world) :key #'creature-kind) :to-be 1))))))

(describe "world-advance"
  (it "increments the tick counter exactly once per call"
    (seeded 2
      (lambda ()
        (let ((world (make-world :width 40 :height 20 :fish-count 1)))
          (multiple-value-bind (final-world frames)
              (tick-loop-run world #'world-advance 5)
            (declare (ignore frames))
            (expect (world-tick final-world) :to-be 5))))))
  (it "moves a fish's position according to its velocity each tick"
    (let* ((world (tiny-world :width 40 :height 20))
           (fish (make-fish world :species :dart :x 5 :y 5 :dx 1)))
      (push fish (world-creatures world))
      (world-advance world)
      (expect (creature-x fish) :to-be 6)
      (world-advance world)
      (expect (creature-x fish) :to-be 7)))
  (it "wraps a fish back into the world when it swims off the right edge"
    (let* ((world (tiny-world :width 10 :height 10))
           (fish (make-fish world :species :dart :x 8 :y 3 :dx 1)))
      (push fish (world-creatures world))
      (dotimes (i 5) (world-advance world))
      (expect (>= (creature-x fish) 0) :to-be-truthy)
      (expect (< (creature-x fish) (world-width world)) :to-be-truthy))))

(describe "world-redraw"
  (it "removes existing fish and repopulates a fresh set, leaving the background"
    (seeded 3
      (lambda ()
        (let ((world (make-world :width 40 :height 20 :fish-count 4)))
          (let ((original-fish (remove :fish (world-creatures world) :key #'creature-kind :test-not #'eq)))
            (world-redraw world)
            (let ((new-fish (remove :fish (world-creatures world) :key #'creature-kind :test-not #'eq)))
              (expect (= (length new-fish) 4) :to-be-truthy)
              (expect (intersection original-fish new-fish) :to-be-falsy)))
          (expect (count :waterline (world-creatures world) :key #'creature-kind) :to-be 1)
          (expect (count :castle (world-creatures world) :key #'creature-kind) :to-be 1))))))
