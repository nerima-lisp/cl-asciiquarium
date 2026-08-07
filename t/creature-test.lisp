(in-package #:cl-asciiquarium/test)

(describe "make-creature"
  (it "positions the entity"
    (let ((creature (make-creature :kind :test-thing :frames (list "hi") :x 2 :y 3 :dx 1 :dy 0)))
      (expect (creature-x creature) :to-be 2)
      (expect (creature-y creature) :to-be 3)))
  (it "stores the given kind and frames"
    (let ((creature (make-creature :kind :test-thing :frames (list "hi") :x 2 :y 3 :dx 1 :dy 0)))
      (expect (creature-kind creature) :to-be :test-thing)
      (expect (creature-art creature) :to-equal "hi")))
  (it "mirrors its art when facing left"
    (let ((creature (make-creature :kind :test-thing :frames (list "<>") :x 0 :y 0 :facing :left)))
      (expect (creature-art creature) :to-equal "<>")))
  (it "leaves right-facing art unmirrored"
    (let ((creature (make-creature :kind :test-thing :frames (list "<>") :x 0 :y 0 :facing :right)))
      (expect (creature-art creature) :to-equal "<>")))
  (it "signals asciiquarium-invalid-policy for a :policy other than :wrap, :despawn, or :none"
    (signals asciiquarium-invalid-policy
      (make-creature :world (tiny-world) :kind :test-thing :frames (list "x") :x 0 :y 0
                      :policy :bogus)))
  (it "accepts a single frame string directly, without wrapping it in a list"
    (let ((creature (make-creature :kind :test-thing :frames "solo" :x 0 :y 0)))
      (expect (creature-art creature) :to-equal "solo")))
  (it "defaults z to 0"
    (let ((creature (make-creature :kind :test-thing :frames (list "a") :x 0 :y 0)))
      (expect (creature-z creature) :to-be 0)))
  (it "defaults dx and dy to 0, so a tick leaves its position unchanged"
    (let ((creature (make-creature :kind :test-thing :frames (list "a") :x 5 :y 5)))
      (entity-tick (creature-entity creature) 10 10)
      (expect (creature-x creature) :to-be 5)))
  (it "defaults policy to :wrap"
    (let* ((world (tiny-world :width 10 :height 10))
           (creature (make-creature :world world :kind :test-thing :frames (list "a")
                                    :x 9 :y 0 :dx 1)))
      (entity-tick (creature-entity creature) (world-width world) (world-height world))
      (expect (creature-x creature) :to-be 0)))
  (it
    "uses cached mirrored art and dimensions for every animation frame"
    (let ((creature
          (make-creature
            :kind
            :test-thing
            :frames
            (list (format nil "ab~%c") "(<")
            :frame-period
            1
            :x
            0
            :y
            0
            :facing
            :left)))
      (expect (creature-art creature) :to-equal (format nil "ba~%c"))
      (expect
        (multiple-value-list (creature-dimensions creature))
        :to-equal
        (quote (2 2)))
      (creature-tick-animation creature)
      (expect (creature-art creature) :to-equal ">)")
      (expect
        (multiple-value-list (creature-dimensions creature))
        :to-equal
        (quote (2 1)))))
  (it
    "rebuilds derived caches and normalizes the frame index when frames are shortened"
    (let ((creature
          (make-creature
            :kind
            :test-thing
            :frames
            (list "a" "b")
            :frame-period
            1
            :x
            0
            :y
            0
            :facing
            :left)))
      (creature-tick-animation creature)
      (expect (creature-frame-index creature) :to-be 1)
      (setf (creature-frames creature) (vector (format nil "a<~%xyz")))
      (expect (creature-frame-index creature) :to-be 0)
      (expect (creature-art creature) :to-equal (format nil ">a~%zyx"))
      (expect
        (multiple-value-list (creature-dimensions creature))
        :to-equal
        (quote (3 2)))))
  (it
    "rejects replacing creature frames with an empty vector"
    (let ((creature (make-creature :kind :test-thing :frames (list "a") :x 0 :y 0)))
      (expect
        (lambda ()
          (setf (creature-frames creature) #()))
        :to-throw
        (quote simple-error)))))

(describe
  "creature-tick-animation"
  (it
    "advances frames every frame-period ticks, looping"
    (let ((creature
          (make-creature
            :kind
            :test-thing
            :frames
            (list "a" "b")
            :frame-period
            2
            :x
            0
            :y
            0)))
      (expect (creature-frame-index creature) :to-be 0)
      (creature-tick-animation creature)
      (expect (creature-frame-index creature) :to-be 0)
      (creature-tick-animation creature)
      (expect (creature-frame-index creature) :to-be 1)
      (creature-tick-animation creature)
      (creature-tick-animation creature)
      (expect (creature-frame-index creature) :to-be 0)))
  (it
    "is a no-op with a single frame"
    (let ((creature
          (make-creature :kind :test-thing :frames (list "a") :frame-period 1 :x 0 :y 0)))
      (dotimes (i 5)
        (creature-tick-animation creature))
      (expect (creature-frame-index creature) :to-be 0)))
  (it
    "does not animate multiple frames without a frame period"
    (let ((creature (make-creature :kind :test-thing :frames (list "a" "b") :x 0 :y 0)))
      (dotimes (i 5)
        (creature-tick-animation creature))
      (expect (creature-frame-index creature) :to-be 0)))
  (it
    "normalizes an out-of-range frame index on advance"
    (let ((creature
          (make-creature :kind :test-thing :frames (list "a" "b") :frame-period 1 :x 0 :y 0)))
      (setf (creature-frame-index creature) 2)
      (creature-tick-animation creature)
      (expect (creature-frame-index creature) :to-be 1)))
  (it
    "normalizes a negative frame index on advance"
    (let ((creature
          (make-creature :kind :test-thing :frames (list "a" "b") :frame-period 1 :x 0 :y 0)))
      (setf (creature-frame-index creature) -1)
      (creature-tick-animation creature)
      (expect (creature-frame-index creature) :to-be 0))))

(describe
  "creature-bounds and creatures-overlap-p"
  (it
    "reports overlapping bounding boxes"
    (let ((a (make-creature :kind :a :frames (list "abc") :x 0 :y 0))
          (b (make-creature :kind :b :frames (list "abc") :x 1 :y 0)))
      (expect (creatures-overlap-p a b) :to-be-truthy)))
  (it
    "reports non-overlapping bounding boxes"
    (let ((a (make-creature :kind :a :frames (list "abc") :x 0 :y 0))
          (b (make-creature :kind :b :frames (list "abc") :x 20 :y 20)))
      (expect (creatures-overlap-p a b) :to-be-falsy))))

(describe "creature off-bounds lifecycle"
  (it-each (("right" 9 0 1 0 0 0)
            ("left" 0 0 -1 0 8 0)
            ("bottom" 0 9 0 1 0 0)
            ("top" 0 0 0 -1 0 9)
            ;; [#wrap-diagonal] Both edges violated the same tick used to wrap
            ;; only the x axis: WRAP-CREATURE re-derived the edge from
            ;; position via a COND that stopped at its first true branch
            ;; instead of using the EDGE argument ENTITY-TICK already passed
            ;; it once per violated edge. Fixed by dispatching on EDGE
            ;; directly; this case pins a corner exit wrapping both axes.
            ("bottom-right corner, both axes at once" 9 9 1 1 0 0))
      ":wrap policy repositions a creature that exits the ~A edge back inside the world"
      (label x y dx dy expected-x expected-y)
    (let* ((world (tiny-world :width 10 :height 10))
           (creature (make-creature :world world :kind :thing :frames (list "ab")
                                    :x x :y y :dx dx :dy dy :policy :wrap)))
      (entity-tick (creature-entity creature) (world-width world) (world-height world))
      (expect (creature-x creature) :to-be expected-x)
      (expect (creature-y creature) :to-be expected-y)))
  (it-each (("right" 9 0 1 0)
            ("left" 0 0 -1 0)
            ("bottom" 0 9 0 1)
            ("top" 0 0 0 -1))
      ":despawn policy marks a creature removep once it exits the ~A edge its own velocity carries it toward"
      (label x y dx dy)
    (let* ((world (tiny-world :width 10 :height 10))
           (creature (make-creature :world world :kind :thing :frames (list "ab")
                                    :x x :y y :dx dx :dy dy :policy :despawn)))
      (expect (creature-removep creature) :to-be-falsy)
      (entity-tick (creature-entity creature) (world-width world) (world-height world))
      (expect (creature-removep creature) :to-be-truthy)))
  ;; A :DESPAWN creature spawned already past the edge it is approaching (as
  ;; every off-screen crossing factory does) must NOT despawn on that first
  ;; tick -- see EXIT-EDGE-IN-TRAVEL-DIRECTION-P and the architecture doc's
  ;; "Off-bounds policy" section.
  (it ":despawn policy does not remove a creature still approaching from its spawn edge"
    (let* ((world (tiny-world :width 10 :height 10))
           (creature (make-creature :world world :kind :thing :frames (list "ab")
                                    :x -5 :y 0 :dx 1 :policy :despawn)))
      (entity-tick (creature-entity creature) (world-width world) (world-height world))
      (expect (creature-removep creature) :to-be-falsy)))
  (it ":none policy installs no callback, leaving a creature free to sit at the edge"
    (let* ((world (tiny-world :width 10 :height 10))
           (creature
          (make-creature
            :world
            world
            :kind
            :thing
            :frames
            (list "a")
            :x
            0
            :y
            0
            :dx
            0
            :dy
            0
            :policy
            :none)))
      (entity-tick
        (creature-entity creature)
        (world-width world)
        (world-height world))
      (expect (creature-removep creature) :to-be-falsy)
      (expect (creature-x creature) :to-be 0))))

(describe "solid-style and *monochrome*"
  ;; SOLID-STYLE and *MONOCHROME* are deliberately not part of the package's
  ;; exported surface (see package.lisp's comment on SOLID-STYLE): every
  ;; creature factory calls it internally, and *MONOCHROME* is bound once, by
  ;; RUN (app.lisp), from the --monochrome CLI flag. Accessed here the same
  ;; way t/app-test.lisp reaches READ-AVAILABLE-STRING: package-qualified,
  ;; since this tests an internal detail directly rather than through a public
  ;; entry point.
  (it "returns a colored style by default"
    (expect (cl-asciiquarium::solid-style :red) :to-be-truthy))
  (it "returns nil while *monochrome* is bound true"
    (let ((cl-asciiquarium::*monochrome* t))
      (expect (cl-asciiquarium::solid-style :red) :to-be-falsy)))
  (it "leaves a fish with no style while *monochrome* is bound true"
    (let ((cl-asciiquarium::*monochrome* t))
      (let* ((world (tiny-world))
             (fish (make-fish world :species :dart)))
        (expect (creature-style fish) :to-be-falsy)))))

(describe
  "creature ownership boundaries"
  (it
    "preserves zero-width bubble placement and single-float velocity"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (fish (make-creature :world world :kind :fish :frames (list "") :x 5 :y 5))
           (bubble (make-bubble world fish)))
      (expect (creature-x bubble) :to-be 5)
      (expect (creature-y bubble) :to-be 4)
      (expect (typep (entity-dy (creature-entity bubble)) 'single-float) :to-be-truthy)))
  (it
    "copies frame input, setter values, and getter results"
    (let* ((input (vector (copy-seq "a")))
           (creature (make-creature :kind :test :frames input :x 0 :y 0)))
      (setf (char (aref input 0) 0) #\A)
      (expect (creature-art creature) :to-equal "a")
      (let ((replacement (vector (copy-seq "b"))))
        (setf (creature-frames creature) replacement)
        (setf (char (aref replacement 0) 0) #\B)
        (expect (creature-art creature) :to-equal "b"))
      (let ((escaped (creature-frames creature)))
        (setf (char (aref escaped 0) 0) #\X)
        (expect (creature-art creature) :to-equal "b"))))
  (it
    "copies styles at public boundaries"
    (let* ((style (make-style (style-fg (named-color :bright-white))))
           (creature (make-creature :kind :test :frames (list "x") :style style :x 0 :y 0))
           (before (make-screen 1 1))
           (after (make-screen 1 1)))
      (cl-asciiquarium::creature-blit before creature)
      (setf (second (first style)) (named-color :bright-green))
      (setf (second (first (creature-style creature))) (named-color :bright-green))
      (cl-asciiquarium::creature-blit after creature)
      (expect (cl-tty-kit:cell-style (screen-cell after 0 0))
              :to-equal (cl-tty-kit:cell-style (screen-cell before 0 0))))))

(describe
  "left-facing creature-art isolation"
  (it
    "returns a fresh mirrored string for each access"
    (let* ((creature
          (make-creature :kind :test :frames (list "a<") :x 0 :y 0 :facing :left))
           (art (creature-art creature)))
      (setf (char art 0) #\X)
      (expect (creature-art creature) :to-equal ">a")))
  (it
    "isolates destructive mirrored bubble art mutation from shared caches"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (fish (make-creature :world world :kind :fish :frames (list "F") :x 5 :y 5))
           (first (make-bubble world fish))
           (second (make-bubble world fish)))
      (setf (creature-facing first) :left
            (creature-facing second) :left)
      (let ((art (creature-art first)))
        (setf (char art 0) #\X))
      (expect (creature-art first) :to-equal ".")
      (expect (creature-art second) :to-equal ".")
      (expect
        (aref
          (cl-asciiquarium::creature-%mirrored-frames
            cl-asciiquarium::+bubble-sprite-prototype+)
          0)
        :to-equal
        ".")
      (let ((future (make-bubble world fish)))
        (setf (creature-facing future) :left)
        (expect (creature-art future) :to-equal ".")))))
