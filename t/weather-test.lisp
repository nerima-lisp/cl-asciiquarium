;;;; t/weather-test.lisp -- the weather cycle, its sheets, lightning and
;;;; --calm, and the storm's boat sway.
(in-package #:cl-asciiquarium/test)

(defun %creatures-of-kind (world kind)
  (remove kind (cl-asciiquarium::world-%creatures world)
          :key #'cl-asciiquarium::creature-kind :test-not #'eq))

(defun %sheets (world)
  (remove-if-not (lambda (creature)
                   (member (cl-asciiquarium::creature-kind creature)
                           cl-asciiquarium::+weather-sheet-kinds+))
                 (cl-asciiquarium::world-%creatures world)))

(defun %storm-world (&key calm-p (fish-count 0) (width 40) (height 12))
  "A world held in a storm for good: the storm starts now and its next change
is far beyond any test's run."
  (let ((world (make-world :width width :height height :fish-count fish-count
                           :calm-p calm-p :shark-enabled-p nil)))
    (cl-asciiquarium::world-change-weather world :storm)
    (setf (cl-asciiquarium::world-weather-at world) most-positive-fixnum)
    world))

(defun %hud-text (world)
  (creature-art (first (%creatures-of-kind world :hud))))

(describe "weather cycle"
  (it "starts clear and changes first at a fixed tick inside 500-900"
    (let ((world (tiny-world)))
      (expect (cl-asciiquarium::world-weather world) :to-be :clear)
      (expect (<= 500 (cl-asciiquarium::world-weather-at world) 900) :to-be-truthy)))
  (it "goes clear -> rain -> storm -> clear, each weather lasting 500-900 ticks"
    (with-seeded-random-state (21)
      (let ((world (make-world :width 40 :height 12 :fish-count 0 :shark-enabled-p nil))
            (changes '()))
        (dotimes (i 2800)
          (let ((before (cl-asciiquarium::world-weather world)))
            (world-advance world)
            (unless (eq before (cl-asciiquarium::world-weather world))
              (push (cons (world-tick world) (cl-asciiquarium::world-weather world)) changes))))
        (setf changes (nreverse changes))
        (expect (>= (length changes) 3) :to-be-truthy)
        (expect (subseq (mapcar #'cdr changes) 0 3) :to-equal '(:rain :storm :clear))
        (expect (<= 500 (car (first changes)) 900) :to-be-truthy)
        (loop for (earlier later) on changes
              while later
              do (expect (<= 500 (- (car later) (car earlier)) 900) :to-be-truthy)))))
  (it "shows the current weather in the status bar, rebuilding it only when the weather changes"
    (let* ((world (make-world :width 80 :height 24 :fish-count 0 :shark-enabled-p nil))
           (art (%hud-text world)))
      (expect (search "clear" art) :to-be-truthy)
      (dotimes (i 20) (world-advance world))
      (expect (%hud-text world) :to-be art)
      (cl-asciiquarium::world-advance-weather world)
      (expect (search "rain" (%hud-text world)) :to-be-truthy)
      (cl-asciiquarium::world-advance-weather world)
      (expect (search "storm" (%hud-text world)) :to-be-truthy)
      (cl-asciiquarium::world-advance-weather world)
      (expect (search "clear" (%hud-text world)) :to-be-truthy))))

(describe "weather sheets"
  (it "keeps exactly one sheet per weather, created at the change, none when clear"
    (with-seeded-random-state (21)
      (let ((world (make-world :width 40 :height 12 :fish-count 0 :shark-enabled-p nil))
            (sheets-seen '())
            (changes 0))
        ;; Through one whole cycle: rain, storm, and back to clear.
        (loop until (= changes 3)
              do (let ((before (cl-asciiquarium::world-weather world)))
                   (world-advance world)
                   (unless (eq before (cl-asciiquarium::world-weather world))
                     (incf changes))
                   (let ((sheets (%sheets world)))
                     (expect (length sheets)
                             :to-be (if (eq (cl-asciiquarium::world-weather world) :clear) 0 1))
                     (when sheets (pushnew (first sheets) sheets-seen)))))
        (expect (mapcar #'cl-asciiquarium::creature-kind (reverse sheets-seen))
                :to-equal '(:rain-sheet :storm-sheet)))))
  (it "adds no creature while it rains"
    (let ((world (make-world :width 40 :height 12 :fish-count 0 :shark-enabled-p nil)))
      (setf (cl-asciiquarium::world-guest-cooldown world) most-positive-fixnum)
      (cl-asciiquarium::world-advance-weather world)
      (world-advance world)
      (let ((count (length (cl-asciiquarium::world-%creatures world))))
        (dotimes (i 300) (world-advance world))
        (expect (cl-asciiquarium::world-weather world) :to-be :rain)
        (expect (length (cl-asciiquarium::world-%creatures world)) :to-be count))))
  (it "rebuilds the sheet at the new width after a resize"
    (let ((world (make-world :width 40 :height 12 :fish-count 0)))
      (cl-asciiquarium::world-advance-weather world)
      (cl-asciiquarium::world-resize world 52 14)
      (let ((sheets (%sheets world)))
        (expect (length sheets) :to-be 1)
        (expect (cl-asciiquarium::creature-kind (first sheets)) :to-be :rain-sheet)
        (expect (creature-dimensions (first sheets)) :to-be 52))))
  (it "draws falling ' rain and ∘ ripples, and slanted / rain under dark clouds with choppy water"
    (let ((world (make-world :width 40 :height 24 :fish-count 0)))
      (cl-asciiquarium::world-advance-weather world)
      (let* ((rain (first (%sheets world)))
             (lines (cl-asciiquarium::split-sprite-lines (creature-art rain))))
        (expect (length lines) :to-be 7)
        (expect (find #\' (first lines)) :to-be-truthy)
        (expect (find #\∘ (nth 6 lines)) :to-be-truthy)
        (expect (string-trim " " (nth 5 lines)) :to-equal ""))
      (cl-asciiquarium::world-advance-weather world)
      (let* ((storm (first (%sheets world)))
             (lines (cl-asciiquarium::split-sprite-lines (creature-art storm))))
        (expect (length lines) :to-be 6)
        (expect (search ".(    )." (second lines)) :to-be-truthy)
        (expect (find #\/ (nth 3 lines)) :to-be-truthy)
        (expect (find #\^ (nth 5 lines)) :to-be-truthy))))
  (it "makes the rain fall: a drop is one row lower in the next frame"
    (let ((world (make-world :width 40 :height 24 :fish-count 0)))
      (cl-asciiquarium::world-advance-weather world)
      (let* ((rain (first (%sheets world)))
             (frames (cl-asciiquarium::creature-frames rain))
             (now (cl-asciiquarium::split-sprite-lines (aref frames 0)))
             (next (cl-asciiquarium::split-sprite-lines (aref frames 1))))
        (expect (char (nth 0 now) 0) :to-equal #\')
        (expect (char (nth 1 next) 0) :to-equal #\'))))
  (it "draws only ASCII under --ascii"
    (let* ((cl-asciiquarium::*ascii* t)
           (world (make-world :width 40 :height 24 :fish-count 0 :hud-visible-p nil)))
      (cl-asciiquarium::world-advance-weather world)
      (dolist (row (%drawn-rows world))
        (expect (every (lambda (character) (< (char-code character) 128)) row) :to-be-truthy)))))

(describe "lightning and --calm"
  (flet ((flash-history (calm-p)
           "Run a held storm for 2000 ticks. Return how many flashes appeared
and whether each one was present exactly on its first two ticks."
           (with-seeded-random-state (33)
             (let ((world (%storm-world :calm-p calm-p))
                   (born '())
                   (lifetimes-ok t))
               (dotimes (i 2000)
                 (world-advance world)
                 (let ((tick (world-tick world))
                       (flashes (%creatures-of-kind world :flash)))
                   (dolist (flash flashes)
                     (unless (assoc flash born)
                       (push (cons flash tick) born)))
                   (loop for (flash . birth) in born
                         unless (eq (and (member flash flashes) t) (< (- tick birth) 2))
                           do (setf lifetimes-ok nil))))
               (values (length born) lifetimes-ok)))))
    (it "never shows a flash under --calm during a 2000-tick storm"
      (expect (flash-history t) :to-be 0))
    (it "flashes at least once in the same storm without --calm, each flash lasting 2 ticks"
      (multiple-value-bind (count lifetimes-ok) (flash-history nil)
        (expect (plusp count) :to-be-truthy)
        (expect lifetimes-ok :to-be-truthy))))
  (it "moves every fish identically with and without --calm through a storm"
    (flet ((fish-positions (calm-p)
             (with-seeded-random-state (42)
               (let ((world (%storm-world :calm-p calm-p :fish-count 12 :width 80 :height 24)))
                 (dotimes (i 900) (world-advance world))
                 (loop for creature in (cl-asciiquarium::world-%creatures world)
                       when (eq (cl-asciiquarium::creature-kind creature) :fish)
                         collect (list (creature-x creature) (creature-y creature)))))))
      (let ((calm (fish-positions t)))
        (expect (plusp (length calm)) :to-be-truthy)
        (expect (fish-positions nil) :to-equal calm))))
  (it "creates a flash only through spawn-flash-now, which does nothing under --calm"
    (let ((calm (make-world :width 40 :height 12 :fish-count 0 :calm-p t))
          (normal (make-world :width 40 :height 12 :fish-count 0)))
      (cl-asciiquarium::spawn-flash-now calm 10)
      (cl-asciiquarium::spawn-flash-now normal 10)
      (expect (%creatures-of-kind calm :flash) :to-be-null)
      (let ((flash (first (%creatures-of-kind normal :flash))))
        (expect flash :to-be-truthy)
        (multiple-value-bind (width height) (creature-dimensions flash)
          (expect width :to-be 40)
          (expect height :to-be (cl-asciiquarium::world-waterline-row normal)))
        (expect (char (first (cl-asciiquarium::split-sprite-lines (creature-art flash))) 10)
                :to-equal #\/)))))

(defun %boat (world rise)
  (let ((boat (make-creature :world world :kind :boat :frames "B" :x 5 :y 0
                             :policy :none :data (list :boat-rise rise))))
    (cl-asciiquarium::%add-world-creature world boat)
    boat))

(describe "storm boat sway"
  ;; A 24-row screen has its waterline on row 5, so :boat-rise 2 is row 3.
  (it "keeps a :boat-rise creature within one row of its base during a storm, and back on it after"
    (let* ((world (%storm-world :height 24))
           (boat (%boat world 2))
           (rows '()))
      (dotimes (i 60)
        (world-advance world)
        (pushnew (creature-y boat) rows))
      (expect (sort rows #'<) :to-equal '(2 3 4))
      (cl-asciiquarium::world-change-weather world :clear)
      (world-advance world)
      (expect (creature-y boat) :to-be 3)))
  (it "leaves a creature without :boat-rise alone"
    (let* ((world (%storm-world))
           (other (make-creature :world world :kind :marker :frames "M" :x 5 :y 3 :policy :none)))
      (cl-asciiquarium::%add-world-creature world other)
      (dotimes (i 60) (world-advance world))
      (expect (creature-y other) :to-be 3)))
  (it "reports the sway offset: 0 when not storming, the boat's row minus its base in a storm"
    (let ((clear (make-world :width 40 :height 12 :fish-count 0)))
      (dotimes (i 30)
        (world-advance clear)
        (expect (cl-asciiquarium::storm-sway-offset clear) :to-be 0)))
    (let* ((world (%storm-world :height 24))
           (boat (%boat world 2))
           (offsets '()))
      (dotimes (i 60)
        (world-advance world)
        (let ((offset (cl-asciiquarium::storm-sway-offset world)))
          (pushnew offset offsets)
          (expect (creature-y boat) :to-be (+ 3 offset))
          (expect (cl-asciiquarium::boat-sway-row world 2) :to-be (+ 3 offset))))
      (expect (sort offsets #'<) :to-equal '(-1 0 1))))
  (it "never lifts a boat above row 0 when its base is row 0"
    ;; A 12-row screen has its waterline on row 2.
    (let* ((world (%storm-world :height 12))
           (boat (%boat world 2))
           (rows '()))
      (dotimes (i 60)
        (world-advance world)
        (pushnew (creature-y boat) rows))
      (expect (sort rows #'<) :to-equal '(0 1))))
  (it "keeps an anchor chain hanging from its ship's bottom row on every storm tick"
    (multiple-value-bind (world ship) (%anchor-ship-world :height 24)
      (cl-asciiquarium::world-change-weather world :storm)
      (setf (cl-asciiquarium::world-weather-at world) most-positive-fixnum)
      (let ((sway-steps 0)
            (ship-rows '())
            (previous-row (creature-y ship)))
        (dotimes (i 120)
          (world-advance world)
          (let ((chain (%anchor-kind world :chain)))
            (when chain
              (pushnew (creature-y ship) ship-rows)
              (unless (= previous-row (creature-y ship))
                (incf sway-steps))
              (expect (creature-y chain)
                      :to-be (+ (creature-y ship) (%anchor-data chain :ship-height)))))
          (setf previous-row (creature-y ship)))
        ;; Non-vacuity: the chain hung through ticks on which the ship moved
        ;; to another row, the ticks the old placement got wrong.
        (expect (plusp sway-steps) :to-be t)
        (expect (length ship-rows) :to-be 3))))
  (it "moves a ship to the new waterline on the tick after a resize"
    (let ((world (make-world :width 40 :height 12 :fish-count 0)))
      (spawn-guest-now world :ship)
      (let ((ship (first (%creatures-of-kind world :ship))))
        (world-advance world)
        (expect (creature-y ship) :to-be 1)
        (cl-asciiquarium::world-resize world 40 24)
        (world-advance world)
        (expect (creature-y ship) :to-be 4)))))

(describe "weather allocation"
  ;; See "apply-collisions: allocation" in collision-test.lisp for why ten
  ;; thousand calls.
  (it "conses nothing on a calm storm tick with a swaying boat"
    (with-seeded-random-state (5)
      (let ((world (%storm-world :calm-p t)))
        ;; Keep the time of day still: a repaint is a rare event that conses.
        (setf (cl-asciiquarium::world-daypart-at world) 0)
        (%boat world 1)
        (dotimes (i 100) (cl-asciiquarium::advance-sky-events world))
        (let ((before (sb-ext:get-bytes-consed)))
          (dotimes (i 10000)
            (incf (world-tick world))
            (cl-asciiquarium::advance-sky-events world))
          (expect (- (sb-ext:get-bytes-consed) before) :to-be 0))))))
