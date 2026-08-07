;;;; src/art-fish.lisp -- the fish factory: species lookup, color choice, and
;;;; MAKE-FISH/KILL-FISH/ALIVE-FISH-P. The species table and death-animation
;;;; art itself are data, in art-fish-data.lisp.
(in-package #:cl-asciiquarium)

(defun fish-species (name)
  (or (find name +fish-species+ :key #'fish-species-entry-name)
      (error 'asciiquarium-unknown-species :name name)))

(defun random-species-color (entry)
  "Return one of ENTRY's COLORS, chosen uniformly at random from its palette."
  (let ((colors (fish-species-entry-colors entry)))
    (nth (random (length colors)) colors)))

(defparameter *fish-sprite-prototypes* (make-hash-table :test #'eq)
  "Maps fish species entries to color-keyed immutable sprite prototypes.")

(defun %make-fish-sprite-prototype (entry color)
  "Create an immutable prepared sprite owner for ENTRY in COLOR mode."
  (make-creature :kind :fish-sprite-prototype
                 :frames (list (copy-seq (fish-species-entry-art entry)))
                 :style (solid-style color)
                 :%trusted-frames-p t
                 :%trusted-style-p t
                 :x 0
                 :y 0
                 :policy :none))

(defun %fish-sprite-prototype (entry color)
  "Return ENTRY's immutable prepared sprite for COLOR and *MONOCHROME*."
  (let* ((prototypes
           (or (gethash entry *fish-sprite-prototypes*)
               (setf (gethash entry *fish-sprite-prototypes*)
                     (make-hash-table :test #'eq))))
         (color-key (unless *monochrome* color)))
    (or (gethash color-key prototypes)
        (setf (gethash color-key prototypes)
              (%make-fish-sprite-prototype entry color)))))

(defun fish-facing-and-dx (facing dx)
  "Return (VALUES FACING DX) for MAKE-FISH: an explicit FACING or DX wins
outright for its own value, but when neither is given, both derive from one
random choice, so 'which way it faces' and 'which way it swims' agree by
construction rather than by separately-defaulted expressions happening to
agree. Passing one argument without the other is only for a test that wants
to check facing and motion independently; ordinary spawning always leaves
both NIL."
  (let* ((resolved-facing (or facing (random-facing)))
         ;; Entity movement runs every frame; avoid allocating rational values
         ;; for the four visually equivalent default swimming speeds.
         (speed (/ (+ 2 (random 4)) 6.0f0)))
    (values resolved-facing
            (or dx (if (eq resolved-facing :right) speed (- speed))))))

(defun make-fish (world &key species x y dx facing)
  "Create a fish CREATURE in WORLD. SPECIES defaults to a random one of
+FISH-SPECIES+; X, Y, DX, and FACING default to a random position, lane, and
direction inside WORLD's swimmable band (below the waterline, above the
seaweed); see FISH-FACING-AND-DX for how FACING and DX default together."
  (let* ((entry (if species
                     (fish-species species)
                     (nth (random (length +fish-species+)) +fish-species+)))
         (width (world-width world))
         (height (world-height world))
         (lane-top (min +fish-lane-top+ (max 0 (1- height))))
         (lane-bottom (max lane-top (- height 3))))
    (multiple-value-bind (facing dx) (fish-facing-and-dx facing dx)
      ;; Preserve the original random draw order: resolve direction before color.
      (let ((color (random-species-color entry)))
        (make-creature :world world
                       :kind :fish
                       :%sprite-prototype (%fish-sprite-prototype entry color)
                       :facing facing
                       :z 5
                       :policy :wrap
                       :x (or x (random (max 1 width)))
                       :y (or y (random-between lane-top lane-bottom))
                       :dx dx
                       :data (list :species (fish-species-entry-name entry)
                                   :bubble-timer (random-between 20 60)))))))

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
