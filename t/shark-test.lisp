;;;; t/shark-test.lisp -- the shark's hunt (src/update-shark.lisp): steering
;;;; toward the nearest fish ahead, growing, and leaving full.
(in-package #:cl-asciiquarium/test)

(defun hunting-world ()
  "A 120x30 world with no fish, no automatic shark, and no HUD."
  (make-world :width 120 :height 30 :fish-count 0 :shark-enabled-p nil :hud-visible-p nil))

(defun parked-shark (world &key (x 10) (y 10) (facing :right) (dx 0) (eaten 0))
  "A shark from MAKE-SHARK moved to X Y with speed DX, already in WORLD."
  (let ((shark (make-shark world :facing facing)))
    (setf (entity-x (cl-asciiquarium::creature-entity shark)) x
          (entity-y (cl-asciiquarium::creature-entity shark)) y
          (entity-dx (cl-asciiquarium::creature-entity shark)) dx
          (getf (cl-asciiquarium::creature-data shark) :eaten) eaten)
    (cl-asciiquarium::%add-world-creature world shark)
    shark))

(defun parked-fish (world x y)
  (let ((fish (make-fish world :species :dart :x x :y y :dx 0)))
    (cl-asciiquarium::%add-world-creature world fish)
    fish))

(defun shark-rows-over (world shark ticks)
  (loop repeat ticks
        do (world-advance world)
        collect (creature-y shark)))

(defun shark-center (shark)
  (multiple-value-bind (width height) (creature-dimensions shark)
    (list (round (+ (creature-x shark) (/ width 2)))
          (round (+ (creature-y shark) (/ height 2))))))

(describe "the shark's hunt on the default seed"
  (it "eats at least one fish during one crossing of an 80x24 tank of 18 fish"
    (with-seeded-random-state (42)
      (let ((world (make-world :width 80 :height 24 :fish-count 18 :shark-enabled-p nil))
            (dying-seen nil))
        (spawn-shark-now world)
        (let ((shark (find :shark (cl-asciiquarium::world-%creatures world)
                           :key #'cl-asciiquarium::creature-kind)))
          (loop repeat 1000
                until (cl-asciiquarium::creature-removep shark)
                do (world-advance world)
                   (when (find-if #'dying-p (cl-asciiquarium::world-%creatures world))
                     (setf dying-seen t)))
          (expect (cl-asciiquarium::creature-removep shark) :to-be-truthy)
          (expect dying-seen :to-be-truthy)
          (expect (plusp (getf (cl-asciiquarium::creature-data shark) :eaten)) :to-be-truthy))))))

(describe "the shark steers toward the nearest fish ahead"
  ;; The shark (12 columns) sits at column 10, so its nose is column 22.
  (it "moves 0.25 rows a tick toward a fish 45 columns ahead and 5 rows down"
    (let* ((world (hunting-world))
           (shark (parked-shark world)))
      (parked-fish world (+ 22 45) 15)
      (expect (shark-rows-over world shark 4) :to-equal '(10.25 10.5 10.75 11.0))))
  (it "moves up toward a fish above, and stops once their centers line up"
    (let* ((world (hunting-world))
           (shark (parked-shark world :y 12)))
      (parked-fish world 30 11)
      (expect (shark-rows-over world shark 6) :to-equal '(11.75 11.5 11.25 11.0 11.0 11.0))))
  (it "ignores a fish 46 columns ahead"
    (let* ((world (hunting-world))
           (shark (parked-shark world)))
      (parked-fish world (+ 22 46) 15)
      (expect (shark-rows-over world shark 4) :to-equal '(10 10 10 10))))
  (it "ignores a fish behind its nose"
    (let* ((world (hunting-world))
           (shark (parked-shark world :x 60)))
      (parked-fish world (- 60 46 6) 15)
      (parked-fish world 64 15)
      (expect (shark-rows-over world shark 4) :to-equal '(10 10 10 10))))
  (it "steers toward the nearer of two fish ahead, facing left"
    ;; Facing left at column 60, its nose is column 60: the fish at column 40
    ;; (ending at 46) is 14 columns ahead, the one at column 10 is 44 ahead.
    (let* ((world (hunting-world))
           (shark (parked-shark world :x 60 :facing :left)))
      (parked-fish world 10 15)
      (parked-fish world 40 5)
      (expect (shark-rows-over world shark 2) :to-equal '(9.75 9.5))))
  (it "stays inside the swim band"
    (let* ((world (hunting-world))
           (shark (parked-shark world :y 7)))
      (parked-fish world 30 0)
      (expect (shark-rows-over world shark 2) :to-equal '(7 7)))))

(describe "what eating does to the shark"
  (it "grows into the big art on its second meal, keeping its center"
    (let* ((world (hunting-world))
           (shark (parked-shark world :dx 1.0f0 :eaten 1))
           (fish (parked-fish world 20 10))
           (center (shark-center shark)))
      (apply-collisions world)
      (with-soft-assertions
        (expect (dying-p fish) :to-be t)
        (expect (getf (cl-asciiquarium::creature-data shark) :eaten) :to-be 2)
        (expect (creature-art shark) :to-equal cl-asciiquarium::+shark-big-art+)
        (expect (shark-center shark) :to-equal center)
        (expect (getf (cl-asciiquarium::creature-data shark) :threat) :to-be-truthy))))
  (it "mirrors the big art when facing left"
    (let* ((world (hunting-world))
           (shark (parked-shark world :x 60 :facing :left :eaten 1))
           (center (shark-center shark)))
      (parked-fish world 58 10)
      (apply-collisions world)
      (expect (creature-art shark)
              :to-equal (mirror-sprite-text cl-asciiquarium::+shark-big-art+))
      (expect (shark-center shark) :to-equal center)))
  (it "leaves full on its third meal: no threat, double speed, a notice, and no fourth meal"
    (let* ((world (hunting-world))
           (shark (parked-shark world :dx 1.0f0 :eaten 2))
           (third (parked-fish world 20 10))
           (spared (parked-fish world 21 10)))
      (apply-collisions world)
      (with-soft-assertions
        (expect (getf (cl-asciiquarium::creature-data shark) :eaten) :to-be 3)
        (expect (getf (cl-asciiquarium::creature-data shark) :threat) :to-be nil)
        (expect (entity-dx (cl-asciiquarium::creature-entity shark)) :to-be 2.0f0)
        (expect (cl-asciiquarium::world-notification world)
                :to-equal cl-asciiquarium::+shark-full-message+)
        (expect (count-if #'dying-p (list third spared)) :to-be 1))
      (expect (getf (cl-asciiquarium::creature-data shark) :tick) :to-be nil)
      (let ((x (creature-x shark))
            (y (creature-y shark)))
        (parked-fish world 60 20)
        (world-advance world)
        (expect (creature-y shark) :to-be y)
        (expect (creature-x shark) :to-be (+ x 2.0f0)))))
  (it "restyles the big art on a theme change"
    (let* ((world (hunting-world))
           (shark (parked-shark world :eaten 1)))
      (parked-fish world 20 10)
      (apply-collisions world)
      (world-set-theme world :coral)
      (expect (creature-style shark) :to-equal (cl-asciiquarium::world-style world :white))
      (expect (creature-art shark) :to-equal cl-asciiquarium::+shark-big-art+))))
