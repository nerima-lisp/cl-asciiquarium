;;;; src/art-food.lisp -- the food grain factory.
(in-package #:cl-asciiquarium)

(defparameter +food-ttl+ 400
  "Ticks an uneaten grain stays in the tank.")

(defparameter +food-sink-rows+ 0.05f0
  "Rows a grain sinks per tick until it reaches the bottom of the swim band.")

(defun make-food (world x y)
  "Create one food grain at (X, Y) in WORLD, sinking and expiring after
+FOOD-TTL+ ticks. Its :DATA is its own list, since FOOD-EATEN-EFFECT clears
its :THREAT."
  (make-creature :world world :kind :food
                 :%sprite-prototype (%food-sprite-prototype (world-theme world))
                 :z 4 :policy :none :x x :y y :dy +food-sink-rows+
                 :ttl +food-ttl+
                 :data (list :threat +food-threat+ :tick 'food-tick)))

(register-creature-restyler
 :food
 (lambda (world food)
   (%set-fixed-creature-colors food :style (creature-%style (%food-sprite-prototype (world-theme world))))))
