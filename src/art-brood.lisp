(in-package #:cl-asciiquarium)

(defun make-egg (world species x y)
  (make-creature :world world :kind :egg
                 :%sprite-prototype (%brood-sprite-prototype :egg (world-theme world))
                 :x x :y y :z 5 :policy :none
                 :data (list :species species
                             :hatch-at (+ (world-tick world) 100)
                             :grow-at (+ (world-tick world) 320)
                             :tick 'brood-tick)))

(defun make-heart (world x y)
  (make-creature :world world :kind :heart
                 :%sprite-prototype (%brood-sprite-prototype :heart (world-theme world))
                 :x x :y y :z 6 :ttl 20 :policy :none))

(register-named-color-restyler :egg :bright-white)
(register-named-color-restyler :fry :bright-white)
(register-named-color-restyler :heart :bright-red)
