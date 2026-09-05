;;;; src/creature.lisp -- the one shape every sprite type goes through.
;;;;
;;;; A CREATURE wraps a cl-tty-kit ENTITY (position + velocity + off-bounds
;;;; callback) with sprite art, an animation frame, a paint order, and an
;;;; optional lifetime. Fish, the shark, bubbles, seaweed, the waterline, the
;;;; castle, the ship, its anchor, and the duck line are all CREATURE
;;;; instances distinguished by their :KIND keyword and :DATA plist.
(in-package #:cl-asciiquarium)

(defstruct (creature (:constructor %make-creature)) "A moving, drawable thing. Cached sprite data is revalidated after its mutable source frames or style escape through the public API."
  (entity nil :type (or null cl-tty-kit:entity))
  (kind nil :type keyword)
  (%frames #() :type simple-vector)
  (%frames-shared-p nil :type boolean)
  (%frames-escaped-p nil :type boolean)
  (%prepared-frames #() :type simple-vector)
  (%mirrored-frames #() :type simple-vector)
  (%frame-widths #() :type simple-vector)
  (%frame-heights #() :type simple-vector)
  (%frame-runs #() :type simple-vector)
  (%mirrored-frame-runs #() :type simple-vector)
  (frame-index 0 :type fixnum)
  (frame-period nil :type (or null fixnum))
  (frame-timer 0 :type fixnum)
  (facing :right :type keyword)
  (%style nil)
  (%style-shared-p nil :type boolean)
  (%style-escaped-p nil :type boolean)
  (%prepared-style nil)
  (z 0 :type fixnum)
  (ttl nil :type (or null fixnum))
  (removep nil :type boolean)
  (data nil :type list)
  (collision-left 0 :type integer)
  (collision-top 0 :type integer)
  (collision-width 0 :type integer)
  (collision-height 0 :type integer))

(defun exit-edge-in-travel-direction-p (entity edge)
  "True when EDGE is the one ENTITY's own velocity is carrying it across, as
opposed to the edge it originally spawned beyond and is still approaching.
MAKE-SHARK, MAKE-SHIP, and MAKE-DUCK-LINE all spawn fully off-screen (X
already negative, or already >= WORLD-WIDTH) so they visibly enter the
screen; CL-TTY-KIT:ENTITY-TICK's off-bounds check does not know this and
fires :ON-EXIT for the spawn-side edge on every tick until the entity crosses
back on-screen. Without this check, CREATURE-ON-EXIT's :DESPAWN policy below
would remove the creature on its very first tick, before it ever became
visible."
  (ecase edge
    (:left (minusp (entity-dx entity)))
    (:right (plusp (entity-dx entity)))
    (:top (minusp (entity-dy entity)))
    (:bottom (plusp (entity-dy entity)))))

(defun creature-frames (creature)
  "Return CREATUREs mutable source animation frames."
  (%materialize-creature-frames creature)
  (setf (creature-%frames-escaped-p creature) t)
  (creature-%frames creature))

(defun (setf creature-frames) (frames creature)
  "Replace CREATURE frames and rebuild all derived sprite data."
  (%set-creature-frames creature frames :escaped-p t))

(defun creature-style (creature)
  "Return CREATUREs mutable drawing style."
  (%materialize-creature-style creature)
  (setf (creature-%style-escaped-p creature) t)
  (creature-%style creature))

(defun (setf creature-style) (style creature)
  "Replace CREATURE style and rebuild all derived blit data."
  (%set-creature-style creature style :escaped-p t))

(defun creature-on-exit (creature world policy)
  "Return an ENTITY :ON-EXIT closure implementing POLICY for CREATURE.
:WRAP repositions CREATURE fully back inside WORLD at the edge it left, so it
reappears rather than accelerating away forever. :DESPAWN marks it for removal
once it exits the edge its own velocity carries it toward (see
EXIT-EDGE-IN-TRAVEL-DIRECTION-P), at the end of the current tick
(WORLD-ADVANCE filters REMOVEP creatures out after every creature has been
ticked). :NONE installs no callback, for creatures whose velocity never
carries them out of bounds (the waterline, the castle). Signals
ASCIIQUARIUM-INVALID-POLICY for anything else, since POLICY is a MAKE-CREATURE
keyword argument a caller controls directly, unlike the closed, internally
derived CREATURE-KIND dispatch in update.lisp."
  (case policy
    (:wrap (lambda (entity edge) (declare (ignore entity)) (wrap-creature creature world edge)))
    (:despawn (lambda (entity edge)
                (when (exit-edge-in-travel-direction-p entity edge)
                  (setf (creature-removep creature) t))))
    (:none nil)
    (otherwise (error 'asciiquarium-invalid-policy :policy policy))))

(defun wrap-creature (creature world edge)
  "Reposition CREATURE fully inside WORLD's bounds along the single EDGE its
ENTITY just exited through (:LEFT, :RIGHT, :TOP, or :BOTTOM, exactly as
CL-TTY-KIT:ENTITY-TICK reported it) -- never re-derived from position, so a
diagonal exit (both axes out of bounds the same tick) is handled correctly by
ENTITY-TICK's own guarantee of one callback call per violated edge, rather
than relying on this function happening to converge across repeated calls.
Landing fully inside (rather than just off the opposite edge) is what keeps
this idempotent: a creature ENTITY-TICK finds still out of bounds next tick
would otherwise re-trigger ON-EXIT and bounce between edges forever."
  (multiple-value-bind (width height) (creature-dimensions creature)
    (let ((entity (creature-entity creature))
          (world-width (world-width world))
          (world-height (world-height world)))
      (ecase edge
        (:right (setf (entity-x entity) 0))
        (:left (setf (entity-x entity) (max 0 (- world-width width))))
        (:bottom (setf (entity-y entity) 0))
        (:top (setf (entity-y entity) (max 0 (- world-height height))))))))

(defparameter *monochrome* nil
  "When bound true (see RUN's :MONOCHROME-P in app.lisp), SOLID-STYLE returns
NIL instead of a colored STYLE, so every creature paints in the terminal's
default foreground. Bound as a dynamic variable rather than threaded through
every creature factory's argument list, since SOLID-STYLE is already the one
place every factory's color composition passes through.")

(defun solid-style (color)
  "Return a cl-tty-kit STYLE painting foreground text COLOR (a NAMED-COLOR
keyword) solid, with no other attribute, or NIL when *MONOCHROME* is true.
Every creature factory in art-*.lisp and bubble.lisp builds its :STYLE this
same way; this is the one place that composition is spelled out."
  (unless *monochrome*
    (make-style (style-fg (named-color color)))))

(defun make-creature (&key
    world
    x
    y
    (dx 0)
    dy
    frames
    frame-period
    facing
    style
    (z 0)
    ttl
    kind
    data
    (policy :wrap)
    %sprite-prototype
    %trusted-frames-p
    %trusted-style-p)
  "Create a CREATURE at (X, Y) with velocity (DX, DY) and sprite art FRAMES
(a single string, or a list of strings for a looping animation advanced every
FRAME-PERIOD ticks). WORLD is the owning WORLD, used only to resolve :WRAP
repositioning (see WRAP-CREATURE) and by default policy :NONE; it is omitted
for creatures constructed as fixtures in isolation from a running world.
POLICY selects the ENTITY :ON-EXIT behavior; see CREATURE-ON-EXIT. Internal
trusted inputs (%SPRITE-PROTOTYPE, %TRUSTED-FRAMES-P, %TRUSTED-STYLE-P) must
be privately owned and never exposed except through CREATURE's public
accessors."
  (let ((creature
        (%make-creature
          :kind
          kind
          :frame-index
          0
          :frame-period
          frame-period
          :frame-timer
          (or frame-period 0)
          :facing
          (or facing :right)
          :%style
          (if %sprite-prototype (creature-%style %sprite-prototype)
            style)
          :%style-escaped-p
          (not (or %sprite-prototype %trusted-style-p))
          :z
          z
          :ttl
          ttl
          :removep
          nil
          :data
          data)))
    (if %sprite-prototype (setf (creature-%frames creature) (creature-%frames %sprite-prototype)
            (creature-%frames-shared-p creature) t
            (creature-%frames-escaped-p creature) nil
            (creature-%prepared-frames creature) (creature-%prepared-frames %sprite-prototype)
            (creature-%style-shared-p creature) t
            (creature-%prepared-style creature) (creature-%prepared-style %sprite-prototype)
            (creature-%mirrored-frames creature) (creature-%mirrored-frames %sprite-prototype)
            (creature-%frame-widths creature) (creature-%frame-widths %sprite-prototype)
            (creature-%frame-heights creature) (creature-%frame-heights %sprite-prototype)
            (creature-%frame-runs creature) (creature-%frame-runs %sprite-prototype)
            (creature-%mirrored-frame-runs creature) (creature-%mirrored-frame-runs %sprite-prototype))
      (%set-creature-frames
        creature
        (etypecase frames
          (string (vector frames))
          (list (coerce frames 'simple-vector))
          (vector (coerce frames 'simple-vector)))
        :escaped-p
        (not %trusted-frames-p)))
    (setf (creature-entity creature) (make-entity
        :x
        x
        :y
        y
        :dx
        dx
        :dy
        (or dy 0)
        :on-exit
        (and world (creature-on-exit creature world policy))))
    creature))

(defun creature-x (creature)
  (entity-x (creature-entity creature)))

(defun creature-y (creature)
  (entity-y (creature-entity creature)))

(defun creature-art (creature)
  "Return CREATURE current animation frame, mirrored via MIRROR-SPRITE-TEXT when CREATURE-FACING is :LEFT. Both orientations are cached when frames are assigned."
  (%ensure-creature-caches-current creature)
  (let ((index (creature-frame-index creature)))
    (if (eq (creature-facing creature) :left) (copy-seq (aref (creature-%mirrored-frames creature) index))
      (progn
        (%materialize-creature-frames creature)
        (setf (creature-%frames-escaped-p creature) t)
        (aref (creature-%frames creature) index)))))



(defun creature-blit (screen creature)
  "Blit CREATURE prepared non-transparent runs onto SCREEN."
  (%ensure-creature-caches-current creature)
  (let* ((index (creature-frame-index creature))
         (runs
        (if (eq (creature-facing creature) :left) (aref (creature-%mirrored-frame-runs creature) index)
          (aref (creature-%frame-runs creature) index)))
         (run-count (length runs))
         (x (round (creature-x creature)))
         (y (round (creature-y creature))))
    (loop for offset from 0 below run-count by 3
          do (cl-tty-kit:screen-blit
        screen
        (svref runs (+ offset 2))
        :dest-x
        (+ x (svref runs offset))
        :dest-y
        (+ y (svref runs (1+ offset)))))
    screen))

(defun creature-dimensions (creature)
  "Return (VALUES WIDTH HEIGHT) of CREATURE current frame. Mirroring preserves
dimensions, so this does not need to mirror first. Dimensions are cached when
frames are assigned."
  (%ensure-creature-caches-current creature)
  (%creature-dimensions-current creature))

(defun creature-tick-animation (creature)
  "Advance CREATURE's animation without exposing its private frame vector."
  (let ((period (creature-frame-period creature)))
    (when period
      (let ((frame-count (length (creature-%frames creature))))
        (when (> frame-count 1)
          (decf (creature-frame-timer creature))
          (when (<= (creature-frame-timer creature) 0)
            (let ((frame-index (creature-frame-index creature)))
              (setf (creature-frame-index creature)
                    (if (and (integerp frame-index)
                             (<= 0 frame-index)
                             (< frame-index frame-count))
                        (let ((next-frame-index (1+ frame-index)))
                          (if (= next-frame-index frame-count)
                              0
                              next-frame-index))
                        (mod (1+ frame-index) frame-count))
                    (creature-frame-timer creature) period))))))))

(defun creature-bounds (creature)
  "Return (VALUES X Y WIDTH HEIGHT), CREATURE current integer bounding box."
  (%ensure-creature-caches-current creature)
  (%creature-bounds-current creature))

(defun creatures-overlap-p (a b)
  "Return true when CREATUREs A and B's bounding boxes overlap."
  (multiple-value-bind (ax ay aw ah) (creature-bounds a)
    (multiple-value-bind (bx by bw bh) (creature-bounds b)
      (rects-overlap-p ax ay aw ah bx by bw bh))))
