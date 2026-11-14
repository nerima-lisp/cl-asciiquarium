;;;; src/update-anchor.lisp -- the ship's anchor: the ship stops, lowers the
;;;; anchor on a chain to the seabed, the anchor rests there eating fish, then
;;;; it is hauled up and the ship sails on.
(in-package #:cl-asciiquarium)

(defun maybe-drop-anchor (world ship)
  "The :TICK of a ship. Once SHIP reaches its scheduled :DROP-TICK, stop it
(MAKE-SHIP saved its DX in :SAVED-DX) and add its anchor and chain to WORLD.
Guarded by :ANCHOR-DROPPED so a ship drops at most one anchor."
  (let ((data (creature-data ship)))
    (when (and (not (getf data :anchor-dropped))
               (>= (world-tick world) (getf data :drop-tick)))
      (let ((entity (creature-entity ship))
            (anchor (make-anchor world ship)))
        (setf (getf data :anchor-dropped) t
              (entity-dx entity) 0)
        ;; The anchor goes in last so it sits ahead of its chain in the list:
        ;; it moves first each tick, and the chain then matches it in the
        ;; same tick instead of one tick behind.
        (%add-world-creature world (getf (creature-data anchor) :chain))
        (%add-world-creature world anchor)))))

(defun anchor-tick (world anchor)
  "Advance ANCHOR through its :PHASE, keeping it under its ship at its
:OFFSET-X. :FALL ends on the seabed, the lower of :TARGET-DEPTH and the row
above the sand of a screen resized smaller since: the anchor stops there and
arms +ANCHOR-THREAT+ until :RISE-AT, +ANCHOR-REST-TICKS+ later. A resize can
clamp a falling or resting anchor below that row, so it is moved back up to
it. :REST then disarms it and starts the climb at the falling speed. :RISE
ends at the waterline row, where the anchor leaves and its ship resumes its
:SAVED-DX."
  (let* ((data (creature-data anchor))
         (entity (creature-entity anchor))
         (ship (getf data :ship))
         (seabed (min (getf data :target-depth)
                     (- (world-sand-top world) (nth-value 1 (creature-dimensions anchor))))))
    (setf (entity-x entity) (+ (creature-x ship) (getf data :offset-x)))
    (case (getf data :phase)
      (:fall
       (when (>= (creature-y anchor) seabed)
         (setf (entity-y entity) seabed
               (entity-dy entity) 0
               (getf data :phase) :rest
               (getf data :rise-at) (+ (world-tick world) +anchor-rest-ticks+))
         (arm-threat world anchor +anchor-threat+)))
      (:rest
       (when (> (creature-y anchor) seabed)
         (setf (entity-y entity) seabed))
       (when (>= (world-tick world) (getf data :rise-at))
         (setf (getf data :threat) nil
               (getf data :phase) :rise
               (entity-dy entity) (- +anchor-speed+))))
      (:rise
       (when (<= (creature-y anchor) (world-waterline-row world))
         (setf (creature-removep anchor) t
               (entity-dx (creature-entity ship)) (getf (creature-data ship) :saved-dx)))))))

(defun chain-tick (world chain)
  "The :TICK of an anchor chain: hang from the row under its anchor's ship in
the anchor's shaft column, show the frame whose length reaches down to the row
above the anchor, and leave together with the anchor. The length stays within
the frames built for the fall: the anchor never sinks below :TARGET-DEPTH, and a
resize clamps the ship up only on a screen whose sand lies above the ship's
bottom row, which leaves no room for a chain."
  (declare (ignore world))
  (let* ((data (creature-data chain))
         (anchor (getf data :anchor))
         (entity (creature-entity chain)))
    (if (creature-removep anchor)
        (setf (creature-removep chain) t)
        (let ((top (+ (creature-y (getf (creature-data anchor) :ship))
                      (getf data :ship-height))))
          (setf (entity-x entity) (+ (creature-x anchor) (getf data :shaft-x))
                (entity-y entity) top
                (creature-frame-index chain) (max 0 (- (creature-y anchor) top)))))))
