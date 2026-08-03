;;;; src/creature.lisp -- the one shape every sprite type goes through.
;;;;
;;;; A CREATURE wraps a cl-tty-kit ENTITY (position + velocity + off-bounds
;;;; callback) with sprite art, an animation frame, a paint order, and an
;;;; optional lifetime. Fish, the shark, bubbles, seaweed, the waterline, the
;;;; castle, the ship, its anchor, and the duck line are ALL CREATURE
;;;; instances distinguished only by their :KIND keyword and the :DATA plist
;;;; -- there is deliberately no per-kind struct or update function. See
;;;; docs/src/reference/architecture.md for the rationale (this is the
;;;; "single entity/collision contract" the architecture review asked for).
(in-package #:cl-asciiquarium)

(defstruct (creature (:constructor %make-creature))
  "A moving, drawable thing. ENTITY carries position and velocity (and fires
ON-EXIT below when it leaves the world bounds); FRAMES is a simple-vector of
sprite-art strings (more than one for a looping animation, such as swaying
seaweed); FACING is :RIGHT (art drawn as authored) or :LEFT (art mirrored via
MIRROR-SPRITE-TEXT); Z is paint order, lower painted first; TTL, when non-NIL,
is a tick countdown after which the creature is removed (used by the shark and
anchor's brief death/lifetime windows); DATA is a plist for kind-specific
extra state (a fish's bubble timer, a ship's anchor-dropped flag, ...)."
  (entity nil :type (or null cl-tty-kit:entity))
  (kind nil :type keyword)
  (frames #() :type simple-vector)
  (frame-index 0 :type fixnum)
  (frame-period nil :type (or null fixnum))
  (frame-timer 0 :type fixnum)
  (facing :right :type keyword)
  (style nil)
  (z 0 :type fixnum)
  (cached-art-frame nil)
  (cached-art nil)
  (cached-dimensions-frame nil)
  (cached-width 0 :type fixnum)
  (cached-height 0 :type fixnum)
  (ttl nil :type (or null fixnum))
  (removep nil :type boolean)
  (data nil :type list))

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

(defun make-creature (&key world x y (dx 0) dy frames frame-period facing style
                       (z 0) ttl kind data (policy :wrap))
  "Create a CREATURE at (X, Y) with velocity (DX, DY) and sprite art FRAMES
(a single string, or a list of strings for a looping animation advanced every
FRAME-PERIOD ticks). WORLD is the owning WORLD, used only to resolve :WRAP
repositioning (see WRAP-CREATURE) and by default policy :NONE; it is omitted
for creatures constructed as fixtures in isolation from a running world.
POLICY selects the ENTITY :ON-EXIT behavior; see CREATURE-ON-EXIT."
  (let* ((frame-vector (coerce (if (listp frames) frames (list frames)) 'simple-vector))
         (creature (%make-creature :kind kind
                                    :frames frame-vector
                                    :frame-index 0
                                    :frame-period frame-period
                                    :frame-timer (or frame-period 0)
                                    :facing (or facing :right)
                                    :style style
                                    :z z
                                    :ttl ttl
                                    :removep nil
                                    :data data)))
    (setf (creature-entity creature)
          (make-entity :x x :y y :dx dx :dy (or dy 0)
                       :on-exit (and world (creature-on-exit creature world policy))))
    creature))

(defun creature-x (creature) (entity-x (creature-entity creature)))
(defun creature-y (creature) (entity-y (creature-entity creature)))

(defun creature-art (creature)
  "Return CREATURE's current animation frame, mirrored via MIRROR-SPRITE-TEXT
when CREATURE-FACING is :LEFT."
  (let* ((frame (aref (creature-frames creature) (creature-frame-index creature)))
         (facing (creature-facing creature)))
    (if (eq facing :left)
        (if (eq frame (creature-cached-art-frame creature))
            (creature-cached-art creature)
            (setf (creature-cached-art-frame creature) frame
                  (creature-cached-art creature) (mirror-sprite-text frame)))
        frame)))

(defun creature-dimensions (creature)
  "Return (VALUES WIDTH HEIGHT) of CREATURE's current frame. Mirroring
preserves dimensions, so this does not need to mirror first."
  (let ((frame (aref (creature-frames creature) (creature-frame-index creature))))
    (if (eq frame (creature-cached-dimensions-frame creature))
        (values (creature-cached-width creature)
                (creature-cached-height creature))
        (multiple-value-bind (width height) (sprite-dimensions frame)
          (setf (creature-cached-dimensions-frame creature) frame
                (creature-cached-width creature) width
                (creature-cached-height creature) height)
          (values width height)))))

(defun creature-tick-animation (creature)
  "Advance CREATURE's animation by one tick, looping FRAME-INDEX through
FRAMES every FRAME-PERIOD ticks. A NIL FRAME-PERIOD, or a single frame, is a
no-op."
  (let* ((period (creature-frame-period creature))
         (frames (creature-frames creature))
         (frame-count (length frames)))
    (when (and period (> frame-count 1))
      (decf (creature-frame-timer creature))
      (when (<= (creature-frame-timer creature) 0)
        (setf (creature-frame-index creature)
              (mod (1+ (creature-frame-index creature)) frame-count))
        (setf (creature-frame-timer creature) period)))))

(defun creature-bounds (creature)
  "Return (VALUES X Y WIDTH HEIGHT), CREATURE's current integer bounding box."
  (multiple-value-bind (width height) (creature-dimensions creature)
    (values (round (creature-x creature)) (round (creature-y creature)) width height)))

(defun creatures-overlap-p (a b)
  "Return true when CREATUREs A and B's bounding boxes overlap."
  (multiple-value-bind (ax ay aw ah) (creature-bounds a)
    (multiple-value-bind (bx by bw bh) (creature-bounds b)
      (rects-overlap-p ax ay aw ah bx by bw bh))))
