;;;; src/update-submarine.lisp -- the submarine's sonar and what a ring does to
;;;; a fish: it stops for +STUN-TICKS+ under a `!', then swims on.
;;;;
;;;; A stun only zeroes the fish's own DX. School members are not stunned:
;;;; SCHOOL-TICK and SCHOOL-SCATTER rewrite their velocity and position, so a
;;;; zeroed DX would not hold and the saved one would be stale when restored.
;;;; Every ring is centred on its submarine, well inside +SCHOOL-SENSE+'s
;;;; range of it, so a school a ring reaches is already scattering. A lured
;;;; fish is stunned but the lantern keeps pulling it (LANTERN-PULL moves its
;;;; position, not its DX).
(in-package #:cl-asciiquarium)

(defparameter +stun-ticks+ 25
  "Ticks a fish stays stopped after a sonar ring reaches it.")

(defun sub-tick (world sub)
  "The submarine's :TICK: emit a sonar ring every +SONAR-INTERVAL-TICKS+."
  (let ((data (creature-data sub)))
    (when (>= (world-tick world) (getf data :sonar-next))
      (incf (getf data :sonar-next) +sonar-interval-ticks+)
      (%add-world-creature world (make-sonar-ring world sub)))))

(defun sonar-tick (world ring)
  "The sonar ring's :TICK: keep the widened frame centred on the emission
point."
  (declare (ignore world))
  (if (creature-removep ring)
      ;; The TTL ran out on the tick the animation wrapped to the narrowest
      ;; frame; that frame must not stun during this tick's collision pass.
      (setf (getf (creature-data ring) :threat) nil)
      (%centre-sonar-ring ring)))

(defun place-stun-mark (mark fish)
  "Put MARK on the row above FISH's head, the front column in its facing."
  (let ((entity (creature-entity mark)))
    (setf (entity-x entity) (if (eq (creature-facing fish) :right)
                                (+ (creature-x fish) (1- (creature-dimensions fish)))
                                (creature-x fish))
          (entity-y entity) (1- (creature-y fish)))))

(defun stun-effect (world ring fish)
  "+SONAR-THREAT+'s :EFFECT: stop FISH for +STUN-TICKS+, saving its DX, and
show a `!' over it. A fish already stunned, or swimming in a school, is left
alone. The stun keys are added to FISH's data the first time; this is a rare
event, and later stuns reuse them."
  (declare (ignore ring))
  (let ((tick (world-tick world))
        (data (creature-data fish)))
    (unless (or (getf data :leader)
                (< tick (getf data :stunned-until 0)))
      (let ((entity (creature-entity fish))
            (mark (make-stun-mark world fish)))
        (setf (getf (creature-data fish) :saved-dx) (entity-dx entity)
              (getf (creature-data fish) :stunned-until) (+ tick +stun-ticks+)
              (entity-dx entity) 0)
        (place-stun-mark mark fish)
        (%add-world-creature world mark)))))

(defun end-stun (fish)
  "Give FISH back its saved DX, facing the way it swims (a lantern may have
turned it while it was stopped)."
  (let ((dx (getf (creature-data fish) :saved-dx)))
    (setf (entity-dx (creature-entity fish)) dx
          (creature-facing fish) (if (minusp dx) :left :right))))

(defun stun-mark-tick (world mark)
  "The `!' mark's :TICK: follow its fish, end the stun when it is due, and
leave with the fish if it stops being alive."
  (let ((fish (getf (creature-data mark) :fish)))
    (cond ((not (alive-fish-p fish))
           (setf (creature-removep mark) t))
          ((>= (world-tick world) (getf (creature-data fish) :stunned-until))
           (end-stun fish)
           (setf (creature-removep mark) t))
          (t (place-stun-mark mark fish)))))
