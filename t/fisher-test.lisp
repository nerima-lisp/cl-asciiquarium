;;;; t/fisher-test.lisp -- the fisher event (src/art-fisher.lisp,
;;;; src/update-fisher.lisp): the boat arrives, lowers its line and hook,
;;;; reels in a catch or rises empty, and leaves. GULL-WORLD,
;;;; WORLD-KIND-CREATURES, and PARKED-DART come from t/gull-test.lisp.
(in-package #:cl-asciiquarium/test)

(defun boat-data (boat key)
  (getf (cl-asciiquarium::creature-data boat) key))

(defun advance-until-phase (world boat phase limit)
  (loop repeat limit
        until (eq (boat-data boat :phase) phase)
        do (world-advance world))
  (boat-data boat :phase))

(defun present-p (world creature)
  (and (member creature (cl-asciiquarium::world-%creatures world)) t))

(describe "the fisher lowers a line and a hook"
  (it "sails in, stops, and lowers the hook on a line hanging from the rod"
    (with-seeded-random-state (5)
      (let* ((world (gull-world))
             (boat (cl-asciiquarium::spawn-fisher-now world))
             (line (boat-data boat :line))
             (hook (boat-data boat :hook)))
        (expect (cl-asciiquarium::creature-kind boat) :to-be :fisher)
        (expect (present-p world line) :to-be nil)
        (expect (advance-until-phase world boat :lower 400) :to-be :lower)
        (let ((first-hook-y (creature-y hook)))
          (dotimes (i 10) (world-advance world))
          (with-soft-assertions
            (expect (present-p world line) :to-be t)
            (expect (present-p world hook) :to-be t)
            (expect (> (creature-y hook) first-hook-y) :to-be t)
            (expect (creature-y line) :to-be (1+ (creature-y boat)))
            (expect (+ (creature-y line) (nth-value 1 (creature-dimensions line)))
                    :to-be (creature-y hook))
            (expect (creature-x line) :to-be (creature-x hook))
            (expect (cl-asciiquarium::boat-sway-row world (boat-data boat :boat-rise))
                    :to-be (creature-y boat))
            (expect (boat-data hook :threat) :to-be cl-asciiquarium::+hook-threat+))))))
  (it "keeps the line between the rod and the hook on every tick of a storm's sway"
    (with-seeded-random-state (5)
      (let* ((world (gull-world))
             (boat (cl-asciiquarium::spawn-fisher-now world))
             (line (boat-data boat :line))
             (hook (boat-data boat :hook))
             (boat-rows nil)
             (misplaced nil))
        (advance-until-phase world boat :lower 400)
        (cl-asciiquarium::world-change-weather world :storm)
        (setf (cl-asciiquarium::world-weather-at world) most-positive-fixnum)
        ;; One full sway cycle is 6 steps of 6 ticks.
        (dotimes (i 36)
          (world-advance world)
          (pushnew (creature-y boat) boat-rows)
          (unless (and (= (creature-y line) (1+ (creature-y boat)))
                       (= (+ (creature-y line) (nth-value 1 (creature-dimensions line)))
                          (creature-y hook)))
            (push (world-tick world) misplaced)))
        (expect (sort boat-rows #'<)
                :to-equal (let ((base (- (world-waterline-row world)
                                         (boat-data boat :boat-rise))))
                            (list (1- base) base (1+ base))))
        (expect misplaced :to-be nil)))))

(describe "the fisher's catch"
  (it "hooks a touching fish, reels it up, cheers, and leaves"
    (with-seeded-random-state (5)
      (let* ((world (gull-world))
             (boat (cl-asciiquarium::spawn-fisher-now world))
             (hook (boat-data boat :hook))
             (cheer (boat-data boat :cheer)))
        (advance-until-phase world boat :lower 400)
        (let* ((fish (parked-dart world (- (creature-x hook) 2) (+ (creature-y hook) 4)))
               (caught-y nil)
               (top-fish-y nil))
          (loop repeat 100
                until (eq (cl-asciiquarium::creature-kind fish) :caught-fish)
                do (world-advance world))
          (expect (cl-asciiquarium::creature-kind fish) :to-be :caught-fish)
          (expect (eq (getf (cl-asciiquarium::creature-data fish) :captor) hook) :to-be t)
          (setf caught-y (creature-y fish)
                top-fish-y caught-y)
          (loop repeat 100
                until (present-p world cheer)
                do (world-advance world)
                   (unless (cl-asciiquarium::creature-removep fish)
                     (setf top-fish-y (min top-fish-y (creature-y fish)))))
          (with-soft-assertions
            (expect (present-p world cheer) :to-be t)
            (expect (cl-asciiquarium::creature-art cheer) :to-equal "!")
            (expect (< (creature-y cheer) (creature-y boat)) :to-be t)
            (expect (<= (creature-x boat) (creature-x cheer)
                        (+ (creature-x boat) (creature-dimensions boat) -1))
                    :to-be t)
            (expect (< top-fish-y caught-y) :to-be t)
            (expect (cl-asciiquarium::creature-removep fish) :to-be t)
            (expect (cl-asciiquarium::creature-removep hook) :to-be t)
            (expect (boat-data boat :phase) :to-be :cheer))
          (expect (advance-until-phase world boat :leave (1+ cl-asciiquarium::+fisher-cheer-ticks+))
                  :to-be :leave)
          (loop repeat 400
                until (cl-asciiquarium::creature-removep boat)
                do (world-advance world))
          (expect (cl-asciiquarium::creature-removep boat) :to-be t)
          (expect (present-p world cheer) :to-be nil))))))

(describe "the fisher's hook holds one fish"
  (it "catches exactly one of two fish touching the hook"
    (with-seeded-random-state (5)
      (let* ((world (gull-world))
             (boat (cl-asciiquarium::spawn-fisher-now world))
             (hook (boat-data boat :hook)))
        (advance-until-phase world boat :lower 400)
        (let* ((x (- (creature-x hook) 2))
               (y (+ (creature-y hook) 4))
               (fishes (list (parked-dart world x y) (parked-dart world x y))))
          (loop repeat 100
                until (find :caught-fish fishes :key #'cl-asciiquarium::creature-kind)
                do (world-advance world))
          (world-advance world)
          (expect (count :caught-fish fishes :key #'cl-asciiquarium::creature-kind) :to-be 1)
          (expect (count-if #'cl-asciiquarium::alive-fish-p fishes) :to-be 1))))))

(describe "the fisher and the screen size"
  (it "stops inside a screen narrowed while it sails in"
    (dolist (facing '(:left :right))
      (with-seeded-random-state (5)
        (let* ((world (gull-world))
               (boat (cl-asciiquarium::%add-world-creature
                      world (cl-asciiquarium::make-fisher world :facing facing))))
          (setf (getf (cl-asciiquarium::creature-data boat) :stop-x) 70)
          (dotimes (i 10) (world-advance world))
          (world-resize world 40 24)
          (expect (list facing (advance-until-phase world boat :lower 400))
                  :to-equal (list facing :lower))
          (world-advance world)
          (let ((line-x (creature-x (boat-data boat :line))))
            (expect (list facing (<= 0 line-x 39)
                          (<= 0 (creature-x boat) (- 40 (creature-dimensions boat))))
                    :to-equal (list facing t t))))))))

(describe "the fisher after the screen shrinks"
  (it "keeps the boat on the new waterline and the hook above the new sand"
    (with-seeded-random-state (5)
      (let* ((world (make-world :width 80 :height 30 :fish-count 0 :shark-enabled-p nil
                                :hud-visible-p nil :theme :coral))
             (boat (progn (remove-gulls world)
                          (setf (cl-asciiquarium::world-guest-cooldown world)
                                most-positive-fixnum)
                          (cl-asciiquarium::spawn-fisher-now world)))
             (line (boat-data boat :line))
             (hook (boat-data boat :hook)))
        (expect (advance-until-phase world boat :wait 400) :to-be :wait)
        (world-resize world 80 12)
        (world-advance world)
        (with-soft-assertions
          (expect (creature-y boat) :to-be (- (world-waterline-row world) 2))
          (expect (< (creature-y hook) (world-sand-top world)) :to-be t)
          (expect (creature-y line) :to-be (1+ (creature-y boat)))
          (expect (+ (creature-y line) (nth-value 1 (creature-dimensions line)))
                  :to-be (creature-y hook)))))))

(describe "the fisher's line in a storm"
  (it "keeps its length through a full sway cycle while the hook stays out of the sand"
    (with-seeded-random-state (5)
      (let* ((world (gull-world))
             (boat (cl-asciiquarium::spawn-fisher-now world))
             (hook (boat-data boat :hook))
             (lowest-hook-y 0))
        (expect (advance-until-phase world boat :wait 400) :to-be :wait)
        (setf (getf (cl-asciiquarium::creature-data boat) :wait-until) most-positive-fixnum)
        (let ((depth (boat-data boat :depth)))
          (cl-asciiquarium::world-change-weather world :storm)
          (setf (cl-asciiquarium::world-weather-at world) most-positive-fixnum)
          (dotimes (i 36)
            (world-advance world)
            (setf lowest-hook-y (max lowest-hook-y (creature-y hook))))
          (cl-asciiquarium::world-change-weather world :clear)
          (setf (cl-asciiquarium::world-weather-at world) most-positive-fixnum)
          (world-advance world)
          (with-soft-assertions
            (expect (boat-data boat :depth) :to-equal depth)
            (expect (<= lowest-hook-y (1- (world-sand-top world))) :to-be t)
            (expect (creature-y hook) :to-be (1- (world-sand-top world)))))))))

(describe "the fisher with nothing to catch"
  (it "sinks the hook to the sand, waits 80 ticks, reels it up empty, and leaves"
    (with-seeded-random-state (5)
      (let* ((world (gull-world))
             (boat (cl-asciiquarium::spawn-fisher-now world))
             (line (boat-data boat :line))
             (hook (boat-data boat :hook)))
        (expect (advance-until-phase world boat :wait 400) :to-be :wait)
        (expect (creature-y hook) :to-be (1- (world-sand-top world)))
        (dotimes (i 79) (world-advance world))
        (expect (boat-data boat :phase) :to-be :wait)
        (world-advance world)
        (expect (boat-data boat :phase) :to-be :reel)
        (expect (advance-until-phase world boat :leave 400) :to-be :leave)
        (with-soft-assertions
          (expect (cl-asciiquarium::creature-removep line) :to-be t)
          (expect (cl-asciiquarium::creature-removep hook) :to-be t)
          (expect (null (boat-data boat :prey)) :to-be t)
          (expect (present-p world (boat-data boat :cheer)) :to-be nil))
        (loop repeat 400
              until (cl-asciiquarium::creature-removep boat)
              do (world-advance world))
        (expect (cl-asciiquarium::creature-removep boat) :to-be t)
        (world-advance world)
        (expect (length (world-kind-creatures world :fisher)) :to-be 0)))))

(describe "fisher and gull glyphs"
  (it "draws only ASCII under --ascii, replacing the fishing line's box-drawing bar"
    (let ((*ascii* t))
      (with-seeded-random-state (5)
        (let* ((world (gull-world))
               (boat (cl-asciiquarium::make-fisher world))
               (parts (list boat (boat-data boat :line) (boat-data boat :hook)
                            (boat-data boat :cheer) (cl-asciiquarium::make-gull world 0))))
          (expect (find #\| (aref (creature-frames (boat-data boat :line)) 0)) :to-be #\|)
          (dolist (part parts)
            (loop for frame across (creature-frames part)
                  do (expect (every (lambda (c) (< (char-code c) 128)) frame) :to-be t)))))))
  (it "draws the fishing line with the box-drawing bar otherwise"
    (with-seeded-random-state (5)
      (let ((boat (cl-asciiquarium::make-fisher (gull-world))))
        (expect (aref (creature-frames (boat-data boat :line)) 0) :to-equal "│")
        (expect (ascii-text "│") :to-equal "|")))))

(describe "fisher colors"
  (it "repaints the boat, line, hook, and cheer in place when the theme changes"
    (let ((*color-mode* :truecolor))
      (with-seeded-random-state (5)
        (let* ((world (gull-world))
               (boat (cl-asciiquarium::make-fisher world))
               (parts (list boat (boat-data boat :line) (boat-data boat :hook)
                            (boat-data boat :cheer))))
          (dolist (part parts)
            (cl-asciiquarium::%add-world-creature world part))
          (let ((boat-frames (cl-asciiquarium::creature-%frames boat))
                (styles (mapcar #'cl-asciiquarium::creature-%style parts))
                (role-styles (cl-asciiquarium::creature-%role-styles boat)))
            (world-set-theme world :abyss)
            (with-soft-assertions
              (expect (mapcar #'cl-asciiquarium::creature-kind parts)
                      :to-equal '(:fisher :line :hook :cheer))
              (expect (every (lambda (part) (present-p world part)) parts) :to-be t)
              (expect (eq boat-frames (cl-asciiquarium::creature-%frames boat)) :to-be t)
              ;; The line, hook, and cheer now draw the runs a fisher built
              ;; under the new theme gets.
              (let ((fresh (cl-asciiquarium::make-fisher world)))
                (expect (every (lambda (key)
                                 (eq (cl-asciiquarium::creature-%frame-runs (boat-data boat key))
                                     (cl-asciiquarium::creature-%frame-runs (boat-data fresh key))))
                               '(:line :hook :cheer))
                        :to-be t))
              (expect (notany #'equalp styles (mapcar #'cl-asciiquarium::creature-%style parts))
                      :to-be t)
              (expect (equalp role-styles (cl-asciiquarium::creature-%role-styles boat))
                      :to-be nil))))))))

(describe "fisher parts and a theme change before they show"
  (it "draws the line, hook, and cheer in the theme current when each appears"
    (let ((*color-mode* :truecolor))
      (with-seeded-random-state (5)
        (let* ((world (gull-world))
               (boat (cl-asciiquarium::spawn-fisher-now world))
               (hook (boat-data boat :hook))
               (cheer (boat-data boat :cheer)))
          (world-advance world)
          (world-set-theme world :abyss)
          (advance-until-phase world boat :lower 400)
          (let ((fresh (cl-asciiquarium::make-fisher world)))
            (flet ((runs-match-p (key)
                     (eq (cl-asciiquarium::creature-%frame-runs (boat-data boat key))
                         (cl-asciiquarium::creature-%frame-runs (boat-data fresh key)))))
              (expect (list (runs-match-p :line) (runs-match-p :hook)) :to-equal '(t t))
              ;; The cheer was built at spawn under :coral and joins later.
              (parked-dart world (- (creature-x hook) 2) (+ (creature-y hook) 4))
              (world-set-theme world :moonlight)
              (loop repeat 200
                    until (present-p world cheer)
                    do (world-advance world))
              (expect (present-p world cheer) :to-be t)
              (let ((night (cl-asciiquarium::make-fisher world)))
                (expect (eq (cl-asciiquarium::creature-%frame-runs cheer)
                            (cl-asciiquarium::creature-%frame-runs (boat-data night :cheer)))
                        :to-be t)))))))))

(describe "fishing line sprite cache"
  (it "keeps only the line built for the latest screen height"
    (with-seeded-random-state (5)
      (let ((world (gull-world)))
        (dolist (height '(24 30 40))
          (world-resize world 80 height)
          (cl-asciiquarium::make-fisher world))
        (let ((boat (cl-asciiquarium::make-fisher world)))
          (expect (hash-table-count cl-asciiquarium::*fishing-line-prototypes*) :to-be 1)
          (expect cl-asciiquarium::*fishing-line-depth* :to-be (boat-data boat :max-depth)))))))

(describe "fisher part sprites"
  (it "shares one set of line, hook, and cheer runs between fishers of the same screen"
    (with-seeded-random-state (5)
      (let* ((world (gull-world))
             (first-boat (cl-asciiquarium::make-fisher world))
             (second-boat (cl-asciiquarium::make-fisher world)))
        (expect (every (lambda (key)
                         (eq (cl-asciiquarium::creature-%frame-runs (boat-data first-boat key))
                             (cl-asciiquarium::creature-%frame-runs (boat-data second-boat key))))
                       '(:line :hook :cheer))
                :to-be t)
        (expect (length (creature-frames (boat-data first-boat :line)))
                :to-be (boat-data first-boat :max-depth))))))

(describe "the fisher from either edge"
  (it "fishes past the rod tip, cheers over the fisher, and sails on, facing either way"
    (dolist (facing '(:left :right))
      (with-seeded-random-state (8)
        (let* ((world (gull-world))
               (boat (cl-asciiquarium::%add-world-creature
                      world (cl-asciiquarium::make-fisher world :facing facing)))
               (line (boat-data boat :line))
               (hook (boat-data boat :hook))
               (cheer (boat-data boat :cheer)))
          (advance-until-phase world boat :lower 400)
          (world-advance world)
          (expect (list facing (creature-x line))
                  :to-equal (list facing (if (eq facing :right)
                                             (+ (creature-x boat) (creature-dimensions boat))
                                             (1- (creature-x boat)))))
          (parked-dart world (- (creature-x hook) 2) (+ (creature-y hook) 4))
          (loop repeat 200
                until (present-p world cheer)
                do (world-advance world))
          (expect (list facing (<= (creature-x boat) (creature-x cheer)
                                   (+ (creature-x boat) (creature-dimensions boat) -1)))
                  :to-equal (list facing t))
          (let ((stop-x (creature-x boat)))
            (advance-until-phase world boat :leave 100)
            (dotimes (i 10) (world-advance world))
            (expect (list facing (if (eq facing :right)
                                     (> (creature-x boat) stop-x)
                                     (< (creature-x boat) stop-x)))
                    :to-equal (list facing t))))))))
