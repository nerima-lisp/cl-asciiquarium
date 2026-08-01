;;;; src/art-shark.lisp -- the predator: original shark art and its factory.
;;;;
;;;; Per the project's interaction rule, the shark is the only creature (other
;;;; than a dropped anchor) that removes a fish; see collision.lisp for the
;;;; single collision pass that enforces that rule.
(in-package #:cl-asciiquarium)

(defparameter +shark-art+
  (format nil "      /^\\~%=<{(o.o)}==>~%      \\_/")
  "Original shark art, authored facing right.")

(defun make-shark (world)
  "Create a shark CREATURE crossing WORLD once, at a random lane and a speed
faster than an ordinary fish. Policy :DESPAWN: the shark is removed once it
swims fully off screen, and SPAWN.LISP schedules its next appearance after a
cooldown rather than having it wrap forever like a fish."
  (let* ((height (world-height world))
         (lane-top 3)
         (lane-bottom (max lane-top (- height 5)))
         (facing (if (zerop (random 2)) :left :right))
         (speed (+ 1 (/ (random 3) 3))))
    (make-creature :world world
                    :kind :shark
                    :frames (list +shark-art+)
                    :facing facing
                    :style (make-style (style-fg (named-color :white)))
                    :z 6
                    :policy :despawn
                    :x (if (eq facing :right) (- (sprite-width +shark-art+)) (world-width world))
                    :y (random-between lane-top lane-bottom)
                    :dx (if (eq facing :right) speed (- speed))
                    :data nil)))
