(in-package #:cl-asciiquarium/test)

(describe "make-world"
  (it "signals invalid-dimensions for a non-positive width or height"
    (expect (lambda () (make-world :width 0 :height 10)) :to-throw 'asciiquarium-invalid-dimensions)
    (expect (lambda () (make-world :width 10 :height -1)) :to-throw 'asciiquarium-invalid-dimensions))
  (it "sets the given width and height"
    (with-seeded-random-state (1)
      (let ((world (make-world :width 40 :height 20 :fish-count 5)))
        (expect (world-width world) :to-be 40)
        (expect (world-height world) :to-be 20))))
  (it "starts with tick 0 and quitp unset"
    (with-seeded-random-state (1)
      (let ((world (make-world :width 40 :height 20 :fish-count 5)))
        (expect (world-tick world) :to-be 0)
        (expect (world-quitp world) :to-be-falsy))))
  (it "populates the requested number of fish"
    (with-seeded-random-state (1)
      (let ((world (make-world :width 40 :height 20 :fish-count 5)))
        (expect (count :fish (world-creatures world) :key #'creature-kind) :to-be 5))))
  (it "populates a fixed background regardless of fish count"
    (with-seeded-random-state (1)
      (let ((world (make-world :width 40 :height 20 :fish-count 5)))
        (expect (count :waterline (world-creatures world) :key #'creature-kind) :to-be 1)
        (expect (count :castle (world-creatures world) :key #'creature-kind) :to-be 1)
        ;; +default-seaweed-count+ (world.lisp) is 4; populate-background spawns
        ;; that many regardless of the requested fish count.
        (expect (count :seaweed (world-creatures world) :key #'creature-kind) :to-be 4)))))

(describe "world-advance"
  (it "increments the tick counter exactly once per call"
    (with-seeded-random-state (2)
      (let ((world (make-world :width 40 :height 20 :fish-count 1)))
        (multiple-value-bind (final-world frames)
            (tick-loop-run world #'world-advance 5)
          (declare (ignore frames))
          (expect (world-tick final-world) :to-be 5)))))
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
      (expect (< (creature-x fish) (world-width world)) :to-be-truthy)))
  (it-fuzz "never signals an error across many random world sizes and fish counts"
      ((width (gen-integer :min 5 :max 120))
       (height (gen-integer :min 5 :max 60))
       (fish-count (gen-integer :min 0 :max 20))
       (ticks (gen-integer :min 1 :max 60)))
      (:trials 50 :timeout-per-trial 2)
    (let ((world (make-world :width width :height height :fish-count fish-count)))
      (dotimes (i ticks) (world-advance world))))
  (it "removes a bubble once it rises to the waterline row"
    (let* ((world (tiny-world :width 40 :height 20))
           (bubble (make-creature :world world :kind :bubble :frames (list ".")
                                  :x 5 :y (1+ +waterline-row+) :dx 0 :dy -1 :policy :none)))
      (push bubble (world-creatures world))
      (world-advance world)
      (expect (member bubble (world-creatures world)) :to-be-falsy))))

(describe "world-advance while paused"
  (it "does not increment the tick counter"
    (let ((world (tiny-world :width 40 :height 20)))
      (setf (world-paused-p world) t)
      (world-advance world)
      (world-advance world)
      (expect (world-tick world) :to-be 0)))
  (it "does not move a fish's position"
    (let* ((world (tiny-world :width 40 :height 20))
           (fish (make-fish world :species :dart :x 5 :y 5 :dx 1)))
      (push fish (world-creatures world))
      (setf (world-paused-p world) t)
      (world-advance world)
      (expect (creature-x fish) :to-be 5)))
  (it "resumes advancing once unpaused"
    (let* ((world (tiny-world :width 40 :height 20))
           (fish (make-fish world :species :dart :x 5 :y 5 :dx 1)))
      (push fish (world-creatures world))
      (setf (world-paused-p world) t)
      (world-advance world)
      (setf (world-paused-p world) nil)
      (world-advance world)
      (expect (world-tick world) :to-be 1)
      (expect (creature-x fish) :to-be 6))))

(describe "world-increase-fish-count and world-decrease-fish-count"
  (it "increase adds one fish and raises world-fish-count"
    (with-seeded-random-state (8)
      (let ((world (tiny-world :width 40 :height 20 :fish-count 2)))
        (world-increase-fish-count world)
        (expect (world-fish-count world) :to-be 3)
        (expect (count :fish (world-creatures world) :key #'creature-kind) :to-be 3))))
  (it "increase refuses to grow past +max-fish-count+"
    (with-seeded-random-state (8)
      (let ((world (tiny-world :width 40 :height 20 :fish-count 0)))
        (setf (world-fish-count world) +max-fish-count+)
        (world-increase-fish-count world)
        (expect (world-fish-count world) :to-be +max-fish-count+))))
  (it "decrease removes one live fish and lowers world-fish-count"
    (with-seeded-random-state (8)
      (let ((world (tiny-world :width 40 :height 20 :fish-count 2)))
        (world-decrease-fish-count world)
        (expect (world-fish-count world) :to-be 1)
        (expect (count :fish (world-creatures world) :key #'creature-kind) :to-be 1))))
  (it "decrease at zero fish is a no-op"
    (let ((world (tiny-world :width 40 :height 20 :fish-count 0)))
      (world-decrease-fish-count world)
      (expect (world-fish-count world) :to-be 0)
      (expect (count :fish (world-creatures world) :key #'creature-kind) :to-be 0))))

(describe "%delete-removed-creatures"
  (labels ((marker (kind) (make-creature :kind kind :frames (list "x") :x 0 :y 0))
           (check (removed-indices expected-kinds expected-removedp)
             (let* ((creatures (list (marker :a) (marker :b) (marker :c)))
                    (original creatures))
               (dolist (index removed-indices)
                 (setf (creature-removep (nth index creatures)) t))
               (multiple-value-bind (survivors removedp)
                   (cl-asciiquarium::%delete-removed-creatures creatures)
                 (expect (mapcar #'creature-kind survivors) :to-equal expected-kinds)
                 (expect removedp :to-be expected-removedp)
                 (when (null removed-indices)
                   (expect survivors :to-be original))))))
    (it "filters removed creatures in one stable destructive pass"
      (check '(0) '(:b :c) t)
      (check '(1) '(:a :c) t)
      (check '(2) '(:a :b) t)
      (check '(0 1 2) nil t)
      (check nil '(:a :b :c) nil))))

(describe "world-redraw"
  (it "repopulates the requested number of fresh fish, none reused from before"
    (with-seeded-random-state (3)
      (let* ((world (make-world :width 40 :height 20 :fish-count 4))
             (original-fish (remove :fish (world-creatures world) :key #'creature-kind :test-not #'eq)))
        (world-redraw world)
        (let ((new-fish (remove :fish (world-creatures world) :key #'creature-kind :test-not #'eq)))
          (expect (= (length new-fish) 4) :to-be-truthy)
          (expect (intersection original-fish new-fish) :to-be-falsy)))))
  (it "leaves the background in place"
    (with-seeded-random-state (3)
      (let ((world (make-world :width 40 :height 20 :fish-count 4)))
        (world-redraw world)
        (expect (count :waterline (world-creatures world) :key #'creature-kind) :to-be 1)
        (expect (count :castle (world-creatures world) :key #'creature-kind) :to-be 1))))
  (it "clears every dolphin and sea-monster segment, the newer guest kinds"
    (let ((world (make-world :width 40 :height 20 :fish-count 0)))
      (spawn-guest-now world :dolphin)
      (spawn-guest-now world :sea-monster)
      (world-redraw world)
      (expect (find :dolphin (world-creatures world) :key #'creature-kind) :to-be-null)
      (expect (find :sea-monster (world-creatures world) :key #'creature-kind) :to-be-null)
      (expect (find :monster-segment (world-creatures world) :key #'creature-kind) :to-be-null)))
  (it "leaves the help overlay in place, since it is UI state, not aquarium population"
    (let ((world (make-world :width 40 :height 20 :fish-count 0)))
      (world-toggle-help-overlay world)
      (world-redraw world)
      (expect (find :help-overlay (world-creatures world) :key #'creature-kind) :to-be-truthy))))
