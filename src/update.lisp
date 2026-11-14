;;;; src/update.lisp -- WORLD-ADVANCE, the one pure per-tick state transition.
;;;;
;;;; This is the function handed to cl-tty-kit:TICK-LOOP-RUN and
;;;; TICK-LOOP-RUN-REALTIME as their ADVANCE argument (see app.lisp). It does
;;;; no I/O and reads no wall clock, so TICK-LOOP-RUN can call it a fixed
;;;; number of times and produce an exactly reproducible final state -- the
;;;; property every test in t/ relies on.
(in-package #:cl-asciiquarium)

(defun dolphin-tick (world dolphin)
  "Recompute DOLPHIN's Y as a sine wave around its :BASELINE-Y, amplitude
:AMPLITUDE, and period :PERIOD (all in its :DATA, set by MAKE-DOLPHIN),
driven by how many ticks have elapsed since its :START-TICK. ENTITY-TICK
already moved its X by its constant DX this same tick; this only overrides Y,
so the dolphin's horizontal crossing and vertical leap are independent."
  (let* ((data (creature-data dolphin))
         (elapsed (- (world-tick world) (getf data :start-tick)))
         (phase (* 2 pi (/ (float elapsed) (getf data :period))))
         (y
          (round
           (- (getf data :baseline-y) (* (getf data :amplitude) (sin phase))))))
    (setf (entity-y (creature-entity dolphin)) (clamp
                                                y
                                                0
                                                (max
                                                 0
                                                 (1- (world-height world)))))))

(defun monster-segment-tick (world segment)
  "Reposition SEGMENT from its :LEADER CREATURE's current position plus its
fixed :OFFSET-X, with a small sine bob (its :PHASE offset by WORLD-TICK) so
consecutive segments undulate out of phase with each other rather than moving
as one rigid rectangle. Once :LEADER exits WORLD and is marked REMOVEP,
SEGMENT marks itself REMOVEP too on its own next tick, so the whole trail
disappears together (one tick behind the head, an imperceptible lag at
ordinary frame rates -- see MAKE-MONSTER-SEGMENT's docstring for why this file
does not instead force leader-before-follower tick ordering)."
  (let* ((data (creature-data segment))
         (leader (getf data :leader)))
    (if (creature-removep leader) (setf (creature-removep segment) t)
      (let ((bob
             (round (sin (+ (getf data :phase) (* 0.4 (world-tick world)))))))
        (setf (entity-x (creature-entity segment)) (+
                                                    (creature-x leader)
                                                    (getf data :offset-x)))
        (setf (entity-y (creature-entity segment)) (+ (creature-y leader) bob))))))

(defun drifting-fish-tick (world fish)
  "The :TICK of a live fish of a DRIFTS-P species: bob around its drift row,
then count its bubble timer down."
  (fish-drift-tick world fish)
  (maybe-emit-bubble world fish))

(defun bubble-tick (world bubble)
  "The :TICK of a bubble: mark it REMOVEP once it reaches the waterline row."
  (when (<= (creature-y bubble) (world-waterline-row world))
    (setf (creature-removep bubble) t)))

(defun tick-creature (world creature width height)
  "Advance one CREATURE and return whether it is marked for removal and its
render state changed. After motion, animation, and the TTL countdown, call the
function designator in CREATURE's :TICK data entry, if any, with WORLD and
CREATURE. Every kind-specific per-tick behaviour lives there, set by the
factory that builds the creature."
  (let ((x (creature-x creature))
        (y (creature-y creature))
        (frame-index (creature-frame-index creature))
        (facing (creature-facing creature)))
    (let ((entity (creature-entity creature)))
      (when (or
             (not (zerop (entity-dx entity)))
             (not (zerop (entity-dy entity)))
             (entity-on-exit entity))
        (entity-tick entity width height)))
    (creature-tick-animation creature)
    (when (creature-ttl creature)
      (decf (creature-ttl creature))
      (when (<= (creature-ttl creature) 0)
        (setf (creature-removep creature) t)))
    (let ((tick (getf (creature-data creature) :tick)))
      (when tick
        (funcall tick world creature)))
    (values
     (creature-removep creature)
     (or
      (/= x (creature-x creature))
      (/= y (creature-y creature))
      (/= frame-index (creature-frame-index creature))
      (not (eq facing (creature-facing creature)))))))

(defun %delete-removed-creatures (creatures)
  "Filter REMOVEP creatures out of CREATURES, sharing the surviving tail
instead of consing a full copy when nothing was removed. Returns (values
new-list removedp)."
  (let ((head nil)
        (tail nil)
        (cursor creatures)
        (removedp nil))
    (loop while cursor
          for creature = (car cursor)
          for next = (cdr cursor)
          do (if (creature-removep creature) (setf removedp t)
               (progn
                 (if tail (setf (cdr tail) cursor)
                   (setf head cursor))
                 (setf tail cursor))) (setf cursor next))
    (when tail
      (setf (cdr tail) nil))
    (values head removedp)))

(defun %flush-removed-creatures (world)
  "Delete WORLD's REMOVEP creatures when a removal is pending."
  (when (world-removal-pending-p world)
    (multiple-value-bind (creatures removedp) (%delete-removed-creatures
                                               (world-%creatures world))
      (when removedp
        (%set-world-creatures world creatures)))))

(defun world-advance (world)
  "Advance WORLD by exactly one tick, returning WORLD. While paused nothing
moves, ages, or spawns, but creatures already marked REMOVEP (by the `-' key)
are still deleted, so they leave the screen."
  (world-tick-ui world)
  (when (world-paused-p world)
    (%flush-removed-creatures world))
  (unless (world-paused-p world)
    (incf (world-tick world))
    (setf (world-render-change-count world) 0)
    (let ((width (world-width world))
          (height (world-height world))
          (removal-pending-p (world-removal-pending-p world))
          (render-change-count 0))
      (dolist (creature (world-%creatures world))
        (multiple-value-bind (removep render-changed-p) (tick-creature
                                                         world
                                                         creature
                                                         width
                                                         height)
          (when removep
            (setf removal-pending-p t))
          (when render-changed-p
            (incf render-change-count))))
      (setf (world-removal-pending-p world) removal-pending-p)
      (apply-collisions world)
      (maybe-spawn-shark world)
      (maybe-spawn-guest world)
      (advance-world-events world)
      (%flush-removed-creatures world)
      (incf (world-render-change-count world) render-change-count)))
  world)
