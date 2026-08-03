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

(defun %sprite-blit-runs (text style)
  "Prepare non-space horizontal runs as flat X, Y, SCREEN triples."
  (let ((run-count 0)
        (in-run nil))
    (loop for character across text
          do (cond
        ((char= character #\Newline)
          (setf in-run nil))
        ((char= character #\Space)
          (setf in-run nil))
        ((not in-run)
          (incf run-count)
          (setf in-run t))))
    (let ((runs (make-array (* 3 run-count)))
          (run-index 0)
          (row 0)
          (line-start 0)
          (text-length (length text)))
      (loop for line-end = (or (position #\Newline text :start line-start) text-length)
            do (loop with column = 0
              while (< column (- line-end line-start))
              do (if (char= #\Space (char text (+ line-start column))) (incf column)
            (let* ((run-start column)
                   (run-end
                  (or
                    (position #\Space text :start (+ line-start run-start) :end line-end)
                    line-end))
                   (run-text (subseq text (+ line-start run-start) run-end))
                   (source (make-screen (length run-text) 1)))
              (dotimes (offset (length run-text))
                (cl-tty-kit:screen-put-cell source offset 0 (char run-text offset) :style style))
              (setf (svref runs run-index) run-start
                    (svref runs (1+ run-index)) row
                    (svref runs (+ 2 run-index)) source)
              (incf run-index 3)
              (setf column (- run-end line-start))))) (when (= line-end text-length)
          (return runs)) (setf line-start (1+ line-end)) (incf row)))))

(defun %copy-creature-frames (frames)
  (map
    (quote simple-vector)
    (lambda (frame)
      (copy-seq frame))
    frames))

(defun %materialize-creature-frames (creature)
  (when (creature-%frames-shared-p creature)
    (setf (creature-%frames creature) (%copy-creature-frames (creature-%frames creature))
          (creature-%frames-shared-p creature) nil))
  creature)

(defun %materialize-creature-style (creature)
  (when (creature-%style-shared-p creature)
    (setf (creature-%style creature) (copy-tree (creature-%style creature))
          (creature-%style-shared-p creature) nil))
  creature)

(defun %rebuild-creature-blit-runs (creature)
  (let* ((count (length (creature-%frames creature)))
         (normal (make-array count))
         (mirrored (make-array count))
         (style (creature-%style creature)))
    (dotimes (index count)
      (setf (aref normal index) (%sprite-blit-runs (aref (creature-%frames creature) index) style)
            (aref mirrored index) (%sprite-blit-runs (aref (creature-%mirrored-frames creature) index) style)))
    (setf (creature-%frame-runs creature) normal
          (creature-%mirrored-frame-runs creature) mirrored
          (creature-%prepared-frames creature) (%copy-creature-frames (creature-%frames creature))
          (creature-%prepared-style creature) (copy-tree style))
    creature))

(defun %rebuild-creature-frame-caches (creature)
  (let* ((frames (creature-%frames creature))
         (count (length frames))
         (mirrored (make-array count))
         (widths (make-array count))
         (heights (make-array count)))
    (when (zerop count)
      (error "CREATURE-FRAMES must contain at least one frame."))
    (dotimes (index count)
      (let ((frame (aref frames index)))
        (setf (aref mirrored index) (mirror-sprite-text frame))
        (multiple-value-bind (width height) (sprite-dimensions frame)
          (setf (aref widths index) width
                (aref heights index) height))))
    (setf (creature-%mirrored-frames creature) mirrored
          (creature-%frame-widths creature) widths
          (creature-%frame-heights creature) heights
          (creature-frame-index creature) (mod (creature-frame-index creature) count))
    (%rebuild-creature-blit-runs creature)))

(defun %ensure-creature-caches-current (creature)
  (cond
    ((and
        (creature-%frames-escaped-p creature)
        (let ((frames (creature-%frames creature))
              (prepared-frames (creature-%prepared-frames creature)))
          (not
            (and
              (= (length frames) (length prepared-frames))
              (loop for frame across frames
                    for prepared-frame across prepared-frames
                    always (string= frame prepared-frame))))))
      (%rebuild-creature-frame-caches creature))
    ((and
        (creature-%style-escaped-p creature)
        (not (equal (creature-%style creature) (creature-%prepared-style creature))))
      (%rebuild-creature-blit-runs creature)))
  creature)

(defun creature-frames (creature)
  "Return CREATUREs mutable source animation frames."
  (%materialize-creature-frames creature)
  (setf (creature-%frames-escaped-p creature) t)
  (creature-%frames creature))

(defun %set-creature-frames (creature frames &key (escaped-p nil escaped-p-supplied-p))
  (let ((frame-vector (coerce frames 'simple-vector)))
    (when (zerop (length frame-vector))
      (error "CREATURE-FRAMES must contain at least one frame."))
    (setf (creature-%frames creature) frame-vector
          (creature-%frames-shared-p creature) nil
          (creature-%frames-escaped-p creature) (if escaped-p-supplied-p escaped-p
        (creature-%frames-escaped-p creature)))
    (%rebuild-creature-frame-caches creature)
    frames))

(defun (setf creature-frames) (frames creature)
  "Replace CREATURE frames, retaining aliases for compatible destructive mutation."
  (%set-creature-frames creature frames :escaped-p t))

(defun creature-style (creature)
  "Return CREATUREs mutable drawing style."
  (%materialize-creature-style creature)
  (setf (creature-%style-escaped-p creature) t)
  (creature-%style creature))

(defun %set-creature-style (creature style &key (escaped-p nil escaped-p-supplied-p))
  (setf (creature-%style creature) style
        (creature-%style-shared-p creature) nil
        (creature-%style-escaped-p creature) (if escaped-p-supplied-p escaped-p
      (creature-%style-escaped-p creature)))
  (%rebuild-creature-blit-runs creature)
  style)

(defun (setf creature-style) (style creature)
  "Replace CREATURE style, retaining aliases for compatible destructive mutation."
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

(defun %creature-dimensions-current (creature)
  (let ((index (creature-frame-index creature)))
    (values
      (aref (creature-%frame-widths creature) index)
      (aref (creature-%frame-heights creature) index))))

(defun creature-blit (screen creature)
  "Blit CREATURE prepared non-transparent runs onto SCREEN."
  (%ensure-creature-caches-current creature)
  (let* ((index (creature-frame-index creature))
         (runs
        (if (eq (creature-facing creature) :left) (aref (creature-%mirrored-frame-runs creature) index)
          (aref (creature-%frame-runs creature) index)))
         (x (round (creature-x creature)))
         (y (round (creature-y creature))))
    (loop for offset from 0 below (length runs) by 3
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
  (let ((period (creature-frame-period creature))
        (frame-count (length (creature-%frames creature))))
    (when (and period (> frame-count 1))
      (decf (creature-frame-timer creature))
      (when (<= (creature-frame-timer creature) 0)
        (setf (creature-frame-index creature) (mod (1+ (creature-frame-index creature)) frame-count)
              (creature-frame-timer creature) period)))))

(defun %creature-bounds-current (creature)
  (multiple-value-bind (width height) (%creature-dimensions-current creature)
    (values
      (round (creature-x creature))
      (round (creature-y creature))
      width
      height)))

(defun creature-bounds (creature)
  "Return (VALUES X Y WIDTH HEIGHT), CREATURE current integer bounding box."
  (%ensure-creature-caches-current creature)
  (%creature-bounds-current creature))

(defun creatures-overlap-p (a b)
  "Return true when CREATUREs A and B's bounding boxes overlap."
  (multiple-value-bind (ax ay aw ah) (creature-bounds a)
    (multiple-value-bind (bx by bw bh) (creature-bounds b)
      (rects-overlap-p ax ay aw ah bx by bw bh))))
