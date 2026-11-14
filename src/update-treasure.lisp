;;;; src/update-treasure.lisp -- the chest opening and closing, the coins'
;;;; arcs, and the dive: the dinghy's phases, with the rope and the diver
;;;; following it.
(in-package #:cl-asciiquarium)

(defparameter +chest-open-ticks+ 45)

(defparameter +chest-reopen-range+ '(380 520)
  "Ticks from one closing to the next opening, inclusive.")

(defparameter +chest-bubble-count+ 8)

(defparameter +chest-coin-count+ 6)

(defparameter +chest-empty-ticks+ 700
  "Ticks the chest stays shut after the diver takes its gold.")

(defparameter +diver-rows-per-tick+ 0.25f0)

(defparameter +diver-grab-ticks+ 20
  "Ticks the diver spends beside the chest taking the coin.")

(defparameter +diver-bubble-period+ 8
  "The diver breathes out a bubble on every tick divisible by this while
going down.")

(defun %switch-chest-art (chest frames masks)
  "Show FRAMES and MASKS on CHEST, keeping its bottom row where it was. The
role styles stay: the chest's roles (data :ROLES) cover both arts."
  (let ((old-height (nth-value 1 (creature-dimensions chest))))
    (%set-creature-frames chest frames :masks masks
                                       :role-styles (creature-%role-styles chest))
    (decf (entity-y (creature-entity chest))
          (- (nth-value 1 (creature-dimensions chest)) old-height))))

(defun open-chest (world chest)
  "Raise CHEST's lid for +CHEST-OPEN-TICKS+, releasing bubbles and coins."
  (let ((data (creature-data chest)))
    (%switch-chest-art chest +chest-open-frames+ +chest-open-masks+)
    (setf (getf data :state) :open
          (getf data :close-at) (+ (world-tick world) +chest-open-ticks+))
    (dotimes (i +chest-bubble-count+)
      (%add-world-creature world (make-bubble world chest)))
    (dotimes (index +chest-coin-count+)
      (%add-world-creature world (make-coin world chest index)))))

(defun close-chest (world chest)
  "Shut CHEST's lid and schedule its next opening."
  (let ((data (creature-data chest)))
    (%switch-chest-art chest +chest-closed-frames+ +chest-closed-masks+)
    (setf (getf data :state) :closed
          (getf data :next-at) (+ (world-tick world)
                                  (apply #'random-between +chest-reopen-range+)))))

(defun empty-chest (world chest)
  "The diver takes CHEST's gold: shut it if open and keep it shut for
+CHEST-EMPTY-TICKS+. Overriding the :NEXT-AT that CLOSE-CHEST just set only
delays the opening, as every :NEXT-AT a closed chest holds is at most the top
of +CHEST-REOPEN-RANGE+ away."
  (when (eq (getf (creature-data chest) :state) :open)
    (close-chest world chest))
  (setf (getf (creature-data chest) :next-at)
        (+ (world-tick world) +chest-empty-ticks+)))

(defun chest-tick (world chest)
  "The chest's :TICK: open once :NEXT-AT is due, and close after
+CHEST-OPEN-TICKS+."
  (let ((data (creature-data chest))
        (tick (world-tick world)))
    (if (eq (getf data :state) :open)
        (when (>= tick (getf data :close-at))
          (close-chest world chest))
        (when (>= tick (getf data :next-at))
          (open-chest world chest)))))

(defun coin-tick (world coin)
  "A coin's :TICK: gravity turns its rise into a fall; it is gone once it
falls back to the chest's top row."
  (declare (ignore world))
  (let ((entity (creature-entity coin)))
    (incf (entity-dy entity) +coin-gravity+)
    (when (and (plusp (entity-dy entity))
               (>= (entity-y entity) (getf (creature-data coin) :floor)))
      (setf (creature-removep coin) t))))

(defun dinghy-tick (world dinghy)
  "The dinghy's :TICK, through its :PHASE: :ARRIVE until it reaches :STOP-X,
:DESCEND while the diver climbs down (breathing bubbles) to the chest's
bottom row, :GRAB while the diver empties the chest, :ASCEND back up, and
:LEAVE, sailing on until it despawns past the far edge. A chest that leaves
mid-descent (a resize) sends the diver up empty-handed."
  (let* ((data (creature-data dinghy))
         (entity (creature-entity dinghy))
         (chest (getf data :chest)))
    (ecase (getf data :phase)
      (:arrive
       (when (if (eq (creature-facing dinghy) :right)
                 (>= (creature-x dinghy) (getf data :stop-x))
                 (<= (creature-x dinghy) (getf data :stop-x)))
         (setf (entity-x entity) (getf data :stop-x)
               (entity-dx entity) 0
               (getf data :phase) :descend)))
      (:descend
       (cond ((creature-removep chest)
              (setf (getf data :phase) :ascend))
             ((>= (getf data :depth) (getf data :max-depth))
              (empty-chest world chest)
              (setf (getf data :phase) :grab
                    (getf data :carrying) t
                    (getf data :grab-until) (+ (world-tick world) +diver-grab-ticks+)))
             (t
              (setf (getf data :depth) (min (getf data :max-depth)
                                            (+ (getf data :depth) +diver-rows-per-tick+)))
              (when (zerop (mod (world-tick world) +diver-bubble-period+))
                (%add-world-creature world (make-bubble world (getf data :diver)))))))
      (:grab
       (when (>= (world-tick world) (getf data :grab-until))
         (setf (getf data :phase) :ascend)))
      (:ascend
       (if (plusp (getf data :depth))
           (setf (getf data :depth) (max 0 (- (getf data :depth) +diver-rows-per-tick+)))
           (setf (getf data :phase) :leave
                 (entity-dx entity) (getf data :dx))))
      (:leave))))

(defun %follow-dinghy (follower column)
  "Put FOLLOWER at the dinghy's COLUMN just under its hull, or mark it
REMOVEP once the dinghy is gone. Returns the dinghy while it remains."
  (let ((dinghy (getf (creature-data follower) :leader))
        (entity (creature-entity follower)))
    (if (creature-removep dinghy)
        (progn (setf (creature-removep follower) t) nil)
        (progn (setf (entity-x entity) (+ (creature-x dinghy) column)
                     (entity-y entity) (+ (creature-y dinghy) 2))
               dinghy))))

(defun rope-tick (world rope)
  "The rope's :TICK: hang from the dinghy, as long as the diver is deep."
  (declare (ignore world))
  (let ((dinghy (%follow-dinghy rope +diver-rope-column+)))
    (when dinghy
      (setf (creature-frame-index rope)
            (floor (getf (creature-data dinghy) :depth))))))

(defun diver-tick (world diver)
  "The diver's :TICK: hang under the rope, hidden in the dinghy while it
sails, carrying the coin on the way up."
  (declare (ignore world))
  (let ((dinghy (%follow-dinghy diver (1- +diver-rope-column+))))
    (when dinghy
      (let ((data (creature-data dinghy)))
        (incf (entity-y (creature-entity diver)) (floor (getf data :depth)))
        (setf (creature-frame-index diver)
              (case (getf data :phase)
                ((:arrive :leave) 0)
                (:ascend (if (getf data :carrying) 2 1))
                (t 1)))))))
