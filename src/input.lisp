;;;; src/input.lisp -- turning decoded cl-tty-kit KEY-EVENTs into WORLD state
;;;; changes: `q' to quit, `r' to redraw/reshuffle.
(in-package #:cl-asciiquarium)

(defun world-apply-key-event (world event)
  "Apply one decoded cl-tty-kit KEY-EVENT to WORLD, returning WORLD.
A :CHARACTER event with code #\\q sets WORLD-QUITP; #\\r calls WORLD-REDRAW.
Every other event (including :SPECIAL keys such as arrows, which this
application does not bind) is ignored."
  (when (eq (key-event-type event) :character)
    (case (key-event-code event)
      (#\q (setf (world-quitp world) t))
      (#\Q (setf (world-quitp world) t))
      (#\r (world-redraw world))
      (#\R (world-redraw world))))
  world)

(defun world-apply-key-events (world events)
  "Apply each of EVENTS to WORLD in order via WORLD-APPLY-KEY-EVENT, returning
WORLD."
  (dolist (event events) (world-apply-key-event world event))
  world)
