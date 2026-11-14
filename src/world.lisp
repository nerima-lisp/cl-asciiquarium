;;;; src/world.lisp -- the simulation's top-level state and its constructors.
(in-package #:cl-asciiquarium)

(defparameter +default-width+ 80)

(defparameter +default-height+ 24)

(defparameter +default-fish-count+ 18)

(defparameter +max-fish-count+ 40
  "The hard ceiling on --max-fish (cli.lisp) and WORLD-MAX-FISH, so repeatedly
pressing `+' cannot degrade the frame rate by populating an unbounded number of
fish.")

(defparameter +default-max-fish+ 30
  "The default for --max-fish: the highest target fish count the `+' key
raises WORLD-FISH-COUNT to.")

(defparameter +default-seaweed-count+ 4)

(defparameter +shark-cooldown-range+ '(180 420))

(defparameter +visual-themes+ '(:abyss :coral :moonlight))

(defparameter +visual-theme-palettes+
  '((:abyss
     (:bright-blue . :bright-blue)
     (:yellow . :yellow)
     (:green . :green)
     (:bright-green . :bright-green)
     (:bright-white . :bright-white)
     (:white . :white)
     (:bright-black . :bright-black)
     (:cyan . :cyan)
     (:bright-cyan . :bright-cyan)
     (:magenta . :magenta)
     (:bright-magenta . :bright-magenta)
     (:red . :red))
    (:coral
     (:bright-blue . :bright-cyan)
     (:yellow . :bright-yellow)
     (:green . :green)
     (:bright-green . :bright-red)
     (:bright-white . :bright-yellow)
     (:white . :bright-white)
     (:bright-black . :red)
     (:cyan . :bright-cyan)
     (:bright-cyan . :bright-white)
     (:magenta . :bright-red)
     (:bright-magenta . :bright-red)
     (:red . :bright-red))
    (:moonlight
     (:bright-blue . :blue)
     (:yellow . :bright-white)
     (:green . :bright-cyan)
     (:bright-green . :bright-cyan)
     (:bright-white . :bright-white)
     (:white . :bright-white)
     (:bright-black . :bright-black)
     (:cyan . :bright-cyan)
     (:bright-cyan . :bright-cyan)
     (:magenta . :blue)
     (:bright-magenta . :bright-cyan)
     (:red . :bright-magenta))))

(defun visual-theme-p (theme)
  (member theme +visual-themes+ :test #'eq))

(defun parse-visual-theme (value)
  (let ((theme (typecase value
                 (keyword value)
                 (string (intern (string-upcase value) :keyword)))))
    (if (visual-theme-p theme)
        theme
        (error 'asciiquarium-invalid-argument
               :value value
               :expected (format nil "a visual theme, one of ~{~(~A~)~^, ~}"
                                 +visual-themes+)))))

(defun visual-theme-label (theme)
  (string-upcase (symbol-name (parse-visual-theme theme))))

(defun visual-theme-color (theme color)
  (or (cdr (assoc color
                  (cdr (assoc (parse-visual-theme theme)
                              +visual-theme-palettes+))))
      color))

(defun visual-style (theme color &key bold-p)
  "Return the style for named 16-color COLOR under THEME. In :ANSI16 this is
the theme's 16-color mapping exactly as before; in :TRUECOLOR and :ANSI256
the mapped color's xterm RGB is painted over THEME's background, so a creature
not yet given its own RGB colors still sits on the water rather than on the
terminal's default background."
  (let ((named (visual-theme-color theme color)))
    (case (effective-color-mode)
      (:mono nil)
      (:ansi16
       (let ((foreground (style-fg (named-color named))))
         (if bold-p
             (make-style :bold foreground)
             (make-style foreground))))
      (t (color-style (multiple-value-list (color-256-to-rgb (named-color named)))
                      :theme theme
                      :bold-p bold-p)))))

(defparameter +waterline-row+ 5
  "The waterline row on a screen at least +FULL-LAYOUT-HEIGHT+ rows tall: the
five rows above it are sky. Shorter screens scale it down; see
LAYOUT-WATERLINE-ROW.")

(defparameter +full-layout-height+ 24
  "The smallest height that shows every band of the layout at full size.")

(defun layout-waterline-row (height)
  "Return the waterline row for a screen HEIGHT rows tall: +WATERLINE-ROW+
from +FULL-LAYOUT-HEIGHT+ rows up, proportionally less below that (row 2 at
the 10-row height the tests use)."
  (min +waterline-row+ (floor (* +waterline-row+ height) +full-layout-height+)))

(defun next-visual-theme (theme)
  (let* ((current (parse-visual-theme theme))
         (tail (member current +visual-themes+ :test #'eq)))
    (or (second tail)
        (first +visual-themes+))))

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
    (max-fish +default-max-fish+ :type fixnum)
    (refill-at 0 :type fixnum)
    (event-due #() :type simple-vector)
    (calm-p nil :type boolean)
    (quitp nil :type boolean)
    (paused-p nil :type boolean)
    (theme :abyss)
    (hud-visible-p t :type boolean)
    (shark-enabled-p t :type boolean)
    (shark-cooldown 0 :type fixnum)
    (guest-cooldown 0 :type fixnum)
    (render-order-cache nil :type list)
    (render-order-valid-p nil :type boolean)
    (ticks-per-second 20 :type fixnum)
    (notification nil :type (or null string))
    (notification-ttl 0 :type fixnum)
    (discovered-species nil :type list)
    (%background-cell nil)
    (%background-theme nil)
    (%background-mode nil)))

(defun world-waterline-row (world)
  (layout-waterline-row (world-height world)))

(defun world-status-row (world)
  "The bottom row, which the status bar always occupies."
  (1- (world-height world)))

(defun world-sand-top (world)
  "The first of the sand rows, which run down to just above the status bar."
  (max (+ (world-waterline-row world) 2) (- (world-height world) 4)))

(defun world-swim-band (world)
  "Return (VALUES TOP BOTTOM), the inclusive rows a swimmer's top line may use:
below the waterline and its ripple row, above the sand. Callers subtract a
sprite's own height from BOTTOM."
  (let ((top (+ (world-waterline-row world) 2)))
    (values top (max top (1- (world-sand-top world))))))

(defun world-background-cell (world)
  "Return WORLD's cached BACKGROUND-CELL for its current theme and color mode,
recomputing it only when either has changed since the last call, so the
renderer can ask for it every frame without allocating."
  (let ((theme (world-theme world))
        (mode (effective-color-mode)))
    (unless (and (eq theme (world-%background-theme world))
                 (eq mode (world-%background-mode world)))
      (setf (world-%background-cell world) (background-cell theme)
            (world-%background-theme world) theme
            (world-%background-mode world) mode))
    (world-%background-cell world)))

(defun world-notify (world message)
  "Show MESSAGE in the status bar's right-hand side for four seconds of
WORLD's ticks, replacing any notification already showing."
  (setf (world-notification world) message
        (world-notification-ttl world) (* 4 (world-ticks-per-second world)))
  (world-refresh-hud world))

(defun world-tick-ui (world)
  "Count the current notification down by one tick, clearing it (and
refreshing the status bar) when it expires. Runs while paused too, so a
notification never outlives its four seconds."
  (when (world-notification world)
    (when (<= (decf (world-notification-ttl world)) 0)
      (setf (world-notification world) nil)
      (world-refresh-hud world)))
  world)

(defun world-style (world color &key bold-p)
  (visual-style (world-theme world) color :bold-p bold-p))

(defun assert-dimensions (width height)
  (unless (and (integerp width) (plusp width) (integerp height) (plusp height))
    (error 'asciiquarium-invalid-dimensions :width width :height height)))

(progn
  (declaim (inline %active-predator-p))
  (defun %active-predator-p (creature)
    (getf (creature-data creature) :threat))
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
    ;; A creature marked REMOVEP outside a tick (the `-' key) may survive a
    ;; list replaced by another key in the same input batch, so recompute the
    ;; pending flag from the new list rather than clearing it.
    (setf (world-%creatures world) creatures
          (world-active-predator-count world) (%recount-world-active-predators
                                               creatures)
          (world-removal-pending-p world) (and (some #'creature-removep creatures) t))
    (incf (world-render-change-count world))
    (%invalidate-world-render-order world)
    creatures)
  (defun %add-world-creature (world creature)
    (push creature (world-%creatures world))
    (when (eq (creature-kind creature) :fish)
      (let ((species (getf (creature-data creature) :species)))
        (unless (member species (world-discovered-species world))
          (push species (world-discovered-species world))
          (when (fish-species-entry-spawn-probability (fish-species species))
            (world-notify world (format nil "Discovered: ~(~A~)" species))))))
    (when (%active-predator-p creature)
      (incf (world-active-predator-count world)))
    (incf (world-render-change-count world))
    (%invalidate-world-render-order world)
    creature)
  (defun attach-creature (world owner child)
    "Add CHILD to WORLD as a creature that leaves with OWNER: every path that
takes OWNER out of play calls RELEASE-ATTACHED. Children that already left on
their own are dropped from OWNER's :ATTACHED here, so a long-lived owner's
list holds only its current children."
    (let ((data (creature-data owner)))
      (setf (getf data :attached)
            (cons child (delete-if #'creature-removep (getf data :attached))))
      (setf (creature-data owner) data))
    (%add-world-creature world child))
  (defun release-attached (owner)
    "Mark every child ATTACH-CREATURE registered on OWNER REMOVEP and forget
them. A child released during a tick stays in the list until the end of the
next WORLD-ADVANCE, so its :TICK is cleared too: it must not act on an owner
that has left (a stun mark restoring a dying fish's speed)."
    (let ((data (creature-data owner)))
      (when (getf data :attached)
        (dolist (child (getf data :attached))
          (setf (creature-removep child) t)
          (when (getf (creature-data child) :tick)
            (setf (getf (creature-data child) :tick) nil)))
        (setf (getf data :attached) nil))))
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
    (dolist (creature (make-background-creatures world))
      (%add-world-creature world creature)))
  (defun populate-fish (world count)
    (dotimes (i count)
      (%add-world-creature world (make-fish world)))))

(defun make-world (&key
                   (width +default-width+)
                   (height +default-height+)
                   (fish-count +default-fish-count+)
                   (max-fish +default-max-fish+)
                   (shark-enabled-p t)
                   calm-p
                   (theme :abyss)
                   (hud-visible-p t)
                   (ticks-per-second 20))
  "Create a WORLD of WIDTH by HEIGHT, populated with the background decoration
and FISH-COUNT fish at random lanes and speeds. The shark and guest cooldowns
start at a random point in their range so a fresh run does not always wait the
full cooldown before the first shark or guest appears. SHARK-ENABLED-P, when
NIL, disables MAYBE-SPAWN-SHARK for the life of this WORLD (see the
--no-shark CLI flag, cli.lisp). MAX-FISH, itself capped at +MAX-FISH-COUNT+,
caps what the `+' key raises FISH-COUNT to; FISH-COUNT itself is not truncated
to it. CALM-P (--calm) stops
blinking animations; see BLINK-FRAME-PERIOD. Neither draws a random number."
  (assert-dimensions width height)
  (let* ((theme (parse-visual-theme theme))
         (world
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
           :max-fish
           (min max-fish +max-fish-count+)
           :calm-p
           calm-p
           :event-due
           (make-event-due-vector)
           :quitp
           nil
           :paused-p
           nil
           :theme
           theme
           :hud-visible-p
           hud-visible-p
           :shark-enabled-p
           shark-enabled-p
           :ticks-per-second
           ticks-per-second
           :shark-cooldown
           (apply #'random-between +shark-cooldown-range+)
           :guest-cooldown
           (apply #'random-between +guest-cooldown-range+))))
    (populate-background world)
    (populate-fish world fish-count)
    (when hud-visible-p
      (%add-world-creature world (make-hud world)))
    world))

(defparameter +background-creature-kinds+
  '(:ambient-current :waterline :ripple :sky :sand :castle :seaweed
    :coral :rock :starfish :vent :chest
    :plume
    :octopus
    :crab)
  "Every CREATURE-KIND MAKE-BACKGROUND-CREATURES (art-decor.lisp) lays out
from the screen size, and so WORLD-RESIZE rebuilds.")

(defun %drop-creature-kinds (world kinds)
  "Take every creature whose kind is in KINDS out of WORLD together with the
children attached to it (ATTACH-CREATURE). They are marked REMOVEP first, so a
creature that keeps a reference to one (a diver's chest, an octopus's
tentacle) sees it leave; the list then drops them along with anything else
already marked, so a released child never ticks or threatens again."
  (let ((creatures (world-%creatures world)))
    (dolist (creature creatures)
      (when (member (creature-kind creature) kinds)
        (setf (creature-removep creature) t)
        (release-attached creature)))
    (%set-world-creatures world (remove-if #'creature-removep creatures))))

(defun world-resize (world width height)
  "Resize WORLD to WIDTH by HEIGHT in place, returning WORLD.
Existing creatures keep their current position; a creature now outside the
new bounds is clamped back inside rather than left to drift until its next
ENTITY-TICK notices, since a resize can move the bounds inward faster than any
single tick's velocity would. The background (+BACKGROUND-CREATURE-KINDS+)
is laid out from the screen size, so it is rebuilt for the new size rather
than clamped (the old octopus's tentacle and ink leave with it, see
%DROP-CREATURE-KINDS), and the status bar is refreshed onto the new bottom
row."
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
                                                    (- height creature-height))))))
  (%drop-creature-kinds world +background-creature-kinds+)
  (populate-background world)
  (world-refresh-hud world)
  world)

(defparameter +transient-creature-kinds+ '(:fish
                                           :caught-fish
                                           :egg
                                           :fry
                                           :heart
                                           :lantern-glow
                                           :shark
                                           :bubble
                                           :ship
                                           :anchor
                                           :duck-line
                                           :dolphin
                                           :sea-monster
                                           :monster-segment
                                           :chain
                                           :coin
                                           :sub
                                           :sonar
                                           :stun-mark
                                           :tentacle
                                           :ink
                                           :dinghy
                                           :rope
                                           :diver)
  "Every CREATURE-KIND that WORLD-REDRAW clears: predators, prey, their
by-products, and every special guest. Deliberately excludes the background
(+BACKGROUND-CREATURE-KINDS+) and the UI creatures
(:HUD, :HELP-OVERLAY), none of which a redraw should touch -- the background
is not what a player watching the aquarium expects a redraw to change, and
the UI state is independent of aquarium population.")

(defun world-refresh-hud (world)
  "Rebuild the status bar's text for WORLD's current state and keep it on the
bottom row. Called whenever something the bar shows changes, never per tick."
  (let ((hud (find :hud
                   (world-%creatures world)
                   :key #'creature-kind)))
    (when hud
      (multiple-value-bind (art mask role-styles) (hud-sprite world)
        (%set-creature-frames hud (list art) :masks (list mask) :role-styles role-styles))
      (setf (entity-y (creature-entity hud)) (world-status-row world))))
  world)

(defvar *creature-restylers* (make-hash-table :test #'eq)
  "Maps a CREATURE-KIND to a (WORLD CREATURE) function that recolors that
creature in place for WORLD's current theme. Each art file registers the kinds
it creates; a kind with no entry keeps its colors until it leaves the screen.")

(defun register-creature-restyler (kind function)
  (setf (gethash kind *creature-restylers*) function))

(defun register-named-color-restyler (kind color)
  "Register a restyler for KIND, whose creatures are painted solid in the
named 16-color COLOR mapped through the theme (WORLD-STYLE): the shark and
every special guest."
  (register-creature-restyler
   kind
   (lambda (world creature)
     (%set-creature-colors creature :style (world-style world color)))))

(defun world-set-theme (world theme)
  "Switch WORLD to THEME by recoloring every creature in place. Unlike a scene
rebuild, no creature is removed, added, or moved and no random number is drawn,
so a theme change (the `t' key, or the time of day) never reshuffles the
aquarium."
  (setf (world-theme world) (parse-visual-theme theme))
  (dolist (creature (world-%creatures world))
    (let ((restyler (gethash (creature-kind creature) *creature-restylers*)))
      (when restyler
        (funcall restyler world creature))))
  (incf (world-render-change-count world))
  world)

(defun world-cycle-theme (world)
  "Cycle WORLD to the next visual theme, recoloring it in place."
  (world-set-theme world (next-visual-theme (world-theme world))))

(defun world-toggle-hud (world)
  "Toggle the persistent status bar without drawing outside the renderer."
  (if (setf (world-hud-visible-p world) (not (world-hud-visible-p world)))
      (%add-world-creature world (make-hud world))
      (%set-world-creatures
       world
       (remove :hud (world-%creatures world) :key #'creature-kind)))
  world)

(defun world-redraw (world)
  "Reshuffle WORLD: remove every fish, shark, bubble, and guest (see
+TRANSIENT-CREATURE-KINDS+), then repopulate fish at fresh random positions.
The background (waterline, castle, seaweed, the octopus) is left in place,
since it is not what a player watching the aquarium expects a redraw to
change; the octopus's tentacle and ink are transient and go. Bound to the `r'
key; see input.lisp."
  (%drop-creature-kinds world +transient-creature-kinds+)
  (populate-fish world (world-fish-count world))
  (setf (world-shark-cooldown world) (apply
                                      #'random-between
                                      +shark-cooldown-range+))
  (setf (world-guest-cooldown world) (apply
                                      #'random-between
                                      +guest-cooldown-range+))
  (world-refresh-hud world)
  world)

(defun world-increase-fish-count (world)
  "Raise WORLD-FISH-COUNT by one (up to WORLD-MAX-FISH) and push one freshly
spawned fish into WORLD to match, returning WORLD. The fish is added only
while live fish are below WORLD-MAX-FISH, so a visiting school that already
fills the tank keeps `+' from overfilling it. Bound to the `+' key; see
input.lisp."
  (when (< (world-fish-count world) (world-max-fish world))
    (incf (world-fish-count world))
    (when (< (count-if #'alive-fish-p (world-%creatures world)) (world-max-fish world))
      (%add-world-creature world (make-fish world))))
  (world-refresh-hud world)
  world)

(defun world-decrease-fish-count (world)
  "Lower WORLD-FISH-COUNT by one (down to zero), returning WORLD. One live fish
is removed only when more live fish than the new target remain, so a press
while a refill is pending lowers the target instead of taking a second fish.
A fish already dying (see ALIVE-FISH-P) is left alone, so this never
interrupts a death animation already in progress. The removed fish stops its
behaviour (FISH-STOP-BEHAVIOUR) and is marked REMOVEP, so it stops counting as
live at once and WORLD-ADVANCE deletes it, with the creatures attached to it
(a lantern's glow, a stun mark), at the end of its next call, paused or not;
school followers let go on their next tick. Bound to the `-' key; see
input.lisp."
  (when (plusp (world-fish-count world))
    (decf (world-fish-count world))
    (when (> (count-if #'alive-fish-p (world-%creatures world)) (world-fish-count world))
      (let ((fish (find-if #'alive-fish-p (world-%creatures world))))
        (fish-stop-behaviour fish)
        (setf (creature-removep fish) t
              (world-removal-pending-p world) t))))
  (world-refresh-hud world)
  world)

(defun blink-frame-period (world period)
  "The :FRAME-PERIOD a factory gives a blinking animation: PERIOD, or NIL under
--calm (WORLD-CALM-P), which holds the creature on its first frame. Every
blinking frame goes through this function. It draws no random number, so a
calm run moves every creature exactly as the same seed without --calm."
  (unless (world-calm-p world)
    period))
