;;;; t/gull-test.lisp -- gulls (src/art-gull.lisp, src/update-gull.lisp):
;;;; flying the sky, diving for a fish near the surface, leaving at night.
(in-package #:cl-asciiquarium/test)

(defun gull-world (&key (theme :coral))
  "An 80x24 world with no fish, no gull, no shark, no HUD, and no automatic
guest, so each test adds exactly the gulls and fish it watches."
  (let ((world (make-world :width 80 :height 24 :fish-count 0 :shark-enabled-p nil
                           :hud-visible-p nil :theme theme)))
    (setf (cl-asciiquarium::world-guest-cooldown world) most-positive-fixnum)
    (remove-gulls world)
    world))

(defun world-kind-creatures (world kind)
  (remove kind (cl-asciiquarium::world-%creatures world)
          :key #'cl-asciiquarium::creature-kind :test-not #'eq))

(defun gull-data (gull key)
  (getf (cl-asciiquarium::creature-data gull) key))

(defun parked-gull (world x)
  "A slot-0 gull hovering at column X, already in WORLD."
  (let ((gull (cl-asciiquarium::make-gull world 0)))
    (setf (entity-x (cl-asciiquarium::creature-entity gull)) x
          (entity-dx (cl-asciiquarium::creature-entity gull)) 0
          (getf (cl-asciiquarium::creature-data gull) :cruise-dx) 0)
    (cl-asciiquarium::%add-world-creature world gull)
    gull))

(defun parked-dart (world x y)
  (let ((fish (make-fish world :species :dart :x x :y y :dx 0)))
    (cl-asciiquarium::%add-world-creature world fish)
    fish))

(describe "gulls in the sky"
  (it "populate-gulls adds two gulls that fly in the sky rows, and no more on a second call"
    (with-seeded-random-state (3)
      (let ((world (gull-world)))
        (cl-asciiquarium::populate-gulls world)
        (cl-asciiquarium::populate-gulls world)
        (let* ((gulls (world-kind-creatures world :gull))
               (start (mapcar #'creature-x gulls)))
          (expect (length gulls) :to-be 2)
          (dotimes (i 20) (world-advance world))
          (with-soft-assertions
            (dolist (gull gulls)
              (expect (< (creature-y gull) (world-waterline-row world)) :to-be t))
            (expect (notany #'= start (mapcar #'creature-x gulls)) :to-be t)
            (expect (length (world-kind-creatures world :gull)) :to-be 2))))))
  (it "adds two gulls to an 80x24 world, and none where the sky has fewer than three rows"
    (let ((full (make-world :width 80 :height 24 :fish-count 0 :theme :coral))
          (low (make-world :width 40 :height 10 :fish-count 0 :theme :coral)))
      (cl-asciiquarium::populate-gulls full)
      (cl-asciiquarium::populate-gulls low)
      (expect (list (world-waterline-row full) (world-waterline-row low)) :to-equal '(5 2))
      (expect (length (world-kind-creatures full :gull)) :to-be 2)
      (expect (length (world-kind-creatures low :gull)) :to-be 0)))
  (it "builds gulls without drawing a random number"
    (let ((world (gull-world))
          (state (make-random-state *random-state*)))
      (cl-asciiquarium::populate-gulls world)
      (expect (random 1000000) :to-be (random 1000000 state)))))

(describe "a gull's dive"
  (it "catches a fish near the surface, lifts it to the sky, and waits 700 ticks"
    (with-seeded-random-state (11)
      (let* ((world (gull-world))
             (gull (parked-gull world 30))
             (fish (parked-dart world 29 (+ (world-waterline-row world) 3)))
             (fish-y (creature-y fish)))
        (loop repeat 600
              until (eq (cl-asciiquarium::creature-kind fish) :caught-fish)
              do (world-advance world))
        (expect (cl-asciiquarium::creature-kind fish) :to-be :caught-fish)
        (expect (eq (getf (cl-asciiquarium::creature-data fish) :captor) gull) :to-be t)
        (let ((catch-tick (world-tick world))
              (lowest-fish-y fish-y)
              (highest-fish-y fish-y))
          (loop repeat 50
                until (eq (gull-data gull :phase) :cruise)
                do (world-advance world)
                   (unless (cl-asciiquarium::creature-removep fish)
                     (setf lowest-fish-y (min lowest-fish-y (creature-y fish))
                           highest-fish-y (max highest-fish-y (creature-y fish)))))
          (with-soft-assertions
            (expect (gull-data gull :phase) :to-be :cruise)
            (expect (creature-y gull) :to-be (cl-asciiquarium::gull-sky-row world 0))
            (expect (< lowest-fish-y (world-waterline-row world)) :to-be t)
            (expect (cl-asciiquarium::creature-removep fish) :to-be t)
            (expect (gull-data gull :threat) :to-be nil)
            (expect (>= (gull-data gull :dive-ready-at) (+ catch-tick 700)) :to-be t))
          (let ((next (parked-dart world 29 (+ (world-waterline-row world) 3)))
                (dove-early nil))
            (loop while (< (world-tick world) (+ catch-tick 700))
                  do (world-advance world)
                     (when (eq (gull-data gull :phase) :dive)
                       (setf dove-early t)))
            (expect dove-early :to-be nil)
            ;; The same setup does dive once the cooldown is over, so the
            ;; quiet stretch above is the cooldown, not a missed target.
            (loop repeat 600
                  until (eq (gull-data gull :phase) :dive)
                  do (world-advance world))
            (expect (gull-data gull :phase) :to-be :dive)
            (expect (cl-asciiquarium::alive-fish-p next) :to-be t))))))
  (it "carries the dive threat only while diving"
    (with-seeded-random-state (11)
      (let* ((world (gull-world))
             (gull (parked-gull world 30)))
        (parked-dart world 29 (+ (world-waterline-row world) 3))
        (expect (gull-data gull :threat) :to-be nil)
        (loop repeat 600
              until (eq (gull-data gull :phase) :dive)
              do (world-advance world))
        (expect (gull-data gull :threat) :to-be cl-asciiquarium::+gull-threat+))))
  (it "does not dive at a fish deeper than six rows below the waterline"
    (with-seeded-random-state (11)
      (let* ((world (gull-world))
             (gull (parked-gull world 30)))
        (parked-dart world 29 (+ (world-waterline-row world) 7))
        (loop repeat 600
              until (eq (gull-data gull :phase) :dive)
              do (world-advance world))
        (expect (gull-data gull :phase) :to-be :cruise))))
  (it "rises empty from the bottom of its dive when the fish is gone"
    (let* ((world (gull-world))
           (gull (parked-gull world 30))
           (fish (parked-dart world 29 (+ (world-waterline-row world) 3))))
      (setf (getf (cl-asciiquarium::creature-data gull) :phase) :dive
            (getf (cl-asciiquarium::creature-data gull) :target) fish
            (entity-dy (cl-asciiquarium::creature-entity gull)) 1)
      (setf (cl-asciiquarium::creature-removep fish) t)
      (world-advance world)
      (expect (gull-data gull :phase) :to-be :rise)
      (loop repeat 20
            until (eq (gull-data gull :phase) :cruise)
            do (world-advance world))
      (expect (list (gull-data gull :phase) (gull-data gull :dive-ready-at))
              :to-equal '(:cruise 0)))))

;; Puts GULL in its dive one row above FISH-Y, so its next move lands on it.
(defun diving-gull (world x fish-y target)
  (let ((gull (parked-gull world x)))
    (setf (entity-y (cl-asciiquarium::creature-entity gull)) (1- fish-y)
          (entity-dy (cl-asciiquarium::creature-entity gull)) 1
          (getf (cl-asciiquarium::creature-data gull) :phase) :dive
          (getf (cl-asciiquarium::creature-data gull) :target) target)
    (cl-asciiquarium::arm-threat world gull cl-asciiquarium::+gull-threat+)
    gull))

(describe "a gull's catch"
  (it "takes exactly one of two fish under it"
    (let* ((world (gull-world))
           (y (+ (world-waterline-row world) 3))
           (first-fish (parked-dart world 29 y))
           (second-fish (parked-dart world 29 y)))
      (diving-gull world 30 y first-fish)
      (world-advance world)
      (expect (count :caught-fish (list first-fish second-fish)
                     :key #'cl-asciiquarium::creature-kind)
              :to-be 1)
      (expect (count-if #'cl-asciiquarium::alive-fish-p (list first-fish second-fish))
              :to-be 1))))

(defun gull-with-catch (world)
  "Let a diving gull catch a dart in WORLD and return (VALUES GULL FISH). The
fish is added after the gull, so it sits ahead of the gull in the creature
list and ticks before its captor: the order in which a captor marked during
its own tick leaves the fish behind."
  (let* ((y (+ (world-waterline-row world) 3))
         (fish (make-fish world :species :dart :x 29 :y y :dx 0))
         (gull (diving-gull world 30 y fish)))
    (cl-asciiquarium::%add-world-creature world fish)
    (world-advance world)
    (expect (cl-asciiquarium::creature-kind fish) :to-be :caught-fish)
    (values gull fish)))

(defun press-keys (world keys)
  (dolist (event (decode-input keys))
    (world-apply-key-event world event)))

(defun expect-gone (world &rest creatures)
  ;; A boolean, not the MEMBER tail: printing a creature in a failure report
  ;; walks the whole world through its references.
  (dolist (creature creatures)
    (expect (null (member creature (cl-asciiquarium::world-%creatures world))) :to-be t)))

(describe "a gull leaving with its catch"
  (it "takes the caught fish off the screen on the tick it leaves at night"
    (let ((world (gull-world)))
      (multiple-value-bind (gull fish) (gull-with-catch world)
        (world-set-theme world :moonlight)
        (world-advance world)
        (expect-gone world gull fish))))
  (it "takes the caught fish off the screen when night falls while paused"
    (let ((world (gull-world :theme :abyss)))
      (multiple-value-bind (gull fish) (gull-with-catch world)
        (press-keys world " n")
        (world-advance world)
        (expect (world-paused-p world) :to-be t)
        (expect (world-theme world) :to-be :moonlight)
        (expect-gone world gull fish))))
  (it "takes the caught fish off the screen when the r key follows nightfall while paused"
    (let ((world (gull-world :theme :abyss)))
      (multiple-value-bind (gull fish) (gull-with-catch world)
        (press-keys world " nr")
        (world-advance world)
        (expect (world-paused-p world) :to-be t)
        (expect-gone world gull fish))))
  (it "takes the caught fish off the screen when the - key follows nightfall while paused"
    (let ((world (gull-world :theme :abyss)))
      (multiple-value-bind (gull fish) (gull-with-catch world)
        (let ((other (parked-dart world 60 (+ (world-waterline-row world) 8))))
          (setf (cl-asciiquarium::world-fish-count world) 1)
          (press-keys world " n-")
          (world-advance world)
          (expect (world-paused-p world) :to-be t)
          (expect (cl-asciiquarium::world-fish-count world) :to-be 0)
          (expect-gone world gull fish other)))))
  (it "lets the r key take the caught fish by day, leaving the gull to cruise on"
    (let ((world (gull-world)))
      (multiple-value-bind (gull fish) (gull-with-catch world)
        (press-keys world "r")
        (world-advance world)
        (expect-gone world fish)
        (expect (null (member gull (cl-asciiquarium::world-%creatures world))) :to-be nil)
        (loop repeat 20
              until (eq (gull-data gull :phase) :cruise)
              do (world-advance world))
        (expect (gull-data gull :phase) :to-be :cruise)))))

(describe "gulls and the screen size"
  (it "leave a sky shrunk below three rows, and come back when it grows again"
    (let ((world (gull-world)))
      (cl-asciiquarium::populate-gulls world)
      (world-resize world 80 10)
      (world-advance world)
      (expect (length (world-kind-creatures world :gull)) :to-be 0)
      (world-resize world 80 24)
      (expect (length (world-kind-creatures world :gull)) :to-be 2)))
  (it "keep cruising inside the sky after it shrinks"
    (let ((world (gull-world)))
      (cl-asciiquarium::populate-gulls world)
      (world-resize world 80 16)
      (world-advance world)
      (expect (>= (world-waterline-row world) cl-asciiquarium::+gull-min-sky-rows+) :to-be t)
      (dolist (gull (world-kind-creatures world :gull))
        (expect (< (creature-y gull) (world-waterline-row world)) :to-be t)))))

(describe "gulls at night"
  (it "leave when night falls while the aquarium is paused"
    (let ((world (gull-world)))
      (cl-asciiquarium::populate-gulls world)
      (setf (world-paused-p world) t)
      (cl-asciiquarium::world-change-daypart world :moonlight)
      (world-advance world)
      (expect (length (world-kind-creatures world :gull)) :to-be 0)))
  (it "catch nothing on the tick they leave for the night"
    (let* ((world (gull-world))
           (y (+ (world-waterline-row world) 3))
           (fish (parked-dart world 29 y)))
      (diving-gull world 30 y fish)
      (world-set-theme world :moonlight)
      (world-advance world)
      (expect (cl-asciiquarium::creature-kind fish) :to-be :fish)
      (expect (length (world-kind-creatures world :gull)) :to-be 0)))
  (it "leave when night falls, and populate-gulls adds none at night"
    (let ((world (gull-world)))
      (cl-asciiquarium::populate-gulls world)
      (world-set-theme world :moonlight)
      (world-advance world)
      (expect (length (world-kind-creatures world :gull)) :to-be 0)
      (cl-asciiquarium::populate-gulls world)
      (expect (length (world-kind-creatures world :gull)) :to-be 0)))
  (it "are not added to a world that starts at night"
    (let ((world (gull-world :theme :moonlight)))
      (cl-asciiquarium::populate-gulls world)
      (expect (length (world-kind-creatures world :gull)) :to-be 0))))

(describe "gull colors"
  (it "repaints gulls in place when the theme changes, adopting the new theme's shared runs"
    (let* ((*color-mode* :truecolor)
           (world (gull-world)))
      (cl-asciiquarium::populate-gulls world)
      (let* ((gulls (world-kind-creatures world :gull))
             (positions (mapcar (lambda (gull) (list (creature-x gull) (creature-y gull)))
                                gulls))
             (old-runs (mapcar #'cl-asciiquarium::creature-%frame-runs gulls))
             (colors (mapcar #'cl-asciiquarium::creature-%role-styles gulls)))
        (world-set-theme world :abyss)
        (with-soft-assertions
          (expect (every #'eq (world-kind-creatures world :gull) gulls) :to-be t)
          (expect (length (world-kind-creatures world :gull)) :to-be (length gulls))
          (expect (mapcar (lambda (gull) (list (creature-x gull) (creature-y gull))) gulls)
                  :to-equal positions)
          (expect (notany #'eq old-runs (mapcar #'cl-asciiquarium::creature-%frame-runs gulls))
                  :to-be t)
          (expect (every (lambda (gull)
                           (eq (cl-asciiquarium::creature-%frame-runs gull)
                               (cl-asciiquarium::creature-%frame-runs
                                (cl-asciiquarium::make-gull world 0))))
                         gulls)
                  :to-be t)
          (expect (notany #'equalp colors
                          (mapcar #'cl-asciiquarium::creature-%role-styles gulls))
                  :to-be t))))))
