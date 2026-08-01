(in-package #:cl-asciiquarium/test)

(describe "make-creature"
  (it "positions the entity and stores the given kind and frames"
    (let ((creature (make-creature :kind :test-thing :frames (list "hi") :x 2 :y 3 :dx 1 :dy 0)))
      (expect (creature-kind creature) :to-be :test-thing)
      (expect (creature-x creature) :to-be 2)
      (expect (creature-y creature) :to-be 3)
      (expect (creature-art creature) :to-equal "hi")))
  (it "mirrors its art when facing left"
    (let ((creature (make-creature :kind :test-thing :frames (list "<>") :x 0 :y 0 :facing :left)))
      (expect (creature-art creature) :to-equal "<>")))
  (it "leaves right-facing art unmirrored"
    (let ((creature (make-creature :kind :test-thing :frames (list "<>") :x 0 :y 0 :facing :right)))
      (expect (creature-art creature) :to-equal "<>"))))

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
  (it ":wrap policy repositions a creature that exits the right edge back inside the world"
    (let* ((world (tiny-world :width 10 :height 10))
           (creature (make-creature :world world :kind :thing :frames (list "ab")
                                    :x 9 :y 0 :dx 1 :policy :wrap)))
      (entity-tick (creature-entity creature) (world-width world) (world-height world))
      (expect (creature-x creature) :to-be 0)))
  (it ":wrap policy repositions a creature that exits the left edge back inside the world"
    (let* ((world (tiny-world :width 10 :height 10))
           (creature (make-creature :world world :kind :thing :frames (list "ab")
                                    :x 0 :y 0 :dx -1 :policy :wrap)))
      (entity-tick (creature-entity creature) (world-width world) (world-height world))
      (expect (creature-x creature) :to-be 8)))
  (it ":despawn policy marks a creature removep once it exits the world"
    (let* ((world (tiny-world :width 10 :height 10))
           (creature (make-creature :world world :kind :thing :frames (list "ab")
                                    :x 9 :y 0 :dx 1 :policy :despawn)))
      (expect (creature-removep creature) :to-be-falsy)
      (entity-tick (creature-entity creature) (world-width world) (world-height world))
      (expect (creature-removep creature) :to-be-truthy)))
  (it ":none policy installs no callback, leaving a creature free to sit at the edge"
    (let* ((world (tiny-world :width 10 :height 10))
           (creature (make-creature :world world :kind :thing :frames (list "a")
                                    :x 0 :y 0 :dx 0 :dy 0 :policy :none)))
      (entity-tick (creature-entity creature) (world-width world) (world-height world))
      (expect (creature-removep creature) :to-be-falsy)
      (expect (creature-x creature) :to-be 0))))
