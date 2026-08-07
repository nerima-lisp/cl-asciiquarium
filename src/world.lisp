;;;; src/world.lisp -- the simulation's top-level state and its constructors.
(in-package #:cl-asciiquarium)

(defparameter +default-width+ 80)

(defparameter +default-height+ 24)

(defparameter +default-fish-count+ 8)

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
  (let ((theme (etypecase value
                 (keyword value)
                 (string (intern (string-upcase value) :keyword)))))
    (if (visual-theme-p theme)
        theme
        (error "Unknown visual theme ~S. Choose one of ~{~A~^, ~}."
               value
               +visual-themes+))))

(defun visual-theme-label (theme)
  (string-upcase (symbol-name (parse-visual-theme theme))))

(defun visual-theme-color (theme color)
  (or (cdr (assoc color
                  (cdr (assoc (parse-visual-theme theme)
                              +visual-theme-palettes+))))
      color))

(defun visual-style (theme color &key bold-p)
  (unless *monochrome*
    (let ((foreground
            (style-fg (named-color (visual-theme-color theme color)))))
      (if bold-p
          (make-style :bold foreground)
          (make-style foreground)))))

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
    (quitp nil :type boolean)
    (paused-p nil :type boolean)
    (theme :abyss)
    (hud-visible-p t :type boolean)
    (shark-enabled-p t :type boolean)
    (shark-cooldown 0 :type fixnum)
    (guest-cooldown 0 :type fixnum)
    (render-order-cache nil :type list)
    (render-order-valid-p nil :type boolean)))

(defun world-style (world color &key bold-p)
  (visual-style (world-theme world) color :bold-p bold-p))

(defun assert-dimensions (width height)
  (unless (and (integerp width) (plusp width) (integerp height) (plusp height))
    (error 'asciiquarium-invalid-dimensions :width width :height height)))

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
    (%add-world-creature world (make-ambient-current world))
    (%add-world-creature world (make-waterline world))
    (%add-world-creature world (make-castle world))
    (let ((width (world-width world)))
      (dotimes (i +default-seaweed-count+)
        (%add-world-creature
         world
         (make-seaweed
          world
          (round (* width (/ (1+ i) (1+ +default-seaweed-count+)))))))))
  (defun populate-fish (world count)
    (dotimes (i count)
      (%add-world-creature world (make-fish world)))))

(defun make-world (&key
                   (width +default-width+)
                   (height +default-height+)
                   (fish-count +default-fish-count+)
                   (shark-enabled-p t)
                   (theme :abyss)
                   (hud-visible-p t))
  "Create a WORLD of WIDTH by HEIGHT, populated with the background decoration
and FISH-COUNT fish at random lanes and speeds. The shark and guest cooldowns
start at a random point in their range so a fresh run does not always wait the
full cooldown before the first shark or guest appears. SHARK-ENABLED-P, when
NIL, disables MAYBE-SPAWN-SHARK for the life of this WORLD (see the
--no-shark CLI flag, cli.lisp)."
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
           :shark-cooldown
           (apply #'random-between +shark-cooldown-range+)
           :guest-cooldown
           (apply #'random-between +guest-cooldown-range+))))
    (populate-background world)
    (populate-fish world fish-count)
    (when hud-visible-p
      (%add-world-creature world (make-hud world)))
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
      (cond
        ((eq (creature-kind creature) :waterline)
         (%set-creature-frames creature (vector (waterline-art width))))
        ((eq (creature-kind creature) :ambient-current)
         (%set-creature-frames creature (ambient-current-frames width)))))
  (world-refresh-hud world)
  world))

(defparameter +transient-creature-kinds+ '(:fish
                                           :shark
                                           :bubble
                                           :ship
                                           :anchor
                                           :duck-line
                                           :dolphin
                                           :sea-monster
                                           :monster-segment)
  "Every CREATURE-KIND that WORLD-REDRAW clears: predators, prey, their
by-products, and every special guest. Deliberately excludes the background
(:WATERLINE, :CASTLE, :SEAWEED, :AMBIENT-CURRENT) and the UI creatures
(:HUD, :HELP-OVERLAY), none of which a redraw should touch -- the background
is not what a player watching the aquarium expects a redraw to change, and
the UI state is independent of aquarium population.")

(defun %visual-scene-creature-p (creature)
  (member (creature-kind creature)
          (append +transient-creature-kinds+
                  '(:waterline :castle :seaweed :ambient-current :hud
                    :help-overlay))))

(defun world-refresh-hud (world)
  (let ((hud (find :hud
                   (world-%creatures world)
                   :key #'creature-kind)))
    (when hud
      (%set-creature-frames hud (list (hud-art world)))
      (%set-creature-style hud (world-style world :bright-white :bold-p t))))
  world)

(defun %rebuild-visual-scene (world)
  (let ((help-visible-p
          (find :help-overlay
                (world-%creatures world)
                :key #'creature-kind))
        (fish-count (world-fish-count world)))
    (%set-world-creatures
     world
     (remove-if #'%visual-scene-creature-p (world-%creatures world)))
    (populate-background world)
    (populate-fish world fish-count)
    (when help-visible-p
      (%add-world-creature world (make-help-overlay world)))
    (when (world-hud-visible-p world)
      (%add-world-creature world (make-hud world))))
  world)

(defun world-cycle-theme (world)
  "Cycle WORLD through the available visual themes and rebuild its scene."
  (setf (world-theme world) (next-visual-theme (world-theme world)))
  (%rebuild-visual-scene world)
  world)

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
The background (waterline, castle, seaweed) is left in place, since it is not
what a player watching the aquarium expects a redraw to change. Bound to the
`r' key; see input.lisp."
  (%set-world-creatures
   world
   (remove-if
    (lambda (creature)
      (member (creature-kind creature) +transient-creature-kinds+))
    (world-%creatures world)))
  (populate-fish world (world-fish-count world))
  (setf (world-shark-cooldown world) (apply
                                      #'random-between
                                      +shark-cooldown-range+))
  (setf (world-guest-cooldown world) (apply
                                      #'random-between
                                      +guest-cooldown-range+))
  (world-refresh-hud world)
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
  (world-refresh-hud world)
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
  (world-refresh-hud world)
  world)
