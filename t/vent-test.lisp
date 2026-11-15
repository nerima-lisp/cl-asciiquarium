(in-package #:cl-asciiquarium/test)

(defun %vent-world (&key (width 100) (height 30))
  "A seeded WORLD with no fish and no shark that has a vent and its plume."
  (with-seeded-random-state (11)
    (make-world :width width :height height :fish-count 0 :shark-enabled-p nil)))

(defun %plume (world)
  (cl-asciiquarium::find-creature-of-kind world :plume))

(defun %crab (world)
  (cl-asciiquarium::find-creature-of-kind world :crab))

(defun %add-dart (world x y)
  (let ((fish (make-fish world :species :dart :x x :y y :dx 0)))
    (cl-asciiquarium::%add-world-creature world fish)
    fish))

(defun %draws-no-random-p (function)
  "True when calling FUNCTION leaves *RANDOM-STATE* where it was."
  (let* ((before (make-random-state *random-state*))
         (after (progn (funcall function) *random-state*)))
    (= (random 1000000 before) (random 1000000 after))))

(describe "the vent plume"
  (it "is nine columns centered on the vent's mouth, from the swim band's top to the row above the vent"
    (let* ((world (%vent-world))
           (vent (cl-asciiquarium::find-creature-of-kind world :vent))
           (plume (%plume world)))
      (multiple-value-bind (x y width height) (creature-bounds plume)
        (with-soft-assertions
          (expect (+ x 4) :to-be (+ (creature-x vent) 3))
          (expect (char (creature-art vent) 3) :to-be #\^)
          (expect width :to-be 9)
          (expect y :to-be (world-swim-band world))
          (expect (+ y height) :to-be (creature-y vent))))))
  (it "carries the push threat row from creation"
    (expect (getf (cl-asciiquarium::creature-data (%plume (%vent-world))) :threat)
            :to-be cl-asciiquarium::+plume-threat+))
  (it "loops four frames of sparse bubbles that rise one row per frame"
    (let* ((plume (%plume (%vent-world)))
           (frames (loop for index below 4
                         collect (cl-asciiquarium::split-sprite-lines
                                  (cl-asciiquarium::plume-frame 9 16 index)))))
      (flet ((bubble-cells (lines)
               (mapcar (lambda (line) (substitute-if #\* (lambda (c) (char/= c #\Space)) line))
                       lines)))
        (expect (length (cl-asciiquarium::creature-%frames plume)) :to-be 4)
        (loop for (frame next) on (append frames (list (first frames)))
              while next
              do (expect (bubble-cells (rest frame)) :to-equal (bubble-cells (butlast next)))))
      (dolist (frame frames)
        (dolist (line frame)
          (expect (length line) :to-be 9)
          (expect (every (lambda (c) (find c " .oO")) line) :to-be-truthy)
          (expect (count #\Space line) :to-be-greater-than 5)))))
  (it "grows its bubbles from . at the vent to O at the top"
    (let ((lines (cl-asciiquarium::split-sprite-lines (cl-asciiquarium::plume-frame 9 12 0))))
      (expect (remove #\Space (format nil "~{~A~}" (last lines 4))) :to-equal ".....")
      (expect (remove #\Space (format nil "~{~A~}" (subseq lines 0 4))) :to-equal "OOOOO")))
  (it "draws no random number"
    (let* ((world (%vent-world))
           (vent (cl-asciiquarium::find-creature-of-kind world :vent)))
      (expect (%draws-no-random-p (lambda () (cl-asciiquarium::make-vent-plume world vent)))
              :to-be-truthy)))
  (it "follows the theme's bubble color"
    (let* ((*color-mode* :truecolor)
           (world (%vent-world))
           (plume (%plume world)))
      (world-set-theme world :coral)
      (expect (member (cl-asciiquarium::rgb-color :bubble :coral) (%creature-run-colors plume)
                      :test #'equal)
              :to-be-truthy)))
  (it "is absent when the terminal omits the vent"
    (let ((world (%vent-world :width 40 :height 30)))
      (expect (cl-asciiquarium::find-creature-of-kind world :vent) :to-be-null)
      (expect (%plume world) :to-be-null)))
  (it "is absent when the vent stands on the swim band's top row"
    (let* ((world (%vent-world :width 80 :height 11))
           (vent (cl-asciiquarium::find-creature-of-kind world :vent)))
      (expect (creature-y vent) :to-be (world-swim-band world))
      (expect (%plume world) :to-be-null)))
  (it "is rebuilt by world-resize: the old plume is marked removep and one new plume stands over the new vent"
    (let* ((world (%vent-world))
           (old (%plume world)))
      (world-resize world 80 24)
      (let ((plumes (remove :plume (cl-asciiquarium::world-%creatures world)
                            :key #'cl-asciiquarium::creature-kind :test-not #'eq)))
        (with-soft-assertions
          (expect (cl-asciiquarium::creature-removep old) :to-be-truthy)
          (expect (length plumes) :to-be 1)
          (expect (eq (first plumes) old) :to-be-falsy)
          (expect (+ (creature-y (first plumes))
                     (nth-value 1 (creature-dimensions (first plumes))))
                  :to-be (creature-y (cl-asciiquarium::find-creature-of-kind world :vent))))))))

(describe "push-effect"
  (it "lifts an overlapping fish every tick until it reaches the swim band's top, keeping it alive"
    (let* ((world (%vent-world))
           (plume (%plume world))
           (top (world-swim-band world))
           (fish (%add-dart world (+ (creature-x plume) 3) 15))
           (ys '()))
      (dotimes (tick 60)
        (world-advance world)
        (push (creature-y fish) ys))
      (setf ys (nreverse ys))
      (with-soft-assertions
        (expect (< (first ys) 15) :to-be-truthy)
        (expect (loop for (a b) on ys while b always (or (< b a) (= a b top))) :to-be-truthy)
        (expect (car (last ys)) :to-be top)
        (expect (cl-asciiquarium::alive-fish-p fish) :to-be-truthy))))
  (it "moves the fish +plume-push-rows-per-tick+ per collision pass"
    (let* ((world (%vent-world))
           (fish (%add-dart world (creature-x (%plume world)) 15)))
      (apply-collisions world)
      (expect (creature-y fish) :to-be (- 15 cl-asciiquarium::+plume-push-rows-per-tick+))))
  (it-each ((:left) (:right))
      "leaves a fish one column outside the ~S edge at its row"
      (side)
    (let* ((world (%vent-world))
           (plume (%plume world))
           (width (creature-dimensions (make-fish world :species :dart :x 0 :y 0 :dx 0)))
           (fish (%add-dart world (if (eq side :left)
                                      (- (creature-x plume) width)
                                      (+ (creature-x plume) 9))
                            15)))
      (dotimes (tick 20) (world-advance world))
      (expect (creature-y fish) :to-be 15)))
  (it "lifts a drifting fish's drift origin with it"
    (let* ((world (%vent-world))
           (fish (make-fish world :species :seahorse :x (creature-x (%plume world)) :y 15 :dx 0)))
      (cl-asciiquarium::%add-world-creature world fish)
      (dotimes (tick 30) (world-advance world))
      (with-soft-assertions
        (expect (< (creature-y fish) 14) :to-be-truthy)
        (expect (< (getf (cl-asciiquarium::creature-data fish) :drift-y) 14) :to-be-truthy))))
  (it "keeps a lantern's glow one row above the lantern it lifts"
    (let* ((world (%vent-world))
           (lantern (make-fish world :species :lantern :x (creature-x (%plume world)) :y 15 :dx 0)))
      (cl-asciiquarium::%add-world-creature world lantern)
      (world-set-theme world :moonlight)
      (dotimes (tick 10)
        (world-advance world)
        (let ((glow (getf (cl-asciiquarium::creature-data lantern) :glow)))
          (expect (creature-y glow) :to-be (1- (creature-y lantern)))))
      (expect (< (creature-y lantern) 14) :to-be-truthy)))
  (it "conses nothing on a collision pass with the plume and a fish inside it"
    (let* ((world (%vent-world))
           (fish (%add-dart world (creature-x (%plume world)) 15)))
      (dotimes (i 100) (apply-collisions world))
      (let ((before (sb-ext:get-bytes-consed)))
        (dotimes (i 10000) (apply-collisions world))
        (expect (- (sb-ext:get-bytes-consed) before) :to-be 0))
      (expect (creature-y fish) :to-be (world-swim-band world)))))

(describe "the crab"
  (it "stands on the sand above the status bar and walks right"
    (let* ((world (%vent-world))
           (crab (%crab world))
           (x (creature-x crab)))
      (expect (+ (creature-y crab) (nth-value 1 (creature-dimensions crab)))
              :to-be (world-sand-top world))
      (dotimes (tick 20) (world-advance world))
      (expect (> (creature-x crab) x) :to-be-truthy)
      (expect (creature-y crab) :to-be (- (world-sand-top world) 3))))
  (it-each ((:right) (:left))
      "turns around at the ~S edge and stays on screen"
      (edge)
    (let* ((world (%vent-world))
           (crab (%crab world))
           (entity (cl-asciiquarium::creature-entity crab))
           (limit (- (world-width world) 10)))
      (setf (entity-x entity) (if (eq edge :right) (- limit 0.1f0) 0.1f0)
            (entity-dx entity) (if (eq edge :right) 0.05f0 -0.05f0))
      (let ((xs (loop repeat 10 do (world-advance world) collect (creature-x crab))))
        (with-soft-assertions
          (expect (if (eq edge :right) (minusp (entity-dx entity)) (plusp (entity-dx entity)))
                  :to-be-truthy)
          (expect (every (lambda (x) (<= -1/2 x (+ limit 1/2))) xs) :to-be-truthy)
          (expect (if (eq edge :right)
                      (< (car (last xs)) limit)
                      (> (car (last xs)) 0))
                  :to-be-truthy)))))
  (it "alternates its two frames"
    (let* ((world (%vent-world))
           (crab (%crab world))
           (indices (loop repeat 13
                          do (world-advance world)
                          collect (cl-asciiquarium::creature-frame-index crab))))
      (expect (remove-duplicates indices) :to-have-length 2)
      (expect (nth 12 indices) :to-be (nth 0 indices))))
  (it "draws no random number"
    (let ((world (%vent-world)))
      (expect (%draws-no-random-p (lambda () (cl-asciiquarium::make-crab world)))
              :to-be-truthy)))
  (it "is not made on a screen narrower than the crab or too short for it"
    (expect (cl-asciiquarium::make-crab (%vent-world :width 9)) :to-be-null)
    (expect (cl-asciiquarium::make-crab (%vent-world :width 40 :height 10)) :to-be-null)
    (expect (%crab (%vent-world :width 40 :height 10)) :to-be-null))
  (it "is rebuilt by world-resize"
    (let* ((world (%vent-world))
           (old (%crab world)))
      (world-resize world 80 24)
      (let ((crabs (remove :crab (cl-asciiquarium::world-%creatures world)
                           :key #'cl-asciiquarium::creature-kind :test-not #'eq)))
        (expect (cl-asciiquarium::creature-removep old) :to-be-truthy)
        (expect (length crabs) :to-be 1)
        (expect (creature-y (first crabs)) :to-be (- (world-sand-top world) 3)))))
  (it "conses nothing while it walks and turns"
    (let* ((world (%vent-world))
           (crab (%crab world))
           (width (world-width world))
           (height (world-height world)))
      (setf (entity-dx (cl-asciiquarium::creature-entity crab)) 1.0f0)
      (dotimes (i 100) (cl-asciiquarium::tick-creature world crab width height))
      (let ((before (sb-ext:get-bytes-consed)))
        (dotimes (i 10000) (cl-asciiquarium::tick-creature world crab width height))
        (expect (- (sb-ext:get-bytes-consed) before) :to-be 0)))))
