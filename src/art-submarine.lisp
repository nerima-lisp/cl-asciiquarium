;;;; src/art-submarine.lisp -- the submarine, its sonar rings, and the `!' a
;;;; stunned fish wears. The submarine only alarms (+SUB-THREAT+); its rings
;;;; stun (+SONAR-THREAT+, STUN-EFFECT in update-submarine.lisp).
(in-package #:cl-asciiquarium)

(defparameter +sub-speed+ 0.35f0
  "How many columns the submarine crosses per tick.")

(defparameter +sub-row+ 20
  "The row the submarine's top line aims for, clamped so the whole sprite stays
inside the swim band.")

(defparameter +sonar-interval-ticks+ 50
  "Ticks between two sonar rings, counted from the submarine's spawn.")

(defparameter +sonar-frame-period+ 2
  "Ticks each sonar ring frame stays on screen before the ring widens.")

(defun make-submarine (world &key facing)
  "Create a submarine CREATURE crossing WORLD once near +SUB-ROW+, entering
from the edge opposite FACING (default random). Its first sonar ring is due
+SONAR-INTERVAL-TICKS+ after this tick."
  (multiple-value-bind (width height) (sprite-dimensions +sub-art+)
    (let ((facing (or facing (random-facing)))
          (theme (world-theme world)))
      (multiple-value-bind (x dx) (off-screen-entry facing width (world-width world) +sub-speed+)
        (multiple-value-bind (top bottom) (fish-swim-limits world height)
          (make-creature :world world :kind :sub
                         :frames (list +sub-art+) :masks (list +sub-mask+)
                         :role-styles (%resolve-roles theme +sub-roles+)
                         :style (color-style :fg :theme theme)
                         :%trusted-frames-p t
                         :facing facing :z 4 :policy :despawn
                         :x x :y (clamp +sub-row+ top bottom) :dx dx
                         :data (list :roles +sub-roles+
                                     :sonar-next (+ (world-tick world) +sonar-interval-ticks+)
                                     :threat +sub-threat+
                                     :tick 'sub-tick)))))))

(defun spawn-submarine-now (world)
  "Add a submarine to WORLD now and return it."
  (let ((sub (make-submarine world)))
    (%add-world-creature world sub)
    sub))

(defun %centre-sonar-ring (ring)
  "Move RING so its current frame is centred on its :CENTRE-X."
  (setf (entity-x (creature-entity ring))
        (- (getf (creature-data ring) :centre-x)
           (* 0.5f0 (creature-dimensions ring)))))

(defun make-sonar-ring (world sub)
  "Create a sonar ring centred on SUB as it is now, on SUB's rows. It widens
through +SONAR-FRAMES+ and is removed after the last one."
  (let ((ring (make-creature :world world :kind :sonar
                             :frames +sonar-frames+
                             :style (color-style :sonar :theme (world-theme world))
                             :%trusted-frames-p t
                             :frame-period +sonar-frame-period+
                             :ttl (* (length +sonar-frames+) +sonar-frame-period+)
                             :z 3 :policy :none
                             :x 0 :y (creature-y sub)
                             :data (list :centre-x (+ (creature-x sub)
                                                      (* 0.5f0 (creature-dimensions sub)))
                                         :threat +sonar-threat+
                                         :tick 'sonar-tick))))
    (%centre-sonar-ring ring)
    ring))

(defun make-stun-mark (world fish)
  "Create the `!' shown above stunned FISH. STUN-MARK-TICK moves it."
  (make-creature :world world :kind :stun-mark
                 :frames (list "!")
                 :style (world-style world :yellow)
                 :%trusted-frames-p t
                 :z 7 :policy :none :x 0 :y 0
                 :data (list :fish fish :tick 'stun-mark-tick)))

(register-creature-restyler :sub #'restyle-decor)
(register-creature-restyler
 :sonar (lambda (world ring)
          (%set-creature-colors ring :style (color-style :sonar :theme (world-theme world)))))
(register-named-color-restyler :stun-mark :yellow)
