;;;; src/spawn.lisp -- periodic spawning: the shark, special guests, and the
;;;; bubble trail each fish periodically emits. Every spawn decision reads
;;;; only the ambient CL:*RANDOM-STATE* (via RANDOM-BETWEEN in art-fish.lisp),
;;;; never a private generator, so binding *RANDOM-STATE* (e.g. via
;;;; SB-EXT:SEED-RANDOM-STATE) makes every spawn in this file deterministic
;;;; for tests.
(in-package #:cl-asciiquarium)

(defparameter +bubble-interval-range+ '(20 60))

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
it reaches zero."
  (decf (world-guest-cooldown world))
  (when (<= (world-guest-cooldown world) 0)
    (spawn-guest-now world (random-guest-kind))
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
