;;;; src/world.lisp -- the simulation's top-level state and its constructors.
(in-package #:cl-asciiquarium)

(defparameter +default-width+ 80)

(defparameter +default-height+ 24)

(defparameter +default-fish-count+ 8)

(defparameter +shark-cooldown-range+ '(180 420))

(progn
  (defparameter +guest-cooldown-range+ (quote (140 360)))
  (defstruct (world (:constructor %make-world)) "The simulation state. Internal mutation of %CREATURES always goes through the cache-maintaining world helpers."
    (width 0 :type fixnum)
    (height 0 :type fixnum)
    (tick 0 :type fixnum)
    (render-change-count 0 :type fixnum)
    (%creatures nil :type list)
    (removal-pending-p nil :type boolean)
    (active-predator-count 0 :type fixnum)
    (fish-count 0 :type fixnum)
    (quitp nil :type boolean)
    (paused-p nil :type boolean)
    (shark-enabled-p t :type boolean)
    (shark-cooldown 0 :type fixnum)
    (guest-cooldown 0 :type fixnum)
    (render-order-cache nil :type list)
    (render-order-valid-p nil :type boolean)))

(progn
  (defun assert-dimensions (width height)
    (unless (and (integerp width) (plusp width)
                 (integerp height) (plusp height))
      (error (quote asciiquarium-invalid-dimensions)
             :width width
             :height height))
    (values width height))
  (defparameter +fish-lane-top+ 9
    "The first terminal row used by swimming creatures, matching upstream layout.")
  (defun default-fish-count-for-dimensions (width height)
    "Return the default fish density used by the terminal-sized aquarium.
The formula follows upstream asciiquarium width and height scaling while still
allowing explicit FISH-COUNT values."
    (max 0
         (floor (* (max 0 (- height +fish-lane-top+))
                   (max 0 width))
                350)))
  (defun default-seaweed-count-for-width (width)
    "Return the number of seaweed strands for terminal WIDTH."
    (floor (max 0 width) 15)))

(progn
  (declaim (inline %active-predator-p))
  (defun %active-predator-p (creature)
    (case (creature-kind creature)
      (:shark t)
      (:anchor (getf (creature-data creature) :dropped))))
  (defun %recount-world-active-predators (creatures)
    (loop for creature in creatures
          count (%active-predator-p creature)))
  (defun %world-has-active-predator-p (world)
    (plusp (world-active-predator-count world)))
  (defun %note-world-predator-activation (world)
    (incf (world-active-predator-count world))
    world)
  (defun %invalidate-world-render-order (world)
    (setf (world-render-order-valid-p world) nil)
    world)
  (defun %set-world-creatures (world creatures)
    (setf (world-%creatures world) creatures
          (world-active-predator-count world) (%recount-world-active-predators
                                               creatures)
          (world-removal-pending-p world) nil)
    (incf (world-render-change-count world))
    (%invalidate-world-render-order world)
    creatures)
  (defun %add-world-creature (world creature)
    (push creature (world-%creatures world))
    (when (%active-predator-p creature)
      (incf (world-active-predator-count world)))
    (incf (world-render-change-count world))
    (%invalidate-world-render-order world)
    creature)
  (defun %world-render-order-cache-valid-p (world)
    (world-render-order-valid-p world))
  (defun %rebuild-world-render-order (world)
    (let* ((creatures (world-%creatures world))
           (render-order
            (stable-sort
             (copy-list creatures)
             (function <)
             :key
             (function creature-z))))
      (setf (world-render-order-cache world) render-order
            (world-render-order-valid-p world) t)
      render-order))
  (defun %world-render-order (world)
    (if (%world-render-order-cache-valid-p world) (world-render-order-cache
                                                   world)
      (%rebuild-world-render-order world))))

(progn
  (defun populate-background (world)
    (%add-world-creature world (make-waterline world))
    (%add-world-creature world (make-castle world))
    (let* ((width (world-width world))
           (seaweed-count (default-seaweed-count-for-width width)))
      (dotimes (i seaweed-count)
        (%add-world-creature
         world
         (make-seaweed
          world
          (round (* width (/ (1+ i) (1+ seaweed-count)))))))))
  (defun populate-fish (world count)
    (dotimes (i count)
      (%add-world-creature world (make-fish world)))))

(defun make-world (&key
                   (width +default-width+)
                   (height +default-height+)
                   (fish-count +default-fish-count+)
                   (shark-enabled-p t))
  "Create a WORLD of WIDTH by HEIGHT, populated with the background decoration
and FISH-COUNT fish at random lanes and speeds. The shark and guest cooldowns
start at a random point in their range so a fresh run does not always wait the
full cooldown before the first shark or guest appears. SHARK-ENABLED-P, when
NIL, disables MAYBE-SPAWN-SHARK for the life of this WORLD (see the
--no-shark CLI flag, cli.lisp)."
  (assert-dimensions width height)
  (let ((world
         (%make-world
          :width
          width
          :height
          height
          :tick
          0
          :%creatures
          nil
          :fish-count
          fish-count
          :quitp
          nil
          :shark-enabled-p
          shark-enabled-p
          :shark-cooldown
          (apply #'random-between +shark-cooldown-range+)
          :guest-cooldown
          (apply #'random-between +guest-cooldown-range+))))
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
    (multiple-value-bind (creature-width creature-height) (creature-dimensions
                                                           creature)
      (setf (entity-x (creature-entity creature)) (clamp
                                                   (creature-x creature)
                                                   0
                                                   (max
                                                    0
                                                    (- width creature-width))))
      (setf (entity-y (creature-entity creature)) (clamp
                                                   (creature-y creature)
                                                   0
                                                   (max
                                                    0
                                                    (- height creature-height))))
      (when (eq (creature-kind creature) :waterline)
        (%set-creature-frames creature (vector (waterline-art width))))))
  world)

(defparameter +redraw-preserved-creature-kinds+ '(:help-overlay)
  "Every CREATURE-KIND that WORLD-REDRAW preserves. The help overlay is UI
state, not aquarium population; every aquarium entity, including background
decorations, is recreated on redraw.")

(defun world-redraw (world)
  "Redraw WORLD by recreating every aquarium entity (see
+REDRAW-PRESERVED-CREATURE-KINDS+), then repopulate fish at fresh random
positions. The help overlay is preserved because it is UI state rather than
aquarium population. Bound to the r key; see input.lisp."
  (%set-world-creatures
   world
   (remove-if-not
    (lambda (creature)
      (member (creature-kind creature)
              +redraw-preserved-creature-kinds+))
    (world-%creatures world)))
  (populate-background world)
  (populate-fish world (world-fish-count world))
  (setf (world-shark-cooldown world) (apply
                                      #'random-between
                                      +shark-cooldown-range+))
  (setf (world-guest-cooldown world) (apply
                                      #'random-between
                                      +guest-cooldown-range+))
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
      (when fish
        (%set-world-creatures world (delete fish (world-%creatures world))))))
  world)
