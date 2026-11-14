(in-package #:cl-asciiquarium/test)

(describe "make-world"
  (it "signals invalid-dimensions for a non-positive width or height"
    (expect (lambda () (make-world :width 0 :height 10)) :to-throw 'asciiquarium-invalid-dimensions)
    (expect (lambda () (make-world :width 10 :height -1)) :to-throw 'asciiquarium-invalid-dimensions))
  (it "signals invalid-dimensions for non-integer dimensions" (dolist (dimensions (quote ((foo 10) (10 bar) (1.5 10) (10 1.5)))) (destructuring-bind (width height) dimensions (expect (lambda () (make-world :width width :height height)) :to-throw (quote asciiquarium-invalid-dimensions)))))
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
        (expect (count :fish (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 5))))
  (it "populates a fixed background regardless of fish count"
    (with-seeded-random-state (1)
      (let ((world (make-world :width 40 :height 20 :fish-count 5)))
        (expect (count :waterline (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 1)
        (expect (count :castle (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 1)
        ;; +default-seaweed-count+ (world.lisp) is 4; populate-background spawns
        ;; that many regardless of the requested fish count.
        (expect (count :seaweed (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 4)))))

(describe "visual themes, HUD, and ambient current"
  (it "builds the selected theme with a HUD and animated ambient current"
    (with-seeded-random-state (14)
      (let* ((world (make-world :width 40 :height 20 :fish-count 0
                                :theme :coral))
             (hud (find :hud (cl-asciiquarium::world-%creatures world)
                        :key #'cl-asciiquarium::creature-kind))
             (current (find :ambient-current
                            (cl-asciiquarium::world-%creatures world)
                            :key #'cl-asciiquarium::creature-kind)))
        (expect (world-theme world) :to-be :coral)
        (expect (cl-asciiquarium::world-hud-visible-p world) :to-be-truthy)
        (expect hud :to-be-truthy)
        (expect (search "CORAL" (creature-art hud)) :to-be-truthy)
        (expect current :to-be-truthy)
        ;; Four current rows spread through the 10-row water band of a
        ;; 20-row screen: two rows apart, so seven rows tall in all.
        (multiple-value-bind (width height) (creature-dimensions current)
          (expect width :to-be 40)
          (expect height :to-be 7)))))

  (it "cycles the theme and refreshes scene-owned UI"
    (let ((world (make-world :width 40 :height 20 :fish-count 0 :theme :abyss)))
      (world-cycle-theme world)
      (expect (world-theme world) :to-be :coral)
      (expect (search "CORAL"
                      (creature-art
                       (find :hud (cl-asciiquarium::world-%creatures world)
                             :key #'cl-asciiquarium::creature-kind)))
              :to-be-truthy)
      (world-cycle-theme world)
      (expect (world-theme world) :to-be :moonlight)))

  (it "toggles the HUD through world-owned scene state"
    (let ((world (make-world :width 40 :height 20 :fish-count 0)))
      (world-toggle-hud world)
      (expect (cl-asciiquarium::world-hud-visible-p world) :to-be-falsy)
      (expect (find :hud (cl-asciiquarium::world-%creatures world)
                    :key #'cl-asciiquarium::creature-kind)
              :to-be-null)
      (world-toggle-hud world)
      (expect (cl-asciiquarium::world-hud-visible-p world) :to-be-truthy)
      (expect (find :hud (cl-asciiquarium::world-%creatures world)
                    :key #'cl-asciiquarium::creature-kind)
              :to-be-truthy)))

  (it "rebuilds the ambient current to fit a resized world"
    (let ((world (make-world :width 20 :height 10 :fish-count 0)))
      (world-resize world 31 12)
      (let ((current (find :ambient-current
                           (cl-asciiquarium::world-%creatures world)
                           :key #'cl-asciiquarium::creature-kind)))
        ;; A 12-row screen leaves a 4-row water band: one current row each.
        (multiple-value-bind (width height) (creature-dimensions current)
          (expect width :to-be 31)
          (expect height :to-be 4))))))

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
      (cl-asciiquarium::%add-world-creature world fish)
      (world-advance world)
      (expect (creature-x fish) :to-be 6)
      (world-advance world)
      (expect (creature-x fish) :to-be 7)))
  (it "wraps a fish back into the world when it swims off the right edge"
    (let* ((world (tiny-world :width 10 :height 10))
           (fish (make-fish world :species :dart :x 8 :y 3 :dx 1)))
      (cl-asciiquarium::%add-world-creature world fish)
      (dotimes (i 5) (world-advance world))
      (expect (>= (creature-x fish) 0) :to-be-truthy)
      (expect (< (creature-x fish) (world-width world)) :to-be-truthy)))
  (it "still runs an exit callback for a stationary creature"
    (let* ((world (tiny-world :width 10 :height 10))
           (creature (make-creature :world world :kind :test :frames (list ".")
                                    :x -1 :y 3 :dx 0 :dy 0 :policy :wrap)))
      (cl-asciiquarium::%add-world-creature world creature)
      (world-advance world)
      (expect (creature-x creature) :to-be 9)))
  (it-fuzz "never signals an error across many random world sizes and fish counts"
      ((width (gen-integer :min 5 :max 120))
       (height (gen-integer :min 5 :max 60))
       (fish-count (gen-integer :min 0 :max 20))
       (ticks (gen-integer :min 1 :max 60)))
      (:trials 50 :timeout-per-trial 2)
    (let ((world (make-world :width width :height height :fish-count fish-count)))
      (dotimes (i ticks) (world-advance world))))
  (it-property "increments the tick counter for random unpaused worlds"
      ((width (gen-integer :min 5 :max 120))
       (height (gen-integer :min 5 :max 60))
       (fish-count (gen-integer :min 0 :max 20))
       (ticks (gen-integer :min 1 :max 60)))
    (let ((world (make-world :width width :height height :fish-count fish-count)))
      (dotimes (i ticks) (world-advance world))
      (= (world-tick world) ticks)))
  (it "removes a bubble once it rises to the waterline row"
    (let* ((world (tiny-world :width 40 :height 20))
           (bubble (make-creature :world world :kind :bubble :frames (list ".")
                                  :x 5 :y (1+ (cl-asciiquarium::world-waterline-row world)) :dx 0 :dy -1 :policy :none
                                  :data cl-asciiquarium::+bubble-data+)))
      (cl-asciiquarium::%add-world-creature world bubble)
      (world-advance world)
      (expect (member bubble (cl-asciiquarium::world-%creatures world)) :to-be-falsy))))
  (it "removes internally managed bubbles without exposing the creature list"
    (let* ((world (make-world :width 40 :height 20 :fish-count 0))
           (bubble (make-creature :world world :kind :bubble :frames (list ".")
                                  :x 5 :y (1+ (cl-asciiquarium::world-waterline-row world)) :dx 0 :dy -1 :policy :none
                                  :data cl-asciiquarium::+bubble-data+)))
      (cl-asciiquarium::%add-world-creature world bubble)
      (world-advance world)
      (expect (member bubble (cl-asciiquarium::world-%creatures world)) :to-be-falsy)
      (expect (cl-asciiquarium::world-removal-pending-p world) :to-be-falsy)))

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
      (cl-asciiquarium::%add-world-creature world fish)
      (setf (world-paused-p world) t)
      (world-advance world)
      (expect (creature-x fish) :to-be 5)))
  (it "resumes advancing once unpaused"
    (let* ((world (tiny-world :width 40 :height 20))
           (fish (make-fish world :species :dart :x 5 :y 5 :dx 1)))
      (cl-asciiquarium::%add-world-creature world fish)
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
        (expect (count :fish (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 3))))
  (it "increase stops at the world's max-fish"
    (with-seeded-random-state (8)
      (let ((world (make-world :width 40 :height 20 :fish-count 0 :max-fish 2)))
        (dolist (event (decode-input "+++"))
          (world-apply-key-event world event))
        (expect (world-fish-count world) :to-be 2)
        (expect (count :fish (cl-asciiquarium::world-%creatures world)
                       :key #'cl-asciiquarium::creature-kind)
                :to-be 2))))
  (it "caps max-fish at +max-fish-count+ without truncating the initial count"
    (with-seeded-random-state (8)
      (let ((world (make-world :width 40 :height 20 :fish-count 45 :max-fish 50)))
        (expect (cl-asciiquarium::world-max-fish world) :to-be +max-fish-count+)
        (expect (count :fish (cl-asciiquarium::world-%creatures world)
                       :key #'cl-asciiquarium::creature-kind)
                :to-be 45))))
  (it "defaults max-fish to 30 and leaves an initial count above it untruncated"
    (with-seeded-random-state (8)
      (let ((world (make-world :width 40 :height 20 :fish-count 31)))
        (expect (cl-asciiquarium::world-max-fish world) :to-be 30)
        (expect (count :fish (cl-asciiquarium::world-%creatures world)
                       :key #'cl-asciiquarium::creature-kind)
                :to-be 31))))
  (it "decrease marks one live fish removep, lowers world-fish-count, and the next tick deletes it"
    (with-seeded-random-state (8)
      (let ((world (tiny-world :width 40 :height 20 :fish-count 2)))
        (world-decrease-fish-count world)
        (expect (world-fish-count world) :to-be 1)
        (expect (count-if #'cl-asciiquarium::alive-fish-p (cl-asciiquarium::world-%creatures world))
                :to-be 1)
        (world-advance world)
        (expect (count :fish (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 1))))
  (it "decrease while paused still takes the fish off the list on the next world-advance"
    (with-seeded-random-state (8)
      (let ((world (tiny-world :width 40 :height 20 :fish-count 2)))
        (setf (world-paused-p world) t)
        (world-decrease-fish-count world)
        (world-advance world)
        (expect (world-tick world) :to-be 0)
        (expect (count :fish (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 1))))
  (it "two presses within one tick remove two different fish"
    (with-seeded-random-state (8)
      (let ((world (tiny-world :width 40 :height 20 :fish-count 3)))
        (world-decrease-fish-count world)
        (world-decrease-fish-count world)
        (let ((marked (remove-if-not #'cl-asciiquarium::creature-removep
                                     (cl-asciiquarium::world-%creatures world))))
          (expect (length marked) :to-be 2)
          (expect (every (lambda (fish) (null (getf (cl-asciiquarium::creature-data fish) :tick)))
                         marked)
                  :to-be-truthy))
        (world-advance world)
        (expect (count :fish (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 1))))
  (it "decrease at zero fish is a no-op"
    (let ((world (tiny-world :width 40 :height 20 :fish-count 0)))
      (world-decrease-fish-count world)
      (expect (world-fish-count world) :to-be 0)
      (expect (count :fish (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 0))))

(describe "%delete-removed-creatures"
  (labels ((marker (kind) (make-creature :kind kind :frames (list "x") :x 0 :y 0))
           (check (removed-indices expected-kinds expected-removedp)
             (let* ((creatures (list (marker :a) (marker :b) (marker :c)))
                    (original creatures))
               (dolist (index removed-indices)
                 (setf (cl-asciiquarium::creature-removep (nth index creatures)) t))
               (multiple-value-bind (survivors removedp)
                   (cl-asciiquarium::%delete-removed-creatures creatures)
                 (expect (mapcar #'cl-asciiquarium::creature-kind survivors) :to-equal expected-kinds)
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
             (original-fish (remove :fish (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind :test-not #'eq)))
        (world-redraw world)
        (let ((new-fish (remove :fish (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind :test-not #'eq)))
          (expect (= (length new-fish) 4) :to-be-truthy)
          (expect (intersection original-fish new-fish) :to-be-falsy)))))
  (it "leaves the background in place"
    (with-seeded-random-state (3)
      (let ((world (make-world :width 40 :height 20 :fish-count 4)))
        (world-redraw world)
        (expect (count :waterline (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 1)
        (expect (count :castle (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be 1))))
  (it "clears every dolphin and sea-monster segment, the newer guest kinds"
    (let ((world (make-world :width 40 :height 20 :fish-count 0)))
      (spawn-guest-now world :dolphin)
      (spawn-guest-now world :sea-monster)
      (world-redraw world)
      (expect (find :dolphin (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-null)
      (expect (find :sea-monster (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-null)
      (expect (find :monster-segment (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-null)))
  (it "leaves the help overlay in place, since it is UI state, not aquarium population"
    (let ((world (make-world :width 40 :height 20 :fish-count 0)))
      (world-toggle-help-overlay world)
      (world-redraw world)
      (expect (find :help-overlay (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind) :to-be-truthy))))

(describe "--calm"
  (it "blink-frame-period passes the period through, or NIL under calm"
    (expect (cl-asciiquarium::blink-frame-period (tiny-world) 6) :to-be 6)
    (expect (cl-asciiquarium::blink-frame-period (make-world :width 20 :height 10 :fish-count 0
                                                             :calm-p t)
                                                 6)
            :to-be nil))
  (it "holds a blinking creature built through blink-frame-period on its first frame"
    (dolist (calm-p '(nil t))
      (let* ((world (make-world :width 20 :height 10 :fish-count 0 :calm-p calm-p))
             (blinker (make-creature :world world :kind :blinker :frames (list "*" ".")
                                     :frame-period (cl-asciiquarium::blink-frame-period world 2)
                                     :x 1 :y 1 :policy :none)))
        (cl-asciiquarium::%add-world-creature world blinker)
        (dotimes (i 2) (world-advance world))
        (expect (cl-asciiquarium::creature-frame-index blinker) :to-be (if calm-p 0 1)))))
  (it "moves every fish identically with and without calm for the same seed"
    (flet ((fish-positions (calm-p)
             (with-seeded-random-state (42)
               (let ((world (make-world :width 80 :height 24 :calm-p calm-p)))
                 (dotimes (i 400) (world-advance world))
                 (loop for creature in (cl-asciiquarium::world-%creatures world)
                       when (eq (cl-asciiquarium::creature-kind creature) :fish)
                         collect (list (creature-x creature) (creature-y creature)))))))
      (let ((calm (fish-positions t)))
        (expect (plusp (length calm)) :to-be-truthy)
        (expect (fish-positions nil) :to-equal calm)))))

(describe "a `-' press survives another list change in the same input batch"
  (it-each (("-u" t) ("-u" nil) ("-h" t) ("-h" nil))
      "keys ~S with paused ~S: the removed fish is gone after the next world-advance"
      (keys paused)
    (with-seeded-random-state (8)
      (let ((world (tiny-world :width 80 :height 24 :fish-count 3)))
        (when (find #\h keys)
          (world-toggle-help-overlay world))
        (setf (world-paused-p world) paused)
        (world-apply-key-events world (decode-input keys))
        (expect (cl-asciiquarium::world-removal-pending-p world) :to-be t)
        (world-advance world)
        (expect (count :fish (cl-asciiquarium::world-%creatures world)
                       :key #'cl-asciiquarium::creature-kind)
                :to-be 2)
        (expect (cl-asciiquarium::world-removal-pending-p world) :to-be nil)))))

(describe "the + key never pushes live fish above max-fish"
  (it "raises the target but adds no fish while a visiting school fills the tank"
    (with-seeded-random-state (8)
      (let ((world (make-world :width 120 :height 30 :fish-count 24 :max-fish 30
                               :shark-enabled-p nil)))
        (cl-asciiquarium::spawn-school-now world)
        (expect (count-if #'cl-asciiquarium::alive-fish-p (cl-asciiquarium::world-%creatures world))
                :to-be 30)
        (dolist (event (decode-input "+++"))
          (world-apply-key-event world event))
        (expect (world-fish-count world) :to-be 27)
        (expect (count-if #'cl-asciiquarium::alive-fish-p (cl-asciiquarium::world-%creatures world))
                :to-be 30)))))
