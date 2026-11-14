;;;; src/update-fisher.lisp -- the fisher event's progress.
;;;;
;;;; The boat's data :PHASE runs :ARRIVE (sail in to :STOP-X), :LOWER (sink
;;;; the hook to :MAX-DEPTH), :WAIT (until :WAIT-UNTIL, an absolute tick),
;;;; :REEL (pull the hook back up), :CHEER (after a catch, until :WAIT-UNTIL),
;;;; and :LEAVE (sail on until the :DESPAWN policy removes the boat). :DEPTH is
;;;; the line's length in rows. The line and hook place themselves on their
;;;; own ticks from the boat's sway row (FISHER-BOAT-ROW), not its entity Y:
;;;; the storm sway (SWAY-BOATS) moves the boat, from its :BOAT-RISE, only
;;;; after every creature has ticked, so its Y would put them one tick behind.
(in-package #:cl-asciiquarium)

(defun fisher-boat-row (world boat)
  "BOAT's row on WORLD's current tick, where SWAY-BOATS puts it."
  (boat-sway-row world (getf (creature-data boat) :boat-rise)))

(defun hook-catch-effect (world hook fish)
  "The :EFFECT of a hook: CATCH-EFFECT on FISH, then disarm HOOK so one hook
holds one fish."
  (catch-effect world hook fish)
  (setf (getf (creature-data hook) :threat) nil))

(defun fisher-base-row (world boat)
  "BOAT's row on WORLD's current waterline with no storm sway."
  (max 0 (- (world-waterline-row world) (getf (creature-data boat) :boat-rise))))

(defun fishing-depth-limit (world boat row)
  "The deepest the line reaches from BOAT on ROW: the row above WORLD's current
sand, within the line frames the factory built (:MAX-DEPTH)."
  (max 1 (min (getf (creature-data boat) :max-depth)
              (- (world-sand-top world) row 2))))

(defun fishing-depth (world boat)
  "The line's drawn length in whole rows: :DEPTH, shortened while the storm
sway lifts the boat's row so the hook stays out of the sand. The line and hook
tick before the boat, so they also clamp after a resize themselves."
  (min (floor (getf (creature-data boat) :depth))
       (fishing-depth-limit world boat (fisher-boat-row world boat))))

(defun fishing-line-tick (world line)
  "The :TICK of a fishing line: hang from the rod tip, :DEPTH rows long."
  (let ((boat (getf (creature-data line) :boat)))
    (setf (entity-x (creature-entity line)) (fishing-line-x boat)
          (entity-y (creature-entity line)) (1+ (fisher-boat-row world boat))
          (creature-frame-index line) (1- (fishing-depth world boat)))))

(defun fishing-hook-tick (world hook)
  "The :TICK of a hook: hang just below the end of the line."
  (let ((boat (getf (creature-data hook) :boat)))
    (setf (entity-x (creature-entity hook)) (fishing-line-x boat)
          (entity-y (creature-entity hook))
          (+ 1 (fisher-boat-row world boat) (fishing-depth world boat)))))

(defun fisher-arrive-tick (world boat)
  (let* ((data (creature-data boat))
         (entity (creature-entity boat))
         ;; A resize during the approach may have narrowed the screen past
         ;; the column drawn at spawn.
         (stop-x (min (getf data :stop-x)
                      (- (world-width world) (creature-dimensions boat) 1))))
    (when (if (plusp (entity-dx entity))
              (>= (entity-x entity) stop-x)
              (<= (entity-x entity) stop-x))
      (setf (entity-x entity) stop-x
            (entity-dx entity) 0
            (getf data :phase) :lower)
      (let ((line (getf data :line))
            (hook (getf data :hook)))
        ;; Placed now: creatures added during a tick first tick on the next.
        (fishing-line-tick world line)
        (fishing-hook-tick world hook)
        (%add-fisher-part world line)
        (%add-fisher-part world hook)))))

(defun start-reeling (boat prey)
  (let ((data (creature-data boat)))
    (setf (getf data :phase) :reel
          (getf data :prey) prey
          (getf (creature-data (getf data :hook)) :threat) nil)))

(defun fisher-leave (boat)
  (setf (entity-dx (creature-entity boat))
        (if (eq (creature-facing boat) :right) +fisher-boat-speed+ (- +fisher-boat-speed+))
        (getf (creature-data boat) :phase) :leave))

(defun fisher-lower-tick (world boat)
  (let* ((data (creature-data boat))
         (depth (getf data :depth))
         (max-depth (fishing-depth-limit world boat (fisher-base-row world boat)))
         (prey (captured-fish world (getf data :hook))))
    (cond (prey (start-reeling boat prey))
          ((>= depth max-depth)
           (setf (getf data :phase) :wait
                 (getf data :wait-until) (+ (world-tick world) +fisher-wait-ticks+)))
          (t (setf (getf data :depth) (min max-depth (+ depth +fishing-line-speed+)))))))

(defun fisher-wait-tick (world boat)
  (let* ((data (creature-data boat))
         (prey (captured-fish world (getf data :hook))))
    (cond (prey (start-reeling boat prey))
          ((>= (world-tick world) (getf data :wait-until)) (start-reeling boat nil)))))

(defun land-fisher-catch (world boat prey)
  (let* ((data (creature-data boat))
         (cheer (getf data :cheer))
         (entity (creature-entity cheer)))
    (setf (creature-removep prey) t
          (entity-x entity) (+ (creature-x boat)
                               (if (eq (creature-facing boat) :right)
                                   +fisher-head-column+
                                   (- (creature-dimensions boat) 1 +fisher-head-column+)))
          ;; The cheer has no :TICK; its :BOAT-RISE lets the storm sway move it.
          (getf (creature-data cheer) :boat-rise) (1+ +fisher-boat-rise+)
          (entity-y entity) (boat-sway-row world (1+ +fisher-boat-rise+))
          (getf data :phase) :cheer
          (getf data :wait-until) (+ (world-tick world) +fisher-cheer-ticks+))
    (%add-fisher-part world cheer)))

(defun fisher-reel-tick (world boat)
  (let* ((data (creature-data boat))
         (depth (getf data :depth)))
    (if (> depth 1)
        (setf (getf data :depth) (max 1 (- depth +fishing-line-speed+)))
        (let ((prey (getf data :prey)))
          (setf (creature-removep (getf data :line)) t
                (creature-removep (getf data :hook)) t)
          (if prey
              (land-fisher-catch world boat prey)
              (fisher-leave boat))))))

(defun fisher-tick (world boat)
  "The :TICK of the fisher's boat: keep :DEPTH within FISHING-DEPTH-LIMIT of
its unswayed row, which a resize can lower, then advance its :PHASE. Its row
is SWAY-BOATS's."
  (let ((data (creature-data boat)))
    ;; The unswayed row, so a storm only shortens the drawn line
    ;; (FISHING-DEPTH), never the stored length it returns to.
    (setf (getf data :depth)
          (min (getf data :depth)
               (fishing-depth-limit world boat (fisher-base-row world boat))))
    (ecase (getf data :phase)
      (:arrive (fisher-arrive-tick world boat))
      (:lower (fisher-lower-tick world boat))
      (:wait (fisher-wait-tick world boat))
      (:reel (fisher-reel-tick world boat))
      (:cheer (when (>= (world-tick world) (getf data :wait-until))
                (fisher-leave boat)))
      (:leave nil))))
