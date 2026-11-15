;;;; src/update-submarine.lisp -- the submarine's sonar and what a ring does to
;;;; a fish: it stands still for +STUN-TICKS+ under a `!', then swims on.
;;;;
;;;; A stun zeroes the fish's DX and DY. It also stops school members, and
;;;; takes precedence over the school: while a member is stunned, SCHOOL-SCATTER
;;;; and SCHOOL-TICK leave its velocity and position alone (update-school.lisp).
;;;; When the stun ends, a member takes the velocity of the school's state at
;;;; that moment and SCHOOL-TICK pulls it back to its slot; any other fish gets
;;;; its saved velocity back. A lured fish is stunned but the lantern keeps
;;;; pulling it (LANTERN-PULL moves its position, not its velocity). The `!' is
;;;; attached to its fish (ATTACH-CREATURE), so it leaves whenever the fish
;;;; leaves play.
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

(defun fish-stunned-p (world fish)
  (< (world-tick world) (getf (creature-data fish) :stunned-until 0)))

(defun stun-effect (world ring fish)
  "+SONAR-THREAT+'s :EFFECT: stop FISH for +STUN-TICKS+, saving its velocity,
and show a `!' over it. A fish already stunned is left alone. The stun keys
are added to FISH's data the first time; this is a rare event, and later
stuns reuse them."
  (declare (ignore ring))
  (unless (fish-stunned-p world fish)
    (let ((data (creature-data fish))
          (entity (creature-entity fish))
          (mark (make-stun-mark world fish)))
      (setf (getf data :saved-dx) (entity-dx entity)
            (getf data :saved-dy) (entity-dy entity)
            (getf data :stunned-until) (+ (world-tick world) +stun-ticks+)
            (creature-data fish) data
            (entity-dx entity) 0
            (entity-dy entity) 0)
      (place-stun-mark mark fish)
      (attach-creature world fish mark))))

(defun end-stun (fish)
  "Set FISH swimming again, facing the way it swims (a lantern may have turned
it while it was stopped): a school member at the velocity of its school's
current state, any other fish at its saved velocity."
  (let ((data (creature-data fish))
        (entity (creature-entity fish)))
    (cond ((not (getf data :leader))
           (setf (entity-dx entity) (getf data :saved-dx)
                 (entity-dy entity) (getf data :saved-dy)))
          ((plusp (getf data :scatter-until))
           (setf (entity-dx entity) (+ (getf data :school-dx) (getf data :scatter-dx))
                 (entity-dy entity) (getf data :scatter-dy)))
          (t
           (setf (entity-dx entity) (getf data :school-dx)
                 (entity-dy entity) 0)))
    (setf (creature-facing fish) (if (minusp (entity-dx entity)) :left :right))))

(defun stun-mark-tick (world mark)
  "The `!' mark's :TICK: follow its fish and end the stun when it is due."
  (let ((fish (getf (creature-data mark) :fish)))
    (cond ((>= (world-tick world) (getf (creature-data fish) :stunned-until))
           (end-stun fish)
           (setf (creature-removep mark) t))
          (t (place-stun-mark mark fish)))))
