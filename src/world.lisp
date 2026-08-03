;;;; src/world.lisp -- the simulation's top-level state and its constructors.
(in-package #:cl-asciiquarium)

(defparameter +default-width+ 80)
(defparameter +default-height+ 24)
(defparameter +default-fish-count+ 8)
(defparameter +default-seaweed-count+ 4)

(defparameter +shark-cooldown-range+ '(180 420))
(defparameter +guest-cooldown-range+ '(140 360))

(defstruct (world (:constructor %make-world))
  "The whole simulation: WIDTH and HEIGHT are the drawable area, TICK counts
ticks elapsed, CREATURES holds every CREATURE (background, fish, predator,
bubbles, guests -- everything), QUITP is the quit flag input.lisp sets on q,
FISH-COUNT is how many fish WORLD-REDRAW repopulates (the count MAKE-WORLD was
originally given, and what the `+'/`-' keys adjust live -- see
WORLD-INCREASE-FISH-COUNT/WORLD-DECREASE-FISH-COUNT), and the two -COOLDOWN
slots count down the ticks until the next shark or special-guest spawn (see
spawn.lisp). PAUSED, set by the space key, makes WORLD-ADVANCE a no-op while
true (update.lisp). SHARK-ENABLED-P, set once at MAKE-WORLD time from the
--no-shark CLI flag, gates MAYBE-SPAWN-SHARK (spawn.lisp); it is not exposed
as a live toggle the way PAUSED is, since no key currently binds it. Input r
calls WORLD-REDRAW directly."
  (width 0 :type fixnum)
  (height 0 :type fixnum)
  (tick 0 :type fixnum)
  (creatures nil :type list)
  (fish-count 0 :type fixnum)
  (quitp nil :type boolean)
  (paused-p nil :type boolean)
  (shark-enabled-p t :type boolean)
  (shark-cooldown 0 :type fixnum)
  (guest-cooldown 0 :type fixnum)
  (draw-order-source nil :type list)
  (draw-order nil :type list))

(defun assert-dimensions (width height)
  (unless (and (integerp width) (plusp width) (integerp height) (plusp height))
    (error 'asciiquarium-invalid-dimensions :width width :height height)))

(defun populate-background (world)
  (push (make-waterline world) (world-creatures world))
  (push (make-castle world) (world-creatures world))
  (let ((width (world-width world)))
    (dotimes (i +default-seaweed-count+)
      (push (make-seaweed world (round (* width (/ (1+ i) (1+ +default-seaweed-count+)))))
            (world-creatures world)))))

(defun populate-fish (world count)
  (dotimes (i count)
    (push (make-fish world) (world-creatures world))))

(defun make-world (&key (width +default-width+) (height +default-height+)
                    (fish-count +default-fish-count+) (shark-enabled-p t))
  "Create a WORLD of WIDTH by HEIGHT, populated with the background decoration
and FISH-COUNT fish at random lanes and speeds. The shark and guest cooldowns
start at a random point in their range so a fresh run does not always wait the
full cooldown before the first shark or guest appears. SHARK-ENABLED-P, when
NIL, disables MAYBE-SPAWN-SHARK for the life of this WORLD (see the
--no-shark CLI flag, cli.lisp)."
  (assert-dimensions width height)
  (let ((world (%make-world :width width :height height :tick 0 :creatures nil
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
  (dolist (creature (world-creatures world))
    (multiple-value-bind (creature-width creature-height) (creature-dimensions creature)
      (setf (entity-x (creature-entity creature))
            (clamp (creature-x creature) 0 (max 0 (- width creature-width))))
      (setf (entity-y (creature-entity creature))
            (clamp (creature-y creature) 0 (max 0 (- height creature-height))))
      (when (eq (creature-kind creature) :waterline)
        (setf (creature-frames creature) (vector (waterline-art width))))))
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
  (setf (world-creatures world)
        (remove-if (lambda (creature) (member (creature-kind creature) +transient-creature-kinds+))
                   (world-creatures world)))
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
    (push (make-fish world) (world-creatures world)))
  world)

(defun world-decrease-fish-count (world)
  "Lower WORLD-FISH-COUNT by one (down to zero) and remove one live fish from
WORLD to match, returning WORLD. A fish already dying (see ALIVE-FISH-P) is
left alone, so this never interrupts a death animation already in progress.
Bound to the `-' key; see input.lisp."
  (when (plusp (world-fish-count world))
    (decf (world-fish-count world))
    (let ((fish (find-if #'alive-fish-p (world-creatures world))))
      (when fish (setf (world-creatures world) (delete fish (world-creatures world))))))
  world)
