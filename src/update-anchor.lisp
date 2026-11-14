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

(defun anchor-seabed (world anchor)
  "The row ANCHOR's top rests on when landed: the lower of its :TARGET-DEPTH
and the row above the sand of a screen resized smaller since."
  (min (getf (creature-data anchor) :target-depth)
       (- (world-sand-top world) (nth-value 1 (creature-dimensions anchor)))))

(defun place-anchor (world anchor)
  "The :PLACE of an anchor: put it under its ship at its :OFFSET-X and, while
it falls or rests, no lower than ANCHOR-SEABED, where a resize may have
clamped it."
  (let ((data (creature-data anchor))
        (entity (creature-entity anchor)))
    (setf (entity-x entity) (+ (creature-x (getf data :ship)) (getf data :offset-x)))
    (unless (eq (getf data :phase) :rise)
      (let ((seabed (anchor-seabed world anchor)))
        (when (> (creature-y anchor) seabed)
          (setf (entity-y entity) seabed))))))

(defun anchor-tick (world anchor)
  "Advance ANCHOR through its :PHASE after PLACE-ANCHOR. :FALL ends on
ANCHOR-SEABED: the anchor stops there and arms +ANCHOR-THREAT+ until :RISE-AT,
+ANCHOR-REST-TICKS+ later. :REST then disarms it and starts the climb at the
falling speed. :RISE ends at the waterline row, where the anchor leaves and its
ship resumes its :SAVED-DX."
  (place-anchor world anchor)
  (let ((data (creature-data anchor))
        (entity (creature-entity anchor)))
    (case (getf data :phase)
      (:fall
       (let ((seabed (anchor-seabed world anchor)))
         (when (>= (creature-y anchor) seabed)
           (setf (entity-y entity) seabed
                 (entity-dy entity) 0
                 (getf data :phase) :rest
                 (getf data :rise-at) (+ (world-tick world) +anchor-rest-ticks+))
           (arm-threat world anchor +anchor-threat+))))
      (:rest
       (when (>= (world-tick world) (getf data :rise-at))
         (setf (getf data :threat) nil
               (getf data :phase) :rise
               (entity-dy entity) (- +anchor-speed+))))
      (:rise
       (when (<= (creature-y anchor) (world-waterline-row world))
         (setf (creature-removep anchor) t
               (entity-dx (creature-entity (getf data :ship)))
               (getf (creature-data (getf data :ship)) :saved-dx)))))))

(defun %set-chain-length (chain length reach)
  "Show LENGTH links of CHAIN. Its frames go up to the longest length it has
been able to reach; REACH, the length at the anchor's seabed, outgrows them
only when a resize has moved the ship up, so they are rebuilt then."
  (when (>= reach (length (creature-%frames chain)))
    (%set-creature-frames chain (vertical-line-frames +chain-glyph+ reach)))
  (setf (creature-frame-index chain) length))

(defun place-chain (world chain)
  "The :PLACE of an anchor chain: hang from the row under its anchor's ship in
the anchor's shaft column, reaching down to the row above the anchor. The
anchor precedes its chain in the creature list (MAYBE-DROP-ANCHOR), so it has
already been placed."
  (let* ((data (creature-data chain))
         (anchor (getf data :anchor))
         (entity (creature-entity chain))
         (top (+ (creature-y (getf (creature-data anchor) :ship))
                 (getf data :ship-height))))
    (setf (entity-x entity) (+ (creature-x anchor) (getf data :shaft-x))
          (entity-y entity) top)
    (%set-chain-length chain
                       (max 0 (- (creature-y anchor) top))
                       (max 0 (- (max (creature-y anchor) (anchor-seabed world anchor)) top)))))

(defun chain-tick (world chain)
  "The :TICK of an anchor chain: PLACE-CHAIN, and leave together with the
anchor."
  (if (creature-removep (getf (creature-data chain) :anchor))
      (setf (creature-removep chain) t)
      (place-chain world chain)))
