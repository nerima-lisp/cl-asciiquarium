;;;; src/art-gull.lisp -- the gull factory and POPULATE-GULLS. Gulls are
;;;; resident sky creatures: they wrap around the screen by day and leave at
;;;; night (GULL-TICK, update-gull.lisp).
(in-package #:cl-asciiquarium)

(defvar *gull-sprite-prototypes* (make-hash-table :test #'equal)
  "Gull sprite prototypes keyed by (THEME COLOR-MODE ASCII), shared by every
gull built or restyled under those settings.")

(defun %gull-sprite-prototype (theme)
  (let ((key (list theme (effective-color-mode) *ascii*)))
    (or (gethash key *gull-sprite-prototypes*)
        (setf (gethash key *gull-sprite-prototypes*)
              (make-creature :kind :gull-sprite-prototype
                             :frames +gull-frames+
                             :masks +gull-masks+
                             :role-styles (mask-role-styles +gull-colors+ :theme theme)
                             :style (color-style :gull :theme theme)
                             :%trusted-frames-p t :%trusted-style-p t
                             :x 0 :y 0 :policy :none)))))

(defun gull-sky-row (world slot)
  "The row the gull of SLOT cruises on in WORLD's current sky."
  (clamp (1+ slot) 0 (- (world-waterline-row world) 2)))

(defun make-gull (world slot)
  "Create the gull for SLOT (an index into +GULL-SLOTS+) cruising the sky of
WORLD. Draws no random number."
  (destructuring-bind (fraction facing speed) (nth slot +gull-slots+)
    (let ((y (gull-sky-row world slot))
          (dx (if (eq facing :right) speed (- speed))))
      (make-creature :world world :kind :gull
                     :%sprite-prototype (%gull-sprite-prototype (world-theme world))
                     :frame-period +gull-flap-period+
                     :facing facing :z 7 :policy :wrap
                     :x (floor (* fraction (world-width world))) :y y :dx dx
                     :data (list :phase :cruise :dive-ready-at 0 :cruise-dx dx :slot slot
                                 :target nil :prey nil :threat nil :tick 'gull-tick)))))

(defun gull-leave (gull)
  "Take GULL out of play with the fish it carries (RELEASE-ATTACHED)."
  (setf (creature-removep gull) t)
  (release-attached gull))

(defun populate-gulls (world)
  "Add gulls to WORLD until +GULL-COUNT+ fly. At night (the :MOONLIGHT theme)
or with fewer than +GULL-MIN-SKY-ROWS+ sky rows, mark every gull REMOVEP
instead, so they leave even while WORLD is paused and GULL-TICK does not run.
A gull already marked REMOVEP does not count as flying: night and day again
in one input batch (`nn') must not leave the day without gulls. Returns
WORLD."
  (if (or (eq (world-theme world) :moonlight)
          (< (world-waterline-row world) +gull-min-sky-rows+))
      (dolist (creature (world-%creatures world))
        (when (eq (creature-kind creature) :gull)
          (gull-leave creature)))
      (loop for slot from (count-if (lambda (creature)
                                      (and (eq (creature-kind creature) :gull)
                                           (not (creature-removep creature))))
                                    (world-%creatures world))
              below +gull-count+
            do (%add-world-creature world (make-gull world slot))))
  world)

(defun restyle-gull (world gull)
  (%adopt-sprite-prototype gull (%gull-sprite-prototype (world-theme world))))

(register-creature-restyler :gull #'restyle-gull)
