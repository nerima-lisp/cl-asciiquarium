;;;; src/art-fish.lisp -- the fish factory: species lookup, color choice, and
;;;; MAKE-FISH/KILL-FISH/ALIVE-FISH-P. The species table and death-animation
;;;; art itself are data, in art-fish-data.lisp.
(in-package #:cl-asciiquarium)

(defun fish-species (name)
  (or (find name +fish-species+ :key #'fish-species-entry-name)
      (error 'asciiquarium-unknown-species :name name)))

(defun random-fish-species ()
  (let ((roll (random 1.0)))
    (dolist (entry +fish-species+)
      (let ((probability (fish-species-entry-spawn-probability entry)))
        (when (and probability (minusp (decf roll probability)))
          (return-from random-fish-species entry))))
    (let ((common (remove-if #'fish-species-entry-spawn-probability +fish-species+)))
      (nth (random (length common)) common))))

(defparameter *fish-sprite-prototypes* (make-hash-table :test #'eq))

(defun %make-fish-sprite-prototype (entry palette-index theme)
  (let* ((palette (nth palette-index (fish-species-entry-color-sets entry)))
         (art (fish-species-entry-art entry))
         (mask (fish-species-entry-mask entry)))
    (when (fish-species-entry-spawn-probability entry)
      (setf art (add-fish-glow art #\✦)
            mask (add-fish-glow mask #\l)))
    (make-creature :kind :fish-sprite-prototype
                   :frames art :masks mask
                   :role-styles (mask-role-styles palette :theme theme)
                   :style (color-style (first palette) :theme theme)
                   :%trusted-frames-p t :%trusted-style-p t
                   :x 0 :y 0 :policy :none)))

(defun %fish-sprite-prototype (entry palette-index theme)
  (let* ((prototypes
           (or (gethash entry *fish-sprite-prototypes*)
               (setf (gethash entry *fish-sprite-prototypes*)
                     (make-hash-table :test #'equal))))
         (theme (parse-visual-theme theme))
         (mode (effective-color-mode))
         (palette-index (if (eq mode :mono) 0 palette-index))
         (key (list palette-index theme mode *ascii*)))
    (or (gethash key prototypes)
        (setf (gethash key prototypes)
              (%make-fish-sprite-prototype entry palette-index theme)))))

(defun fish-facing-and-dx (entry facing dx)
  (let ((resolved-facing (or facing (random-facing))))
    (values resolved-facing
            (or dx
                (destructuring-bind (low high) (fish-species-entry-speed-range entry)
                  (let ((speed (+ low (random (- high low)))))
                    (if (eq resolved-facing :right) speed (- speed))))))))

(defun make-fish (world &key species x y dx facing)
  (let* ((entry (if species (fish-species species) (random-fish-species)))
         (palette-index (random (length (fish-species-entry-color-sets entry))))
         (prototype (%fish-sprite-prototype entry palette-index (world-theme world)))
         (height (nth-value 1 (%creature-dimensions-current prototype))))
    (multiple-value-bind (top bottom) (fish-swim-limits world height)
      (multiple-value-bind (facing dx) (fish-facing-and-dx entry facing dx)
        (let* ((y (or y (random-between top bottom)))
               (data (list :species (fish-species-entry-name entry)
                           :palette-index palette-index
                           :bubble-timer (random-between 20 60)))
               (fish (make-creature :world world :kind :fish
                                    :%sprite-prototype prototype
                                    :facing facing :z 5 :policy :wrap
                                    :x (or x (random (world-width world)))
                                    :y y :dx dx :data data)))
          (when (fish-species-entry-drifts-p entry)
            (setf (creature-data fish)
                  (list* :drift-phase (random 120) :drift-y (round y) data)))
          fish)))))

(defun kill-fish (fish)
  "Convert a live FISH creature into its brief death animation, in place.
Idempotent: a fish already dying (checked via its :DYING data flag) is left
alone, so a fish inside more than one predator's bounding box in the same
tick is only killed once."
  (unless (getf (creature-data fish) :dying)
    (setf (creature-data fish) (list* :dying t (creature-data fish)))
    (%set-creature-frames fish (vector +fish-death-art+))
    (setf (creature-frame-index fish) 0)
    (setf (creature-ttl fish) +death-animation-ticks+)
    (setf (entity-dx (creature-entity fish)) 0)
    (setf (entity-dy (creature-entity fish)) 0)))

(defun alive-fish-p (creature)
  "True for a fish CREATURE not already in its death animation."
  (and (eq (creature-kind creature) :fish)
       (not (getf (creature-data creature) :dying))))

(defun add-fish-glow (text marker)
  (let ((newline (position #\Newline text)))
    (concatenate 'string (subseq text 0 newline) " " (string marker)
                 (subseq text newline))))

(defun fish-swim-limits (world height)
  (multiple-value-bind (top bottom) (world-swim-band world)
    (values top (max top (- bottom height -1)))))

(defun fish-drift-tick (world fish)
  (let* ((data (creature-data fish))
         (phase (getf data :drift-phase)))
    (when phase
      (multiple-value-bind (top bottom)
          (fish-swim-limits world (nth-value 1 (%creature-dimensions-current fish)))
        (let* ((step (mod (+ (world-tick world) phase) 120))
               (offset (cond ((< step 30) 0) ((< step 60) 1)
                             ((< step 90) 0) (t -1)))
               (origin (clamp (getf data :drift-y) top bottom)))
          (setf (entity-y (creature-entity fish))
                (clamp (+ origin offset) top bottom)))))))

(defun restyle-fish (world fish)
  (let* ((data (creature-data fish))
         (entry (fish-species (getf data :species)))
         (prototype (%fish-sprite-prototype entry (getf data :palette-index)
                                           (world-theme world))))
    (%set-creature-colors fish
                          :style (copy-tree (creature-%style prototype))
                          :role-styles (creature-%role-styles prototype))))

(register-creature-restyler :fish #'restyle-fish)
