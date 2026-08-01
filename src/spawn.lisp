;;;; src/spawn.lisp -- periodic spawning: the shark, special guests, and the
;;;; bubble trail each fish periodically emits. Every spawn decision reads
;;;; only the ambient CL:*RANDOM-STATE* (via RANDOM-BETWEEN in art-fish.lisp),
;;;; never a private generator, so binding *RANDOM-STATE* (e.g. via
;;;; SB-EXT:SEED-RANDOM-STATE) makes every spawn in this file deterministic
;;;; for tests.
(in-package #:cl-asciiquarium)

(defparameter +bubble-interval-range+ '(20 . 60))

(defun maybe-spawn-shark (world)
  "Count WORLD's shark cooldown down by one tick; spawn a shark and reset the
cooldown once it reaches zero."
  (decf (world-shark-cooldown world))
  (when (<= (world-shark-cooldown world) 0)
    (push (make-shark world) (world-creatures world))
    (setf (world-shark-cooldown world) (apply #'random-between +shark-cooldown-range+))))

(defun %random-guest-kind ()
  "Return :SHIP or :DUCK-LINE with equal probability."
  (if (zerop (random 2)) :ship :duck-line))

(defun maybe-spawn-guest (world)
  "Count WORLD's guest cooldown down by one tick; spawn a random special
guest (see %RANDOM-GUEST-KIND) and reset the cooldown once it reaches zero."
  (decf (world-guest-cooldown world))
  (when (<= (world-guest-cooldown world) 0)
    (push (ecase (%random-guest-kind)
            (:ship (make-ship world))
            (:duck-line (make-duck-line world)))
          (world-creatures world))
    (setf (world-guest-cooldown world) (apply #'random-between +guest-cooldown-range+))))

(defun maybe-emit-bubble (world fish)
  "Count FISH's per-fish bubble timer (stored in its :BUBBLE-TIMER data entry)
down by one tick; emit a bubble from FISH's position and reset the timer once
it reaches zero."
  (let ((timer (1- (getf (creature-data fish) :bubble-timer))))
    (if (<= timer 0)
        (progn
          (push (make-bubble world fish) (world-creatures world))
          (setf (getf (creature-data fish) :bubble-timer) (apply #'random-between +bubble-interval-range+)))
        (setf (getf (creature-data fish) :bubble-timer) timer))))
