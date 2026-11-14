;;;; src/update-anchor.lisp -- the ship's anchor: the ship stops, lowers the
;;;; anchor on a chain to the seabed, the anchor rests there eating fish, then
;;;; it is hauled up and the ship sails on.
(in-package #:cl-asciiquarium)

(defun maybe-drop-anchor (world ship)
  "The :TICK of a ship. Once SHIP reaches its scheduled :DROP-TICK, stop it,
saving its DX in :SAVED-DX, and add its anchor and chain to WORLD. Guarded by
:ANCHOR-DROPPED so a ship drops at most one anchor."
  (let ((data (creature-data ship)))
    (when (and (not (getf data :anchor-dropped))
               (>= (world-tick world) (getf data :drop-tick)))
      (let ((entity (creature-entity ship))
            (anchor (make-anchor world ship)))
        (setf (getf data :anchor-dropped) t
              (getf data :saved-dx) (entity-dx entity)
              (entity-dx entity) 0)
        ;; The anchor goes in last so it sits ahead of its chain in the list:
        ;; it moves first each tick, and the chain then matches it in the
        ;; same tick instead of one tick behind.
        (%add-world-creature world (getf (creature-data anchor) :chain))
        (%add-world-creature world anchor)))))

(defun anchor-tick (world anchor)
  "Advance ANCHOR through its :PHASE. :FALL ends on the seabed (:TARGET-DEPTH):
the anchor stops and arms +ANCHOR-THREAT+ until :RISE-AT, +ANCHOR-REST-TICKS+
later. :REST then disarms it and starts the climb at the falling speed. :RISE
ends at the waterline row, where the anchor leaves and its ship resumes its
:SAVED-DX."
  (let ((data (creature-data anchor))
        (entity (creature-entity anchor)))
    (case (getf data :phase)
      (:fall
       (when (>= (creature-y anchor) (getf data :target-depth))
         (setf (entity-dy entity) 0
               (getf data :phase) :rest
               (getf data :rise-at) (+ (world-tick world) +anchor-rest-ticks+))
         (arm-threat world anchor +anchor-threat+)))
      (:rest
       (when (>= (world-tick world) (getf data :rise-at))
         (setf (getf data :threat) nil
               (getf data :phase) :rise
               (entity-dy entity) (- +anchor-speed+))))
      (:rise
       (when (<= (creature-y anchor) (world-waterline-row world))
         (let ((ship (getf data :ship)))
           (setf (creature-removep anchor) t
                 (entity-dx (creature-entity ship)) (getf (creature-data ship) :saved-dx))))))))

(defun chain-tick (world chain)
  "The :TICK of an anchor chain: show the frame whose length spans :TOP down
to the row above its :ANCHOR, and leave together with the anchor."
  (declare (ignore world))
  (let* ((data (creature-data chain))
         (anchor (getf data :anchor)))
    (if (creature-removep anchor)
        (setf (creature-removep chain) t)
        (setf (creature-frame-index chain)
              (max 0 (- (creature-y anchor) (getf data :top)))))))
