(in-package #:cl-asciiquarium/test)

(describe "world-apply-key-event"
  (it "sets quitp on a lowercase q key event"
    (let ((world (tiny-world)))
      (dolist (event (decode-input "q"))
        (world-apply-key-event world event))
      (expect (world-quitp world) :to-be-truthy)))
  (it "sets quitp on an uppercase Q key event"
    (let ((world (tiny-world)))
      (dolist (event (decode-input "Q"))
        (world-apply-key-event world event))
      (expect (world-quitp world) :to-be-truthy)))
  (it "leaves quitp unset for an unrelated key"
    (let ((world (tiny-world)))
      (dolist (event (decode-input "x"))
        (world-apply-key-event world event))
      (expect (world-quitp world) :to-be-falsy)))
  (it "calls world-redraw on an r key event, repopulating fish"
    (seeded 4
      (lambda ()
        (let ((world (make-world :width 40 :height 20 :fish-count 3))
              (original-tick 0))
          (declare (ignore original-tick))
          (let ((original-fish (remove :fish (world-creatures world) :key #'creature-kind :test-not #'eq)))
            (dolist (event (decode-input "r"))
              (world-apply-key-event world event))
            (let ((new-fish (remove :fish (world-creatures world) :key #'creature-kind :test-not #'eq)))
              (expect (= (length new-fish) 3) :to-be-truthy)
              (expect (intersection original-fish new-fish) :to-be-falsy))))))))

(describe "world-apply-key-events"
  (it "applies a sequence of decoded events in order"
    (let ((world (tiny-world)))
      (world-apply-key-events world (decode-input "xq"))
      (expect (world-quitp world) :to-be-truthy))))
