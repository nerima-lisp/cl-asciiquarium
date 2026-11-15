;;;; src/art-vent.lisp -- factories for the seabed life SEABED-LIFE (spawn.lisp)
;;;; adds while the background is built: the bubble plume over the vent and the
;;;; crab on the sand. Neither draws a random number, so building the
;;;; background never shifts a seeded run.
(in-package #:cl-asciiquarium)

(defun plume-frame (width height phase)
  "The plume art for frame PHASE: WIDTH columns by HEIGHT rows of sparse
bubbles over transparent spaces. A stream's bubble sits PHASE rows higher than
in frame 0, so stepping through the frames makes the bubbles rise."
  (with-output-to-string (out)
    (dotimes (row height)
      (unless (zerop row)
        (write-char #\Newline out))
      (let ((rise (- height 1 row)))
        (loop for stream-phase in +plume-stream-phases+
              repeat width
              do (write-char (if (and stream-phase
                                      (zerop (mod (- rise phase stream-phase)
                                                  +plume-frame-count+)))
                                 (char +plume-glyphs+ (floor (* 3 rise) height))
                                 #\Space)
                             out))))))

(defun make-vent-plume (world vent)
  "Create the bubble plume rising from VENT's mouth: 2*+PLUME-HALF-WIDTH+ + 1
columns centered on the mouth, from the row above VENT up to the top of
WORLD's swim band. It is a threat with +PLUME-THREAT+ for as long as it
exists. NIL when VENT stands on the swim band's top row, leaving no room."
  (let* ((top (world-swim-band world))
         (height (- (creature-y vent) top))
         (width (1+ (* 2 +plume-half-width+))))
    (when (plusp height)
      (let* ((frames (loop for phase below +plume-frame-count+
                           collect (plume-frame width height phase)))
             (plume (%make-decor world :plume frames
                                 (mapcar (lambda (frame) (%glyph-mask frame #\m)) frames)
                                 +plume-roles+
                                 :x (- (+ (creature-x vent) (position #\m +vent-mask+))
                                       +plume-half-width+)
                                 :y top :z 1
                                 :frame-period +plume-frame-period+)))
        (setf (creature-data plume)
              (list* :threat +plume-threat+ (creature-data plume)))
        plume))))

(defparameter +crab-columns-per-tick+ 0.05f0
  "How far the crab walks along the sand each tick.")

(defparameter +crab-frame-period+ 6
  "How many ticks each of the crab's two walking frames shows.")

(defun make-crab (world)
  "Create the crab walking right along the sand from a third of the way across
WORLD, or NIL when WORLD is narrower than the crab or too short for it to stand
below the waterline. It turns around at the screen edges (CRAB-TICK)."
  (multiple-value-bind (width height) (sprite-dimensions (first +crab-frames+))
    (let ((y (- (world-sand-top world) height)))
      (when (and (<= width (world-width world))
                 (>= y (world-swim-band world)))
        (let ((crab (%make-decor world :crab +crab-frames+
                                 (list +crab-mask+ +crab-mask+) +crab-roles+
                                 :x (min (floor (world-width world) 3)
                                         (- (world-width world) width))
                                 :y y :z 2
                                 :frame-period +crab-frame-period+)))
          (setf (entity-dx (creature-entity crab)) +crab-columns-per-tick+
                (creature-data crab) (list* :tick 'crab-tick (creature-data crab)))
          crab)))))

(dolist (kind '(:plume :crab))
  (register-creature-restyler kind #'restyle-decor))
