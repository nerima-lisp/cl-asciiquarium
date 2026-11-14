;;;; src/update-shark.lisp -- the shark's hunt: steering toward the nearest
;;;; fish ahead, and what eating does to it (it grows, then leaves full).
;;;; The bite itself is the collision pass applying +SHARK-THREAT+.
(in-package #:cl-asciiquarium)

(defparameter +shark-sight-columns+ 45
  "How many empty columns ahead of its nose the shark notices a fish.")

(defparameter +shark-steer-rows-per-tick+ 0.25f0
  "How far the shark moves up or down toward its target each tick.")

(defparameter +shark-meals-to-grow+ 2)

(defparameter +shark-meals-to-fill+ 3)

(defparameter +shark-full-message+ "The shark is full and swims away")

(defun %shark-sight-distance (shark-left shark-width facing fish)
  "How many empty columns lie between the shark's nose and FISH when FISH
reaches past the nose in the FACING direction (0 when it overlaps the nose),
or NIL when FISH is level with or behind the nose."
  (multiple-value-bind (fish-left fish-top fish-width) (creature-bounds fish)
    (declare (ignore fish-top))
    (if (eq facing :left)
        (when (< fish-left shark-left)
          (max 0 (- shark-left (+ fish-left fish-width))))
        (let ((nose (+ shark-left shark-width)))
          (when (> (+ fish-left fish-width) nose)
            (max 0 (- fish-left nose)))))))

(defun shark-target (world shark)
  "The live fish nearest ahead of SHARK within +SHARK-SIGHT-COLUMNS+, or NIL.
A fish beside or behind the nose is ignored. Ties go to the earlier fish in
WORLD's creature list."
  (multiple-value-bind (shark-left shark-top shark-width) (creature-bounds shark)
    (declare (ignore shark-top))
    (let ((facing (creature-facing shark))
          (best nil)
          (best-distance (1+ +shark-sight-columns+)))
      (dolist (creature (world-%creatures world) best)
        (when (alive-fish-p creature)
          (let ((distance (%shark-sight-distance shark-left shark-width facing creature)))
            (when (and distance (< distance best-distance))
              (setf best creature
                    best-distance distance))))))))

(defun %steer-shark-toward (world shark fish)
  "Move SHARK's row at most +SHARK-STEER-ROWS-PER-TICK+ toward lining its
vertical center up with FISH's, staying inside the swim band."
  (let* ((shark-height (nth-value 1 (creature-dimensions shark)))
         (fish-height (nth-value 1 (creature-dimensions fish)))
         (y (creature-y shark))
         (gap (- (+ (creature-y fish) (* 0.5f0 fish-height))
                 (+ y (* 0.5f0 shark-height))))
         (step (clamp gap (- +shark-steer-rows-per-tick+) +shark-steer-rows-per-tick+)))
    (unless (zerop step)
      (multiple-value-bind (top bottom) (fish-swim-limits world shark-height)
        (setf (entity-y (creature-entity shark)) (clamp (+ y step) top bottom))))))

(defun shark-tick (world shark)
  "The shark's :TICK while it hunts: steer toward SHARK-TARGET."
  (let ((fish (shark-target world shark)))
    (when fish
      (%steer-shark-toward world shark fish))))

(defun grow-shark (shark)
  "Swap SHARK to +SHARK-BIG-ART+, keeping its center where it was. Both arts
are three rows tall, so only the column moves."
  (let ((old-width (creature-dimensions shark)))
    (%set-creature-frames shark (vector +shark-big-art+))
    (decf (entity-x (creature-entity shark))
          (* 0.5f0 (- (creature-dimensions shark) old-width)))))

(defun sate-shark (world shark)
  "SHARK stops hunting and steering, doubles its speed out of the screen, and
says so."
  (setf (getf (creature-data shark) :threat) nil
        (getf (creature-data shark) :tick) nil)
  (let ((entity (creature-entity shark)))
    (setf (entity-dx entity) (* 2 (entity-dx entity))))
  (world-notify world +shark-full-message+))

(defun shark-eat-effect (world shark fish)
  "The shark's :EFFECT: eat FISH, then grow at +SHARK-MEALS-TO-GROW+ meals and
leave full at +SHARK-MEALS-TO-FILL+."
  (eat-effect world shark fish)
  (let ((eaten (incf (getf (creature-data shark) :eaten))))
    (cond ((= eaten +shark-meals-to-grow+) (grow-shark shark))
          ((= eaten +shark-meals-to-fill+) (sate-shark world shark)))))
