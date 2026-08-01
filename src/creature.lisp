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
  (ttl nil :type (or null fixnum))
  (removep nil :type boolean)
  (data nil :type list))

(defun %creature-on-exit (creature world policy)
  "Return an ENTITY :ON-EXIT closure implementing POLICY for CREATURE.
:WRAP repositions CREATURE fully back inside WORLD at the edge it left, so it
reappears rather than accelerating away forever. :DESPAWN marks it for removal
at the end of the current tick (WORLD-ADVANCE filters REMOVEP creatures out
after every creature has been ticked). :NONE installs no callback, for
creatures whose velocity never carries them out of bounds (the waterline, the
castle)."
  (ecase policy
    (:wrap (lambda (entity edge) (declare (ignore edge)) (%wrap-creature creature world)))
    (:despawn (lambda (entity edge)
                (declare (ignore entity edge))
                (setf (creature-removep creature) t)))
    (:none nil)))

(defun %wrap-creature (creature world)
  "Reposition CREATURE fully inside WORLD's bounds at the edge its ENTITY just
left. Landing fully inside (rather than just off the opposite edge) is what
keeps this idempotent: a creature ENTITY-TICK finds still out of bounds next
tick would otherwise re-trigger ON-EXIT and bounce between edges forever."
  (multiple-value-bind (width height) (creature-dimensions creature)
    (let ((entity (creature-entity creature))
          (world-width (world-width world))
          (world-height (world-height world)))
      (cond
        ((>= (entity-x entity) world-width) (setf (entity-x entity) 0))
        ((< (entity-x entity) 0) (setf (entity-x entity) (max 0 (- world-width width))))
        ((>= (entity-y entity) world-height) (setf (entity-y entity) 0))
        ((< (entity-y entity) 0) (setf (entity-y entity) (max 0 (- world-height height))))))))

(defun make-creature (&key world x y (dx 0) dy frames frame-period facing style
                       (z 0) ttl kind data (policy :wrap))
  "Create a CREATURE at (X, Y) with velocity (DX, DY) and sprite art FRAMES
(a single string, or a list of strings for a looping animation advanced every
FRAME-PERIOD ticks). WORLD is the owning WORLD, used only to resolve :WRAP
repositioning (see %WRAP-CREATURE) and by default policy :NONE; it is omitted
for creatures constructed as fixtures in isolation from a running world.
POLICY selects the ENTITY :ON-EXIT behavior; see %CREATURE-ON-EXIT."
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
                       :on-exit (and world (%creature-on-exit creature world policy))))
    creature))

(defun creature-x (creature) (entity-x (creature-entity creature)))
(defun creature-y (creature) (entity-y (creature-entity creature)))

(defun creature-art (creature)
  "Return CREATURE's current animation frame, mirrored via MIRROR-SPRITE-TEXT
when CREATURE-FACING is :LEFT."
  (let ((frame (aref (creature-frames creature) (creature-frame-index creature))))
    (if (eq (creature-facing creature) :left)
        (mirror-sprite-text frame)
        frame)))

(defun creature-dimensions (creature)
  "Return (VALUES WIDTH HEIGHT) of CREATURE's current frame. Mirroring
preserves dimensions, so this does not need to mirror first."
  (sprite-dimensions (aref (creature-frames creature) (creature-frame-index creature))))

(defun creature-tick-animation (creature)
  "Advance CREATURE's animation by one tick, looping FRAME-INDEX through
FRAMES every FRAME-PERIOD ticks. A NIL FRAME-PERIOD, or a single frame, is a
no-op."
  (let ((period (creature-frame-period creature)))
    (when (and period (> (length (creature-frames creature)) 1))
      (decf (creature-frame-timer creature))
      (when (<= (creature-frame-timer creature) 0)
        (setf (creature-frame-index creature)
              (mod (1+ (creature-frame-index creature)) (length (creature-frames creature))))
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
