;;;; src/update-food.lisp -- sprinkling food, sinking it, and drawing nearby
;;;; fish toward it. Eating goes through the collision pass (+FOOD-THREAT+).
(in-package #:cl-asciiquarium)

(defparameter +max-food-grains+ 18
  "No food is sprinkled while this many grains are in the tank.")

(defparameter +food-lure-columns+ 20)
(defparameter +food-lure-rows+ 6)

(defun spawn-food-now (world x y count)
  "Add up to COUNT grains to WORLD on row Y, each at a random column within
two of X, never taking WORLD past +MAX-FOOD-GRAINS+ grains."
  (dotimes (i (min count (- +max-food-grains+
                            (count :food (world-%creatures world) :key #'creature-kind))))
    (%add-world-creature
     world
     (make-food world (clamp (+ x (random-between -2 2)) 0 (1- (world-width world))) y)))
  world)

(defun world-scatter-food (world)
  "Sprinkle six grains on the top row of WORLD's swim band, around a column
in the middle half of the width."
  (let ((width (world-width world)))
    (spawn-food-now world
                    (random-between (floor width 4) (floor (* 3 width) 4))
                    (world-swim-band world)
                    6)))

(defun world-apply-mouse-event (world event)
  "Sprinkle three grains at a left-button press, its row clamped into the
swim band. Every other mouse event is ignored. Returns WORLD."
  (when (and (eq (mouse-event-button event) :left)
             (eq (mouse-event-action event) :press))
    (multiple-value-bind (top bottom) (world-swim-band world)
      (spawn-food-now world (mouse-event-x event) (clamp (mouse-event-y event) top bottom) 3)))
  world)

(defun food-eaten-effect (world food fish)
  "FISH eats FOOD: FOOD leaves the tank this tick and grips no other fish."
  (declare (ignore world fish))
  (setf (creature-removep food) t
        (getf (creature-data food) :threat) nil))

(defun %food-ahead-p (dx left width fish-left fish-width)
  "True when a fish at FISH-LEFT FISH-WIDTH swimming with DX leads toward the
food spanning LEFT WIDTH: the food is not behind the fish's tail."
  (cond ((plusp dx) (> (+ left width) fish-left))
        ((minusp dx) (< left (+ fish-left fish-width)))))

(defun food-lured-fish (world food)
  "The live fish outside a school, heading toward FOOD within
+FOOD-LURE-COLUMNS+ empty columns and +FOOD-LURE-ROWS+ empty rows of it,
with the fewest empty cells between them, or NIL."
  (multiple-value-bind (left top width height) (creature-bounds food)
    (let ((best nil) (best-gap (+ +food-lure-columns+ +food-lure-rows+ 1)))
      (dolist (fish (world-%creatures world) best)
        (when (and (alive-fish-p fish)
                   (null (getf (creature-data fish) :leader)))
          (multiple-value-bind (fish-left fish-top fish-width fish-height) (creature-bounds fish)
            (let ((gap-x (%axis-gap left width fish-left fish-width))
                  (gap-y (%axis-gap top height fish-top fish-height)))
              (when (and (<= gap-x +food-lure-columns+)
                         (<= gap-y +food-lure-rows+)
                         (< (+ gap-x gap-y) best-gap)
                         (%food-ahead-p (entity-dx (creature-entity fish))
                                        left width fish-left fish-width))
                (setf best fish best-gap (+ gap-x gap-y))))))))))

(defun food-pull (world food fish)
  "Move FISH at most one column and a quarter row so its middle nears FOOD,
keeping it inside its swim limits. Its velocity and facing are untouched."
  (multiple-value-bind (width height) (creature-dimensions fish)
    (multiple-value-bind (top bottom) (fish-swim-limits world height)
      (let ((entity (creature-entity fish))
            (gap-x (- (+ (creature-x food) 0.5f0) (+ (creature-x fish) (* 0.5f0 width))))
            (gap-y (- (clamp (- (+ (creature-y food) 0.5f0) (* 0.5f0 height)) top bottom)
                      (creature-y fish))))
        (incf (entity-x entity) (clamp gap-x -1.0f0 1.0f0))
        (incf (entity-y entity) (clamp gap-y -0.25f0 0.25f0))))))

(defun food-tick (world food)
  "Keep FOOD sinking until the bottom of the swim band and resting there, then,
unless FOOD expired this tick, draw the nearest lured fish toward it. Nothing
about the pulled fish is remembered."
  (let ((entity (creature-entity food))
        (bottom (nth-value 1 (world-swim-band world))))
    ;; Reset DY above the bottom too: a resize can raise the bottom under a
    ;; grain that had come to rest.
    (if (>= (entity-y entity) bottom)
        (setf (entity-y entity) bottom
              (entity-dy entity) 0)
        (setf (entity-dy entity) +food-sink-rows+)))
  (unless (creature-removep food)
    (let ((fish (food-lured-fish world food)))
      (when fish
        (food-pull world food fish)))))
