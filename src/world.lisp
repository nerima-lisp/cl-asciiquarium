;;;; src/world.lisp -- the simulation's top-level state and its constructors.
(in-package #:cl-asciiquarium)

(defparameter +default-width+ 80)
(defparameter +default-height+ 24)
(defparameter +default-fish-count+ 8)
(defparameter +default-seaweed-count+ 4)

(defparameter +shark-cooldown-range+ '(180 420))
(defparameter +guest-cooldown-range+ '(140 360))

(progn
  (defstruct (world (:constructor %make-world)) "The whole simulation state. WIDTH and HEIGHT are the drawable area, TICK counts ticks elapsed, %CREATURES holds every CREATURE (background, fish, predator, bubbles, guests -- everything) and remains privately mutable so internal paths can preserve O(1) render-order and active-predator-cache fast paths; WORLD-CREATURES returns a list copy and WORLD-ADD-CREATURE is the explicit mutation operation. QUITP is the quit flag input.lisp sets on `q`. FISH-COUNT is how many fish WORLD-REDRAW repopulates (the count MAKE-WORLD was originally given, and what the `+`/`-` keys adjust live -- see WORLD-INCREASE-FISH-COUNT/WORLD-DECREASE-FISH-COUNT), and the two -COOLDOWN slots count down the ticks until the next shark or special-guest spawn (see spawn.lisp). PAUSED-P, set by the space key, makes WORLD-ADVANCE a no-op while true (update.lisp). SHARK-ENABLED-P, set once at MAKE-WORLD time from the --no-shark CLI flag, gates MAYBE-SPAWN-SHARK (spawn.lisp); it is not exposed as a live toggle the way PAUSED-P is, since no key currently binds it. Input `r` does not set a flag; it calls WORLD-REDRAW directly." (width 0 :type fixnum) (height 0 :type fixnum) (tick 0 :type fixnum) (%creatures nil :type list) (removal-pending-p nil :type boolean) (active-predator-count 0 :type fixnum) (collision-predators nil :type list) (fish-count 0 :type fixnum) (quitp nil :type boolean) (paused-p nil :type boolean) (shark-enabled-p t :type boolean) (shark-cooldown 0 :type fixnum) (guest-cooldown 0 :type fixnum) (render-order-cache nil :type list) (render-order-valid-p nil :type boolean) (render-change-count 0 :type fixnum))
  (defun world-creatures (world)
    "Return a list copy of WORLD's creatures in internal update order."
    (copy-list (world-%creatures world)))
  (defun (setf world-creatures) (creatures world)
    "Replace WORLD's creatures with a privately owned list copy."
    (%set-world-creatures world (copy-list creatures))))

(defun assert-dimensions (width height)
  (unless (and (integerp width) (plusp width) (integerp height) (plusp height))
    (error 'asciiquarium-invalid-dimensions :width width :height height)))

(progn
  (declaim (inline %active-predator-p %collision-predator-p))
  (defun %active-predator-p (creature)
    (case (creature-kind creature)
      (:shark t)
      (:anchor (getf (creature-data creature) :dropped))))
  (defun %collision-predator-p (creature)
    (case (creature-kind creature)
      ((:shark :anchor) t)))
  (defun %rebuild-world-collision-predators (world creatures)
    (let ((predators nil)
          (active-count 0))
      (dolist (creature creatures)
        (when (%collision-predator-p creature)
          (push creature predators)
          (when (%active-predator-p creature)
            (incf active-count))))
      (setf (world-collision-predators world) (nreverse predators)
            (world-active-predator-count world) active-count)))
  (defun %world-has-active-predator-p (world)
    (loop for predator in (world-collision-predators world)
          thereis (%active-predator-p predator)))
  (defun %note-world-predator-activation (world)
    (incf (world-active-predator-count world))
    world)
  (defun %invalidate-world-render-order (world)
    (setf (world-render-order-valid-p world) nil)
    world)
  (defun %set-world-creatures (world creatures)
    (setf (world-%creatures world) creatures
          (world-removal-pending-p world) nil)
    (%rebuild-world-collision-predators world creatures)
    (%invalidate-world-render-order world)
    creatures)

(defun %remove-world-creatures (world creatures removed-active-predator-count)
  "Install CREATURES after internal removal while preserving the render-order cache."
  (setf (world-%creatures world) creatures
        (world-removal-pending-p world) nil)
  (decf (world-active-predator-count world) removed-active-predator-count)
  (setf (world-collision-predators world)
        (delete-if (function creature-removep)
                   (world-collision-predators world)))
  (if (world-render-order-valid-p world)
      (setf (world-render-order-cache world)
            (delete-if (function creature-removep)
                       (world-render-order-cache world)))
      (%invalidate-world-render-order world))
  creatures)
  (defun %insert-creature-into-render-order (world creature)
    (let ((z (creature-z creature))
          (render-order (world-render-order-cache world)))
      (if (or (null render-order)
              (>= (creature-z (car render-order)) z))
          (push creature (world-render-order-cache world))
          (let ((cursor render-order))
            (loop while (and (cdr cursor)
                             (< (creature-z (cadr cursor)) z))
                  do (setf cursor (cdr cursor)))
            (setf (cdr cursor) (cons creature (cdr cursor))))))
    world)
  (defun %add-world-creature (world creature)
    (push creature (world-%creatures world))
    (when (%collision-predator-p creature)
      (push creature (world-collision-predators world)))
    (when (%active-predator-p creature)
      (incf (world-active-predator-count world)))
    (if (world-render-order-valid-p world)
        (%insert-creature-into-render-order world creature)
        (%invalidate-world-render-order world))
    creature)
  (defun %world-render-order-cache-valid-p (world)
    (world-render-order-valid-p world))
  (defun %rebuild-world-render-order (world)
    (let* ((creatures (world-%creatures world))
           (render-order (stable-sort (copy-list creatures) (function <)
                                      :key (function creature-z))))
      (setf (world-render-order-cache world) render-order
            (world-render-order-valid-p world) t)
      render-order))
  (defun %world-render-order (world)
    (if (%world-render-order-cache-valid-p world)
        (world-render-order-cache world)
        (%rebuild-world-render-order world))))

  (defun world-add-creature (world creature)
    "Add CREATURE to WORLD and return CREATURE.
The world owns its creature list; callers never mutate that list directly."
    (%add-world-creature world creature))

(progn
  (defun populate-background (world)
    (%add-world-creature world (make-waterline world))
    (%add-world-creature world (make-castle world))
    (let ((width (world-width world)))
      (dotimes (i +default-seaweed-count+)
        (%add-world-creature
         world
         (make-seaweed world
                       (round (* width (/ (1+ i) (1+ +default-seaweed-count+)))))))))
  (defun populate-fish (world count)
    (dotimes (i count)
      (%add-world-creature world (make-fish world)))))

(defun make-world (&key (width +default-width+) (height +default-height+)
                    (fish-count +default-fish-count+) (shark-enabled-p t))
  "Create a WORLD of WIDTH by HEIGHT, populated with the background decoration
and FISH-COUNT fish at random lanes and speeds. The shark and guest cooldowns
start at a random point in their range so a fresh run does not always wait the
full cooldown before the first shark or guest appears. SHARK-ENABLED-P, when
NIL, disables MAYBE-SPAWN-SHARK for the life of this WORLD (see the
--no-shark CLI flag, cli.lisp)."
  (assert-dimensions width height)
  (let ((world (%make-world :width width :height height :tick 0 :%creatures nil
                             :fish-count fish-count :quitp nil
                             :shark-enabled-p shark-enabled-p
                             :shark-cooldown (apply #'random-between +shark-cooldown-range+)
                             :guest-cooldown (apply #'random-between +guest-cooldown-range+))))
    (populate-background world)
    (populate-fish world fish-count)
    world))

(defun world-resize (world width height)
  "Resize WORLD to WIDTH by HEIGHT in place, returning WORLD.
Existing creatures keep their current position; a creature now outside the
new bounds is clamped back inside rather than left to drift until its next
ENTITY-TICK notices, since a resize can move the bounds inward faster than any
single tick's velocity would. The waterline's width-dependent art is
regenerated to span the new width."
  (assert-dimensions width height)
  (setf (world-width world) width
        (world-height world) height)
  (dolist (creature (world-%creatures world))
    (multiple-value-bind (creature-width creature-height) (creature-dimensions creature)
      (setf (entity-x (creature-entity creature))
            (clamp (creature-x creature) 0 (max 0 (- width creature-width))))
      (setf (entity-y (creature-entity creature))
            (clamp (creature-y creature) 0 (max 0 (- height creature-height))))
      (when (eq (creature-kind creature) :waterline)
        (%set-creature-frames creature (vector (waterline-art width))))))
  world)

(defparameter +transient-creature-kinds+
  '(:fish :shark :bubble :ship :anchor :duck-line :dolphin :sea-monster :monster-segment)
  "Every CREATURE-KIND that WORLD-REDRAW clears: predators, prey, their
by-products, and every special guest. Deliberately excludes the background
(:WATERLINE, :CASTLE, :SEAWEED) and :HELP-OVERLAY, neither of which a redraw
should touch -- the background is not what a player watching the aquarium
expects a redraw to change, and the help overlay is UI state, not aquarium
population.")

(defun world-redraw (world)
  "Reshuffle WORLD: remove every fish, shark, bubble, and guest (see
+TRANSIENT-CREATURE-KINDS+), then repopulate fish at fresh random positions.
The background (waterline, castle, seaweed) is left in place, since it is not
what a player watching the aquarium expects a redraw to change. Bound to the
`r' key; see input.lisp."
  (%set-world-creatures
   world
   (remove-if (lambda (creature) (member (creature-kind creature) +transient-creature-kinds+))
              (world-%creatures world)))
  (populate-fish world (world-fish-count world))
  (setf (world-shark-cooldown world) (apply #'random-between +shark-cooldown-range+))
  (setf (world-guest-cooldown world) (apply #'random-between +guest-cooldown-range+))
  world)

(defparameter +max-fish-count+ 40
  "The upper bound WORLD-INCREASE-FISH-COUNT clamps to, so repeatedly pressing
`+' cannot degrade the frame rate by populating an unbounded number of fish.")

(defun world-increase-fish-count (world)
  "Raise WORLD-FISH-COUNT by one (up to +MAX-FISH-COUNT+) and push one freshly
spawned fish into WORLD to match, returning WORLD. Bound to the `+' key; see
input.lisp."
  (when (< (world-fish-count world) +max-fish-count+)
    (incf (world-fish-count world))
    (%add-world-creature world (make-fish world)))
  world)

(defun world-decrease-fish-count (world)
  "Lower WORLD-FISH-COUNT by one (down to zero) and remove one live fish from
WORLD to match, returning WORLD. A fish already dying (see ALIVE-FISH-P) is
left alone, so this never interrupts a death animation already in progress.
Bound to the `-' key; see input.lisp."
  (when (plusp (world-fish-count world))
    (decf (world-fish-count world))
    (let ((fish (find-if #'alive-fish-p (world-%creatures world))))
      (when fish (%set-world-creatures world (delete fish (world-%creatures world))))))
  world)
