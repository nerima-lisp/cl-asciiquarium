;;;; src/spawn.lisp -- periodic spawning: the shark, special guests, the
;;;; bubble trail each fish periodically emits, refills for fish taken out of
;;;; play, and the automatic event table. Every spawn decision reads only
;;;; the ambient CL:*RANDOM-STATE* (via RANDOM-BETWEEN in geometry.lisp),
;;;; never a private generator, so binding *RANDOM-STATE* (e.g. via
;;;; SB-EXT:SEED-RANDOM-STATE) makes every spawn in this file deterministic
;;;; for tests.
(in-package #:cl-asciiquarium)

(defparameter +bubble-interval-range+ '(20 60))

(defparameter +refill-delay-ticks+ 90
  "Ticks between a fish leaving play (eaten or caught) and a replacement
swimming in from the screen edge. Fixed, so scheduling draws no random number.")

(defun schedule-fish-refill (world)
  "Schedule a refill +REFILL-DELAY-TICKS+ from now unless one is already
pending. Called by every effect that takes a fish out of play."
  (when (zerop (world-refill-at world))
    (setf (world-refill-at world) (+ (world-tick world) +refill-delay-ticks+))))

(defparameter +big-event-kinds+ '(:ship
                                   :sub
                                   :dinghy)
  "The CREATURE-KIND of each big event's lead creature. At most
+MAX-BIG-EVENTS+ of them may be on screen before the automatic paths
(MAYBE-SPAWN-GUEST, ADVANCE-WORLD-EVENTS) hold back; keys spawn regardless.")

(defparameter +max-big-events+ 2)

(defvar *auto-events*
  '((:id :school :big nil :every (900 1600) :first 600 :spawn spawn-school-if-room))
  "The automatic events ADVANCE-WORLD-EVENTS runs, one plist row each:
(:ID keyword :BIG boolean :EVERY (low high) :FIRST ticks :SPAWN symbol).
:SPAWN names a (WORLD) function. :FIRST is the fixed tick of the first
occurrence, so building a world draws no random number for it; each
occurrence then schedules the next one :EVERY ticks later. A :BIG row is
skipped, and rescheduled, while +MAX-BIG-EVENTS+ big events are on screen.
WORLD-EVENT-DUE holds each row's next tick, in the same order; MAKE-WORLD sizes
it from this list, so bind it before creating the world.")

(defun school-room-p (world)
  "True when a whole school (one fish per +SCHOOL-OFFSETS+ slot) fits under
WORLD-MAX-FISH alongside the live fish already present."
  (<= (+ (count-if #'alive-fish-p (world-%creatures world)) (length +school-offsets+))
      (world-max-fish world)))

(defun spawn-school-if-room (world)
  "Spawn a school (SPAWN-SCHOOL-NOW, art-school.lisp) when SCHOOL-ROOM-P, and
return true; otherwise spawn nothing and return NIL."
  (when (school-room-p world)
    (spawn-school-now world)
    t))

(defun make-event-due-vector ()
  "A fresh WORLD-EVENT-DUE for *AUTO-EVENTS*: each row's :FIRST tick."
  (map 'simple-vector (lambda (row) (getf row :first)) *auto-events*))

(defun big-event-count (world)
  "How many big-event lead creatures (+BIG-EVENT-KINDS+) WORLD holds."
  (loop for creature in (world-%creatures world)
        count (member (creature-kind creature) +big-event-kinds+ :test #'eq)))

(defun big-event-room-p (world)
  (< (big-event-count world) +max-big-events+))

(defun find-creature-of-kind (world kind)
  "The first creature of KIND in WORLD that is not marked REMOVEP, or NIL."
  (find-if (lambda (creature)
             (and (eq (creature-kind creature) kind)
                  (not (creature-removep creature))))
           (world-%creatures world)))

(defun seabed-life (world ornaments)
  "Return the seabed ORNAMENTS (MAKE-SEABED-ORNAMENTS, art-decor.lisp) plus the
resident creatures that live on them, arming each ornament that animates.
Called while the background is built, so it draws no random number."
  (let ((life '()))
    (dolist (ornament ornaments)
      (case (creature-kind ornament)
        (:chest (arm-chest world ornament))
        (:vent (let ((plume (make-vent-plume world ornament)))
                 (when plume (push plume life))))))
    (let ((crab (make-crab world)))
      (when crab (push crab life)))
    (append ornaments life)))

(defun make-edge-fish (world)
  "A random fish entering at the screen edge it swims away from: column 0
facing right, or flush with the right edge facing left."
  (let* ((facing (random-facing))
         (fish (make-fish world :x 0 :facing facing)))
    (when (eq facing :left)
      (setf (entity-x (creature-entity fish))
            (max 0 (- (world-width world) (creature-dimensions fish)))))
    fish))

(defun maybe-refill-fish (world)
  "Once WORLD's pending refill is due, add one edge fish when fewer live fish
than WORLD-FISH-COUNT remain, and schedule the next refill only while the
population is still short. The shortfall is counted at this moment, so a
lowered target or extra fish need no bookkeeping."
  (let ((due (world-refill-at world))
        (tick (world-tick world)))
    (when (and (plusp due) (>= tick due))
      (let ((live (count-if #'alive-fish-p (world-%creatures world)))
            (target (world-fish-count world)))
        (when (< live target)
          (%add-world-creature world (make-edge-fish world)))
        (setf (world-refill-at world)
              (if (< (1+ live) target) (+ tick +refill-delay-ticks+) 0))))))

(defparameter +courting-interval-ticks+ 50
  "How often ADVANCE-WORLD-EVENTS picks a fish to court (SELECT-COURTING-FISH,
update-brood.lisp). Each pick retires the previous one's courting row, so this
is also how long a fish courts.")

(defun advance-world-events (world)
  "Run WORLD's per-tick event bookkeeping: a due refill, every due row of
*AUTO-EVENTS*, then, every +COURTING-INTERVAL-TICKS+ ticks, the pick of a
courting fish. Called by WORLD-ADVANCE after the automatic shark and guest
spawns."
  (maybe-refill-fish world)
  (let ((tick (world-tick world))
        (due (world-event-due world)))
    (loop for row in *auto-events*
          for index of-type fixnum from 0
          when (>= tick (svref due index))
            do (when (or (not (getf row :big)) (big-event-room-p world))
                 (funcall (getf row :spawn) world))
               (setf (svref due index)
                     (+ tick (apply #'random-between (getf row :every)))))
    (when (zerop (mod tick +courting-interval-ticks+))
      (select-courting-fish world)))
  world)

(defun spawn-shark-now (world)
  "Create a shark and push it into WORLD immediately, resetting the shark
cooldown, without regard to how much of it was left or to SHARK-ENABLED-P.
Shared by MAYBE-SPAWN-SHARK (the automatic cooldown path) and the `s' key's
manual spawn (input.lisp), which is why the immediate-spawn action is its own
function rather than inlined into MAYBE-SPAWN-SHARK."
  (%add-world-creature world (make-shark world))
  (setf (world-shark-cooldown world) (apply #'random-between +shark-cooldown-range+)))

(defun maybe-spawn-shark (world)
  "Count WORLD's shark cooldown down by one tick; spawn a shark and reset the
cooldown once it reaches zero. A no-op for the life of WORLD when
WORLD-SHARK-ENABLED-P is false (the --no-shark CLI flag; see cli.lisp and
app.lisp), including the cooldown countdown itself, so the cooldown cannot
wander arbitrarily negative over a long disabled run."
  (when (world-shark-enabled-p world)
    (decf (world-shark-cooldown world))
    (when (<= (world-shark-cooldown world) 0)
      (spawn-shark-now world))))

(defun random-guest-kind ()
  "Return :SHIP, :DUCK-LINE, :DOLPHIN, or :SEA-MONSTER with equal
probability."
  (nth (random 4) '(:ship :duck-line :dolphin :sea-monster)))

(defun spawn-guest-now (world kind)
  "Create and push into WORLD the CREATURE(s) for guest KIND (:SHIP,
:DUCK-LINE, :DOLPHIN, or :SEA-MONSTER) immediately. Every kind but
:SEA-MONSTER pushes exactly one CREATURE; :SEA-MONSTER also pushes its
trailing segments (see MAKE-SEA-MONSTER and SEA-MONSTER-SEGMENTS,
art-guests.lisp), which is why this is a statement-oriented helper rather than
a single expression MAYBE-SPAWN-GUEST could just PUSH the result of, the way
MAYBE-SPAWN-SHARK does for MAKE-SHARK. Shared by MAYBE-SPAWN-GUEST (the
automatic cooldown path) and the `g' key's manual spawn (input.lisp)."
  (ecase kind
    (:ship (%add-world-creature world (make-ship world)))
    (:duck-line (%add-world-creature world (make-duck-line world)))
    (:dolphin (%add-world-creature world (make-dolphin world)))
    (:sea-monster
     (let ((leader (make-sea-monster world)))
       (%add-world-creature world leader)
       (dolist (segment (sea-monster-segments world leader))
         (%add-world-creature world segment))))))

(defun maybe-spawn-guest (world)
  "Count WORLD's guest cooldown down by one tick; spawn a random special
guest (see RANDOM-GUEST-KIND and SPAWN-GUEST-NOW) and reset the cooldown once
it reaches zero. A drawn guest that is a big event (+BIG-EVENT-KINDS+) is
skipped while +MAX-BIG-EVENTS+ are already on screen; the kind and cooldown
draws happen either way."
  (decf (world-guest-cooldown world))
  (when (<= (world-guest-cooldown world) 0)
    (let ((kind (random-guest-kind)))
      (when (or (not (member kind +big-event-kinds+ :test #'eq))
                (big-event-room-p world))
        (spawn-guest-now world kind)))
    (setf (world-guest-cooldown world) (apply #'random-between +guest-cooldown-range+))))

(defun maybe-emit-bubble (world fish)
  "Count FISH's per-fish bubble timer (stored in its :BUBBLE-TIMER data entry)
down by one tick; emit a bubble from FISH's position and reset the timer once
it reaches zero."
  (let ((timer (1- (getf (creature-data fish) :bubble-timer))))
    (if (<= timer 0)
        (progn
          (%add-world-creature world (make-bubble world fish))
          (setf (getf (creature-data fish) :bubble-timer)
                (apply #'random-between +bubble-interval-range+)))
        (setf (getf (creature-data fish) :bubble-timer) timer))))
