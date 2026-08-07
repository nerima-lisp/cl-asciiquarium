;;;; src/art-shark.lisp -- the predator: original shark art and its factory.
;;;;
;;;; Per the project's interaction rule, the shark is the only creature (other
;;;; than a dropped anchor) that removes a fish; see collision.lisp for the
;;;; single collision pass that enforces that rule.
(in-package #:cl-asciiquarium)

(defparameter +shark-art+
  (format nil "      /^\\~%=<{(o.o)}==>~%      \\_/")
  "Original shark art, authored facing right.")

(defun make-shark (world &key facing)
  "Create a shark CREATURE crossing WORLD once, at a random lane and a speed
faster than an ordinary fish. Policy :DESPAWN: the shark is removed once it
swims fully off screen, and SPAWN.LISP schedules its next appearance after a
cooldown rather than having it wrap forever like a fish. FACING defaults to a
random :LEFT or :RIGHT, as with MAKE-FISH's :X/:Y/:DX; an explicit override is
what lets a test exercise one crossing direction deterministically."
  (let* ((height (world-height world))
         (lane-top 3)
         (lane-bottom (max lane-top (- height 5)))
         (facing (or facing (random-facing)))
         (speed (+ 1.0f0 (/ (random 3) 3.0f0))))
    (multiple-value-bind (x dx)
        (off-screen-entry facing (sprite-width +shark-art+) (world-width world) speed)
      (make-creature :world world
                     :kind :shark
                     :frames (list +shark-art+)
                     :facing facing
                     :style (world-style world :white)
                     :%trusted-frames-p t
                     :%trusted-style-p t
                     :z 6
                     :policy :despawn
                     :x x
                     :y (random-between lane-top lane-bottom)
                     :dx dx
                     :data nil))))
