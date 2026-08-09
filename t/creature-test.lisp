(in-package #:cl-asciiquarium/test)

(describe "make-creature"
  (it "positions the entity"
    (let ((creature (make-creature :kind :test-thing :frames (list "hi") :x 2 :y 3 :dx 1 :dy 0)))
      (expect (creature-x creature) :to-be 2)
      (expect (creature-y creature) :to-be 3)))
  (it "stores the given kind and frames"
    (let ((creature (make-creature :kind :test-thing :frames (list "hi") :x 2 :y 3 :dx 1 :dy 0)))
      (expect (cl-asciiquarium::creature-kind creature) :to-be :test-thing)
      (expect (creature-art creature) :to-equal "hi")))
  ;; "<>" is a fixed point of MIRROR-SPRITE-TEXT -- reversing it swaps the two
  ;; glyphs back into place -- so it cannot distinguish mirroring from a plain
  ;; copy. "a<" reverses to "<a" and then swaps the directional glyph, so only
  ;; real mirroring yields ">a".
  (it "mirrors its art when facing left"
    (let ((creature (make-creature :kind :test-thing :frames (list "a<") :x 0 :y 0 :facing :left)))
      (expect (creature-art creature) :to-equal ">a")))
  (it "leaves right-facing art unmirrored"
    (let ((creature (make-creature :kind :test-thing :frames (list "a<") :x 0 :y 0 :facing :right)))
      (expect (creature-art creature) :to-equal "a<")))
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
      (entity-tick (cl-asciiquarium::creature-entity creature) 10 10)
      (expect (creature-x creature) :to-be 5)))
  (it "defaults policy to :wrap"
    (let* ((world (tiny-world :width 10 :height 10))
           (creature (make-creature :world world :kind :test-thing :frames (list "a")
                                    :x 9 :y 0 :dx 1)))
      (entity-tick (cl-asciiquarium::creature-entity creature) (world-width world) (world-height world))
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
      (expect (cl-asciiquarium::creature-frame-index creature) :to-be 1)
      (setf (creature-frames creature) (vector (format nil "a<~%xyz")))
      (expect (cl-asciiquarium::creature-frame-index creature) :to-be 0)
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
      (expect (cl-asciiquarium::creature-frame-index creature) :to-be 0)
      (creature-tick-animation creature)
      (expect (cl-asciiquarium::creature-frame-index creature) :to-be 0)
      (creature-tick-animation creature)
      (expect (cl-asciiquarium::creature-frame-index creature) :to-be 1)
      (creature-tick-animation creature)
      (creature-tick-animation creature)
      (expect (cl-asciiquarium::creature-frame-index creature) :to-be 0)))
  (it
    "is a no-op with a single frame"
    (let ((creature
          (make-creature :kind :test-thing :frames (list "a") :frame-period 1 :x 0 :y 0)))
      (dotimes (i 5)
        (creature-tick-animation creature))
      (expect (cl-asciiquarium::creature-frame-index creature) :to-be 0)))
  (it
    "normalizes an out-of-range frame index on advance"
    (let ((creature
          (make-creature :kind :test-thing :frames (list "a" "b") :frame-period 1 :x 0 :y 0)))
      (setf (cl-asciiquarium::creature-frame-index creature) 2)
      (creature-tick-animation creature)
      (expect (cl-asciiquarium::creature-frame-index creature) :to-be 1))))

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
      (entity-tick (cl-asciiquarium::creature-entity creature) (world-width world) (world-height world))
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
      (expect (cl-asciiquarium::creature-removep creature) :to-be-falsy)
      (entity-tick (cl-asciiquarium::creature-entity creature) (world-width world) (world-height world))
      (expect (cl-asciiquarium::creature-removep creature) :to-be-truthy)))
  ;; A :DESPAWN creature spawned already past the edge it is approaching (as
  ;; every off-screen crossing factory does) must NOT despawn on that first
  ;; tick -- see EXIT-EDGE-IN-TRAVEL-DIRECTION-P and the architecture doc's
  ;; "Off-bounds policy" section.
  (it ":despawn policy does not remove a creature still approaching from its spawn edge"
    (let* ((world (tiny-world :width 10 :height 10))
           (creature (make-creature :world world :kind :thing :frames (list "ab")
                                    :x -5 :y 0 :dx 1 :policy :despawn)))
      (entity-tick (cl-asciiquarium::creature-entity creature) (world-width world) (world-height world))
      (expect (cl-asciiquarium::creature-removep creature) :to-be-falsy)))
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
        (cl-asciiquarium::creature-entity creature)
        (world-width world)
        (world-height world))
      (expect (cl-asciiquarium::creature-removep creature) :to-be-falsy)
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
  "make-bubble prepared sprite sharing"
  (it
    "uses a single-float vertical velocity"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (fish (make-creature :world world :kind :fish :frames (list "F") :x 5 :y 5))
           (bubble (make-bubble world fish)))
      (expect (typep (entity-dy (cl-asciiquarium::creature-entity bubble)) 'single-float) :to-be-truthy)))
  (it
    "shares prototype sprite data until public access materializes private mutable values"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (fish (make-creature :world world :kind :fish :frames (list "F") :x 5 :y 5))
           (prototype cl-asciiquarium::+bubble-sprite-prototype+)
           (first (make-bubble world fish))
           (art-accessed (make-bubble world fish))
           (untouched (make-bubble world fish)))
      (expect
        (cl-asciiquarium::creature-%frames first)
        :to-be
        (cl-asciiquarium::creature-%frames prototype))
      (expect
        (cl-asciiquarium::creature-%mirrored-frames first)
        :to-be
        (cl-asciiquarium::creature-%mirrored-frames prototype))
      (expect (cl-asciiquarium::creature-%frames-shared-p first) :to-be-truthy)
      (expect (cl-asciiquarium::creature-%style-shared-p first) :to-be-truthy)
      (expect
        (cl-asciiquarium::creature-%prepared-style first)
        :to-be
        (cl-asciiquarium::creature-%prepared-style prototype))
      (let ((frames (creature-frames first)))
        (expect frames :not :to-be (cl-asciiquarium::creature-%frames prototype))
        (expect
          (aref frames 0)
          :not
          :to-be
          (aref (cl-asciiquarium::creature-%frames prototype) 0))
        (expect (cl-asciiquarium::creature-%frames-shared-p first) :to-be-falsy))
      (creature-art art-accessed)
      (expect
        (cl-asciiquarium::creature-%frames art-accessed)
        :not
        :to-be
        (cl-asciiquarium::creature-%frames prototype))
      (expect
        (aref (cl-asciiquarium::creature-%frames art-accessed) 0)
        :not
        :to-be
        (aref (cl-asciiquarium::creature-%frames prototype) 0))
      (expect (cl-asciiquarium::creature-%frames-shared-p art-accessed) :to-be-falsy)
      (expect
        (cl-asciiquarium::creature-%frames untouched)
        :to-be
        (cl-asciiquarium::creature-%frames prototype))
      (expect (cl-asciiquarium::creature-entity first) :not :to-be (cl-asciiquarium::creature-entity untouched))))
  (it
    "detaches cache slots and clears sharing flags when public setters are used"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (fish (make-creature :world world :kind :fish :frames (list "F") :x 5 :y 5))
           (changed (make-bubble world fish))
           (unchanged (make-bubble world fish)))
      (expect (cl-asciiquarium::creature-%frames-shared-p changed) :to-be-truthy)
      (expect (cl-asciiquarium::creature-%style-shared-p changed) :to-be-truthy)
      (setf (creature-frames changed) (list "X")
            (creature-style changed) (make-style (style-fg (named-color :bright-green))))
      (expect (cl-asciiquarium::creature-%frames-shared-p changed) :to-be-falsy)
      (expect (cl-asciiquarium::creature-%style-shared-p changed) :to-be-falsy)
      (expect (creature-art changed) :to-equal "X")
      (expect (creature-art unchanged) :to-equal ".")
      (expect (creature-style unchanged) :to-equal cl-asciiquarium::+bubble-style+)
      (expect (creature-style unchanged) :not :to-be cl-asciiquarium::+bubble-style+)
      (expect
        (cl-asciiquarium::creature-%frame-runs changed)
        :not
        :to-be
        (cl-asciiquarium::creature-%frame-runs unchanged))))
  (it
    "selects a shared monochrome prototype without a colored style"
    (let ((cl-asciiquarium::*monochrome* t))
      (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
             (fish (make-creature :world world :kind :fish :frames (list "F") :x 5 :y 5))
             (bubble (make-bubble world fish))
             (prototype cl-asciiquarium::+monochrome-bubble-sprite-prototype+))
        (expect (cl-asciiquarium::creature-%style-shared-p bubble) :to-be-truthy)
        (expect
          (cl-asciiquarium::creature-%prepared-style bubble)
          :to-be
          (cl-asciiquarium::creature-%prepared-style prototype))
        (expect (creature-style bubble) :to-be-falsy))))
  (it
    "materializes a shared prototype style before exposing it for mutation"
    (let* ((prototype
             (make-creature
               :kind :prototype :frames (list "x")
               :style (make-style (style-fg (named-color :bright-white)))
               :%trusted-frames-p t :%trusted-style-p t :x 0 :y 0))
           (creature
             (make-creature :kind :child :%sprite-prototype prototype :x 0 :y 0))
           (prototype-style (cl-asciiquarium::creature-%style prototype))
           (expected-prototype-style (copy-tree prototype-style))
           (style (creature-style creature)))
      (expect (cl-asciiquarium::creature-%style-shared-p creature) :to-be-falsy)
      (expect style :not :to-be prototype-style)
      (setf (second (first style)) (named-color :bright-green))
      (expect
        (cl-asciiquarium::creature-%style prototype)
        :to-equal
        expected-prototype-style)))
  (it
    "rebuilds caches after direct frame vector mutation"
    (let* ((creature
          (make-creature
            :kind
            :test-thing
            :frames
            (list "a")
            :style
            (make-style (style-fg (named-color :bright-white)))
            :x
            0
            :y
            0))
           (screen (make-screen 4 1)))
      (setf (aref (creature-frames creature) 0) "xyz")
      (expect (creature-art creature) :to-equal "xyz")
      (expect
        (multiple-value-list (creature-dimensions creature))
        :to-equal
        (quote (3 1)))
      (cl-asciiquarium::creature-blit screen creature)
      (expect (cell-char (screen-cell screen 2 0)) :to-be #\z)))
  (it
    "rebuilds prepared cells after direct nested style mutation"
    (let* ((style (make-style (style-fg (named-color :bright-white))))
           (creature
          (make-creature :kind :test-thing :frames (list "x") :style style :x 0 :y 0))
           (before (make-screen 1 1))
           (after (make-screen 1 1)))
      (cl-asciiquarium::creature-blit before creature)
      (setf (second (first (creature-style creature))) (named-color :bright-green))
      (cl-asciiquarium::creature-blit after creature)
      (expect
        (cl-tty-kit:cell-style (screen-cell after 0 0))
        :not
        :to-equal
        (cl-tty-kit:cell-style (screen-cell before 0 0)))))
  (it
    "isolates direct bubble style mutation from siblings and future bubbles"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (fish (make-creature :world world :kind :fish :frames (list "F") :x 5 :y 5))
           (first (make-bubble world fish))
           (second (make-bubble world fish))
           (canonical (copy-tree cl-asciiquarium::+bubble-style+)))
      (setf (second (first (creature-style first))) (named-color :bright-green))
      (expect (creature-style first) :not :to-equal (creature-style second))
      (expect (creature-style second) :to-equal canonical)
      (expect cl-asciiquarium::+bubble-style+ :to-equal canonical)
      (let ((future (make-bubble world fish)))
        (expect (creature-style future) :to-equal canonical)
        (expect (creature-style future) :not :to-be (creature-style first)))))
  (it
    "rebuilds caches after a case-only direct frame string mutation"
    (let* ((creature
          (make-creature
            :kind
            :test-thing
            :frames
            (list "a")
            :style
            (make-style (style-fg (named-color :bright-white)))
            :x
            0
            :y
            0))
           (screen (make-screen 1 1)))
      (setf (char (aref (creature-frames creature) 0) 0) #\A)
      (expect (creature-art creature) :to-equal "A")
      (cl-asciiquarium::creature-blit screen creature)
      (expect (cell-char (screen-cell screen 0 0)) :to-be #\A)))
  (it
    "isolates destructive bubble frame mutation from siblings and future bubbles"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (fish (make-creature :world world :kind :fish :frames (list "F") :x 5 :y 5))
           (first (make-bubble world fish))
           (second (make-bubble world fish)))
      (setf (char (aref (creature-frames first) 0) 0) #\X)
      (expect (creature-art first) :to-equal "X")
      (expect (creature-art second) :to-equal ".")
      (expect (first cl-asciiquarium::+bubble-art-frames+) :to-equal ".")
      (let ((future (make-bubble world fish)))
        (expect (creature-art future) :to-equal "."))))
  (it
    "isolates the bubble prototype from destructive constant frame mutation"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (fish (make-creature :world world :kind :fish :frames (list "F") :x 5 :y 5))
           (existing (make-bubble world fish))
           (constant-frame (first cl-asciiquarium::+bubble-art-frames+))
           (original-char (char constant-frame 0)))
      (unwind-protect (progn
          (setf (char constant-frame 0) #\X)
          (expect (creature-art existing) :to-equal ".")
          (expect
            (aref (creature-frames cl-asciiquarium::+bubble-sprite-prototype+) 0)
            :to-equal
            ".")
          (let ((future (make-bubble world fish)))
            (expect (creature-art future) :to-equal ".")))
        (setf (char constant-frame 0) original-char))))
  (it
    "draws the same cells as an independently prepared bubble creature"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (fish (make-creature :world world :kind :fish :frames (list "F") :x 5 :y 5))
           (bubble (make-bubble world fish))
           (expected-creature
          (make-creature
            :kind
            :bubble
            :frames
            cl-asciiquarium::+bubble-art-frames+
            :style
            cl-asciiquarium::+bubble-style+
            :x
            (creature-x bubble)
            :y
            (creature-y bubble)))
           (expected (make-screen 20 10))
           (actual (make-screen 20 10)))
      (setf (cl-asciiquarium::creature-frame-index bubble) 2
            (cl-asciiquarium::creature-frame-index expected-creature) 2)
      (cl-asciiquarium::creature-blit expected expected-creature)
      (cl-asciiquarium::creature-blit actual bubble)
      (dotimes (row 10)
        (dotimes (column 20)
          (expect
            (cell-char (screen-cell actual column row))
            :to-be
            (cell-char (screen-cell expected column row)))
          (expect
            (cl-tty-kit:cell-style (screen-cell actual column row))
            :to-equal
            (cl-tty-kit:cell-style (screen-cell expected column row))))))))

(describe
  "creature cache escape tracking"
  (it
    "revalidates constructor frame aliases after a delayed destructive mutation"
    (let* ((frame (copy-seq "a"))
           (creature (make-creature :kind :test :frames (vector frame) :x 0 :y 0)))
      (expect (creature-art creature) :to-equal "a")
      (setf (char frame 0) #\A)
      (expect (creature-art creature) :to-equal "A")))
  (it
    "revalidates setter frame aliases after a delayed destructive mutation"
    (let* ((frame (copy-seq "b"))
           (replacement (vector frame))
           (creature (make-creature :kind :test :frames (list "a") :x 0 :y 0)))
      (setf (creature-frames creature) replacement)
      (expect (creature-art creature) :to-equal "b")
      (setf (char frame 0) #\B)
      (expect (creature-art creature) :to-equal "B")))
  (it
    "keeps getter escape tracking enabled after later cache hits"
    (let* ((creature (make-creature :kind :test :frames (list (copy-seq "a")) :x 0 :y 0))
           (escaped (creature-frames creature)))
      (expect (creature-art creature) :to-equal "a")
      (expect (creature-art creature) :to-equal "a")
      (setf (char (aref escaped 0) 0) #\A)
      (expect (creature-art creature) :to-equal "A")
      (expect (cl-asciiquarium::creature-%frames-escaped-p creature) :to-be-truthy)))
  (it
    "revalidates constructor style aliases without requiring a getter"
    (let* ((style (make-style (style-fg (named-color :bright-white))))
           (creature (make-creature :kind :test :frames (list "x") :style style :x 0 :y 0))
           (before (make-screen 1 1))
           (after (make-screen 1 1)))
      (cl-asciiquarium::creature-blit before creature)
      (setf (second (first style)) (named-color :bright-green))
      (cl-asciiquarium::creature-blit after creature)
      (expect
        (cl-tty-kit:cell-style (screen-cell after 0 0))
        :not
        :to-equal
        (cl-tty-kit:cell-style (screen-cell before 0 0)))))
  (it
    "revalidates setter style aliases after a delayed destructive mutation"
    (let* ((style (make-style (style-fg (named-color :bright-white))))
           (creature (make-creature :kind :test :frames (list "x") :x 0 :y 0))
           (before (make-screen 1 1))
           (after (make-screen 1 1)))
      (setf (creature-style creature) style)
      (cl-asciiquarium::creature-blit before creature)
      (setf (second (first style)) (named-color :bright-green))
      (cl-asciiquarium::creature-blit after creature)
      (expect
        (cl-tty-kit:cell-style (screen-cell after 0 0))
        :not
        :to-equal
        (cl-tty-kit:cell-style (screen-cell before 0 0)))))
  (it
    "skips snapshot scans for privately owned trusted inputs"
    (let ((creature
          (make-creature
            :kind
            :test
            :frames
            (list "a")
            :style
            (make-style (style-fg (named-color :white)))
            :%trusted-frames-p
            t
            :%trusted-style-p
            t
            :x
            0
            :y
            0)))
      (setf (cl-asciiquarium::creature-%prepared-frames creature) (vector 42))
      (cl-asciiquarium::%ensure-creature-caches-current creature)
      (expect (cl-asciiquarium::creature-%frames-escaped-p creature) :to-be-falsy)
      (expect (cl-asciiquarium::creature-%style-escaped-p creature) :to-be-falsy)
      (expect (creature-art creature) :to-equal "a")))
  (it
    "marks factory-owned fish caches escaped after frame and style access"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (fish (make-fish world :species :dart :x 5 :y 5 :dx 0 :facing :right)))
      (expect (cl-asciiquarium::creature-%frames-escaped-p fish) :to-be-falsy)
      (expect (cl-asciiquarium::creature-%style-escaped-p fish) :to-be-falsy)
      (let ((frames (creature-frames fish)))
        (creature-style fish)
        (expect (cl-asciiquarium::creature-%frames-escaped-p fish) :to-be-truthy)
        (expect (cl-asciiquarium::creature-%style-escaped-p fish) :to-be-truthy)
        (setf (char (aref frames 0) 0) #\X)
        (expect (char (creature-art fish) 0) :to-be #\X)))))

(describe
  "creature cache monotonic escape tracking"
  (it
    "tracks right-facing creature-art strings as permanently escaped"
    (let* ((creature
          (make-creature
            :kind
            :test
            :frames
            (list (copy-seq "a<"))
            :%trusted-frames-p
            t
            :x
            0
            :y
            0))
           (art (creature-art creature)))
      (expect (cl-asciiquarium::creature-%frames-escaped-p creature) :to-be-truthy)
      (setf (char art 0) #\A)
      (setf (creature-facing creature) :left)
      (expect (creature-art creature) :to-equal ">A")))
  (it
    "preserves frame escape tracking across private replacement"
    (let* ((creature
          (make-creature
            :kind
            :test
            :frames
            (list (copy-seq "a<"))
            :%trusted-frames-p
            t
            :x
            0
            :y
            0))
           (replacement (copy-seq "b<")))
      (creature-frames creature)
      (cl-asciiquarium::%set-creature-frames creature (vector replacement))
      (expect (cl-asciiquarium::creature-%frames-escaped-p creature) :to-be-truthy)
      (setf (char replacement 0) #\B)
      (setf (creature-facing creature) :left)
      (expect (creature-art creature) :to-equal ">B")))
  (it
    "preserves style escape tracking across private replacement"
    (let* ((creature
          (make-creature
            :kind
            :test
            :frames
            (list "x")
            :style
            (make-style (style-fg (named-color :bright-white)))
            :%trusted-style-p
            t
            :x
            0
            :y
            0))
           (replacement (make-style (style-fg (named-color :bright-white))))
           (before (make-screen 1 1))
           (after (make-screen 1 1)))
      (creature-style creature)
      (cl-asciiquarium::%set-creature-style creature replacement)
      (expect (cl-asciiquarium::creature-%style-escaped-p creature) :to-be-truthy)
      (cl-asciiquarium::creature-blit before creature)
      (setf (second (first replacement)) (named-color :bright-green))
      (cl-asciiquarium::creature-blit after creature)
      (expect
        (cl-tty-kit:cell-style (screen-cell after 0 0))
        :not
        :to-equal
        (cl-tty-kit:cell-style (screen-cell before 0 0))))))

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

(defun %cold-bubble-prototype-table ()
  "An empty stand-in for *BUBBLE-SPRITE-PROTOTYPES*.

That table is global mutable state pre-seeded for :ABYSS only
(src/bubble-data.lisp), so the cache-miss SETF arm -- and with it the only
runtime call to %MAKE-BUBBLE-SPRITE-PROTOTYPE -- is taken by whichever test
asks for a given (THEME MODE) key first, and every later test hits the cache
instead. Binding a cold table per test makes the miss deterministic rather than
an accident of execution order, and stops a non-:ABYSS entry leaking out to
change which branch a later test reaches."
  (make-hash-table :test (function equal)))

(describe
 "%themed-bubble-sprite-prototype"
 (it
  "builds, styles, and caches a colored prototype for each non-abyss theme"
  ;; Expected styles are the palette's own answers (:CORAL remaps
  ;; :BRIGHT-WHITE to :BRIGHT-YELLOW, :MOONLIGHT leaves it alone), written out
  ;; rather than recomputed with VISUAL-STYLE, which is the same call the
  ;; implementation makes and would agree with it by construction.
  (dolist (case (list (list :coral (make-style (style-fg (named-color :bright-yellow))))
                      (list :moonlight (make-style (style-fg (named-color :bright-white))))))
    (destructuring-bind (theme expected-style) case
      (let ((cl-asciiquarium::*monochrome* nil)
            (cl-asciiquarium::*bubble-sprite-prototypes*
             (%cold-bubble-prototype-table)))
        (let ((key (list theme :colored)))
          ;; Assert the precondition the branch depends on: without a cold
          ;; table this test would pass on the cache hit and prove nothing.
          (expect (gethash key cl-asciiquarium::*bubble-sprite-prototypes*)
                  :to-be-falsy)
          (let ((prototype
                 (cl-asciiquarium::%themed-bubble-sprite-prototype theme)))
            (expect (gethash key cl-asciiquarium::*bubble-sprite-prototypes*)
                    :to-be prototype)
            (expect (creature-style prototype) :to-equal expected-style)
            (expect (creature-art prototype) :to-equal ".")
            (expect (cl-asciiquarium::%themed-bubble-sprite-prototype theme)
                    :to-be prototype)))))))
 (it
  "builds and caches a style-free prototype for each non-abyss theme in monochrome"
  (dolist (theme (list :coral :moonlight))
    (let ((cl-asciiquarium::*monochrome* t)
          (cl-asciiquarium::*bubble-sprite-prototypes*
           (%cold-bubble-prototype-table)))
      (let ((key (list theme :monochrome)))
        (expect (gethash key cl-asciiquarium::*bubble-sprite-prototypes*)
                :to-be-falsy)
        (let ((prototype
               (cl-asciiquarium::%themed-bubble-sprite-prototype theme)))
          (expect (gethash key cl-asciiquarium::*bubble-sprite-prototypes*)
                  :to-be prototype)
          ;; The UNLESS *MONOCHROME* arm yields NIL, so the prototype carries
          ;; no colored style even though the theme has a palette entry.
          (expect (creature-style prototype) :to-be-falsy)
          (expect (creature-art prototype) :to-equal ".")
          (expect (cl-asciiquarium::%themed-bubble-sprite-prototype theme)
                  :to-be prototype))))))
 (it
  "keys the cache by theme and colour mode together, not by mode alone"
  (let ((cl-asciiquarium::*bubble-sprite-prototypes*
         (%cold-bubble-prototype-table)))
    (let* ((coral (let ((cl-asciiquarium::*monochrome* nil))
                    (cl-asciiquarium::%themed-bubble-sprite-prototype :coral)))
           (moonlight (let ((cl-asciiquarium::*monochrome* nil))
                        (cl-asciiquarium::%themed-bubble-sprite-prototype
                         :moonlight)))
           (coral-monochrome
            (let ((cl-asciiquarium::*monochrome* t))
              (cl-asciiquarium::%themed-bubble-sprite-prototype :coral))))
      (expect coral :not :to-be moonlight)
      (expect coral :not :to-be coral-monochrome)
      ;; :CORAL recolours the bubble and :MOONLIGHT does not, so a cache keyed
      ;; on mode alone would hand both themes the same style.
      (expect (creature-style coral)
              :not :to-equal (creature-style moonlight))
      (expect (hash-table-count cl-asciiquarium::*bubble-sprite-prototypes*)
              :to-be 3))))
 (it
  "gives a bubble spawned in a non-abyss world that world's themed prototype"
  ;; Reaches %THEMED-BUBBLE-SPRITE-PROTOTYPE through the real spawn path
  ;; (MAKE-BUBBLE -> %BUBBLE-SPRITE-PROTOTYPE, src/bubble.lisp:6), which every
  ;; other bubble test drives with the default :ABYSS theme.
  (let ((cl-asciiquarium::*monochrome* nil)
        (cl-asciiquarium::*bubble-sprite-prototypes*
         (%cold-bubble-prototype-table)))
    (let* ((world (make-world :width 20 :height 10 :fish-count 0 :theme :coral))
           (fish (make-creature :world world :kind :fish :frames (list "F")
                                :x 5 :y 5))
           (bubble (make-bubble world fish))
           (prototype
            (gethash (list :coral :colored)
                     cl-asciiquarium::*bubble-sprite-prototypes*)))
      (expect prototype :to-be-truthy)
      (expect (cl-asciiquarium::creature-%prepared-style bubble)
              :to-be
              (cl-asciiquarium::creature-%prepared-style prototype))
      (expect (creature-style bubble)
              :to-equal (make-style (style-fg (named-color :bright-yellow))))))))
