;;;; src/update.lisp -- WORLD-ADVANCE, the one pure per-tick state transition.
;;;;
;;;; This is the function handed to cl-tty-kit:TICK-LOOP-RUN and
;;;; TICK-LOOP-RUN-REALTIME as their ADVANCE argument (see app.lisp). It does
;;;; no I/O and reads no wall clock, so TICK-LOOP-RUN can call it a fixed
;;;; number of times and produce an exactly reproducible final state -- the
;;;; property every test in t/ relies on.
(in-package #:cl-asciiquarium)

(defun %tick-creature (world creature)
  "Advance one CREATURE by a tick: move its ENTITY, advance its animation
frame, count down its TTL (marking it REMOVEP at zero), and run any
kind-specific per-tick behavior (a fish's bubble trail, a ship's anchor drop,
an anchor's fall-then-settle, a bubble's waterline removal)."
  (entity-tick (creature-entity creature) (world-width world) (world-height world))
  (creature-tick-animation creature)
  (when (creature-ttl creature)
    (decf (creature-ttl creature))
    (when (<= (creature-ttl creature) 0)
      (setf (creature-removep creature) t)))
  (case (creature-kind creature)
    (:fish (when (%alive-fish-p creature) (maybe-emit-bubble world creature)))
    (:ship (%maybe-drop-anchor world creature))
    (:anchor (%anchor-tick creature))
    (:bubble (when (<= (creature-y creature) +waterline-row+) (setf (creature-removep creature) t)))))

(defun world-advance (world)
  "Advance WORLD by exactly one tick, returning WORLD. Every CREATURE is
ticked first (so a fish removed this tick still collides once with a shark
also ticked this tick, matching how a real shark bite and its victim's motion
are simultaneous), then collisions are resolved, then the shark and guest
spawn timers are counted down, and finally every REMOVEP creature is dropped
from the list."
  (incf (world-tick world))
  (dolist (creature (world-creatures world))
    (%tick-creature world creature))
  (apply-collisions world)
  (maybe-spawn-shark world)
  (maybe-spawn-guest world)
  (setf (world-creatures world) (delete-if #'creature-removep (world-creatures world)))
  world)
