;;;; src/world.lisp -- the simulation's top-level state and its constructors.
(in-package #:cl-asciiquarium)

(defparameter +default-width+ 80)
(defparameter +default-height+ 24)
(defparameter +default-fish-count+ 8)
(defparameter +default-seaweed-count+ 4)

(defparameter +shark-cooldown-range+ '(180 . 420))
(defparameter +guest-cooldown-range+ '(140 . 360))

(defstruct (world (:constructor %make-world))
  "The whole simulation: WIDTH and HEIGHT are the drawable area, TICK counts
ticks elapsed, CREATURES holds every CREATURE (background, fish, predator,
bubbles, guests -- everything), QUITP is the quit flag input.lisp sets on `q',
and the two -COOLDOWN slots count down the ticks until the next shark or
special-guest spawn (see spawn.lisp). `r' (input.lisp) does not set a flag; it
calls WORLD-REDRAW directly."
  (width 0 :type fixnum)
  (height 0 :type fixnum)
  (tick 0 :type fixnum)
  (creatures nil :type list)
  (quitp nil :type boolean)
  (shark-cooldown 0 :type fixnum)
  (guest-cooldown 0 :type fixnum))

(defun %assert-dimensions (width height)
  (unless (and (integerp width) (plusp width) (integerp height) (plusp height))
    (error 'invalid-dimensions :width width :height height)))

(defun %populate-background (world)
  (push (make-waterline world) (world-creatures world))
  (push (make-castle world) (world-creatures world))
  (let ((width (world-width world)))
    (dotimes (i +default-seaweed-count+)
      (push (make-seaweed world (round (* width (/ (1+ i) (1+ +default-seaweed-count+)))))
            (world-creatures world)))))

(defun %populate-fish (world count)
  (dotimes (i count)
    (push (make-fish world) (world-creatures world))))

(defun make-world (&key (width +default-width+) (height +default-height+)
                    (fish-count +default-fish-count+))
  "Create a WORLD of WIDTH by HEIGHT, populated with the background decoration
and FISH-COUNT fish at random lanes and speeds. The shark and guest cooldowns
start at a random point in their range so a fresh run does not always wait the
full cooldown before the first shark or guest appears."
  (%assert-dimensions width height)
  (let ((world (%make-world :width width :height height :tick 0 :creatures nil :quitp nil
                             :shark-cooldown (apply #'random-between +shark-cooldown-range+)
                             :guest-cooldown (apply #'random-between +guest-cooldown-range+))))
    (%populate-background world)
    (%populate-fish world fish-count)
    world))

(defun world-resize (world width height)
  "Resize WORLD to WIDTH by HEIGHT in place, returning WORLD.
Existing creatures keep their current position; a creature now outside the
new bounds is clamped back inside rather than left to drift until its next
ENTITY-TICK notices, since a resize can move the bounds inward faster than any
single tick's velocity would. The waterline's width-dependent art is
regenerated to span the new width."
  (%assert-dimensions width height)
  (setf (world-width world) width
        (world-height world) height)
  (dolist (creature (world-creatures world))
    (multiple-value-bind (creature-width creature-height) (creature-dimensions creature)
      (setf (entity-x (creature-entity creature))
            (clamp (creature-x creature) 0 (max 0 (- width creature-width))))
      (setf (entity-y (creature-entity creature))
            (clamp (creature-y creature) 0 (max 0 (- height creature-height))))
      (when (eq (creature-kind creature) :waterline)
        (setf (creature-frames creature) (vector (%waterline-art width))))))
  world)

(defun world-redraw (world)
  "Reshuffle WORLD: remove every fish, shark, bubble, and guest, then
repopulate fish at fresh random positions. The background (waterline, castle,
seaweed) is left in place, since it is not what a player watching the
aquarium expects a redraw to change. Bound to the `r' key; see input.lisp."
  (setf (world-creatures world)
        (remove-if (lambda (creature)
                     (member (creature-kind creature)
                             '(:fish :shark :bubble :ship :anchor :duck-line)))
                   (world-creatures world)))
  (%populate-fish world +default-fish-count+)
  (setf (world-shark-cooldown world) (apply #'random-between +shark-cooldown-range+))
  (setf (world-guest-cooldown world) (apply #'random-between +guest-cooldown-range+))
  world)
