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
      (expect (creature-x creature) :to-be 0))))

(describe "creature-tick-animation"
  (it "advances frames every frame-period ticks, looping"
    (let ((creature (make-creature :kind :test-thing :frames (list "a" "b") :frame-period 2 :x 0 :y 0)))
      (expect (creature-frame-index creature) :to-be 0)
      (creature-tick-animation creature)
      (expect (creature-frame-index creature) :to-be 0)
      (creature-tick-animation creature)
      (expect (creature-frame-index creature) :to-be 1)
      (creature-tick-animation creature)
      (creature-tick-animation creature)
      (expect (creature-frame-index creature) :to-be 0)))
  (it "is a no-op with a single frame"
    (let ((creature (make-creature :kind :test-thing :frames (list "a") :frame-period 1 :x 0 :y 0)))
      (dotimes (i 5) (creature-tick-animation creature))
      (expect (creature-frame-index creature) :to-be 0))))

(describe "creature-bounds and creatures-overlap-p"
  (it "reports overlapping bounding boxes"
    (let ((a (make-creature :kind :a :frames (list "abc") :x 0 :y 0))
          (b (make-creature :kind :b :frames (list "abc") :x 1 :y 0)))
      (expect (creatures-overlap-p a b) :to-be-truthy)))
  (it "reports non-overlapping bounding boxes"
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
           (creature (make-creature :world world :kind :thing :frames (list "a")
                                    :x 0 :y 0 :dx 0 :dy 0 :policy :none)))
      (entity-tick (creature-entity creature) (world-width world) (world-height world))
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
