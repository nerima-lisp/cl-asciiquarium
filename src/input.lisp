;;;; src/input.lisp -- turning decoded cl-tty-kit KEY-EVENTs into WORLD state
;;;; changes: `q' to quit, `r' to redraw/reshuffle, space to pause/resume,
;;;; `+'/`-' to adjust the live fish count, `s'/`g'/`c'/`a'/`m'/`d' to force an
;;;; immediate shark/guest/school/ship/submarine/diver spawn, `t' to cycle the
;;;; visual theme, `u' to toggle the HUD, and `h' to toggle the on-screen help
;;;; panel.
(in-package #:cl-asciiquarium)

(defparameter +quit-characters+ (list #\q #\Q)
  "Characters that set WORLD-QUITP on a decoded :CHARACTER event, by
application convention (q/Q). Ctrl-C is matched separately, on the decoded
event's type rather than a character: raw mode clears ISIG (see
cl-tty-kit's raw-mode-sbcl.lisp), so cl-tty-kit's decoder reports Ctrl-C as
a :SPECIAL event with code :CONTROL-C -- see +CONTROL-LETTER-EVENTS+ in
cl-tty-kit's key-tables.lisp -- rather than as a :CHARACTER event or a raw
byte this file would have to inspect itself.")

(defun quit-key-event-p (event)
  "True when decoded cl-tty-kit KEY-EVENT should set WORLD-QUITP: a
:CHARACTER event whose code is a member of +QUIT-CHARACTERS+, or the
:SPECIAL :CONTROL-C event Ctrl-C decodes to."
  (or (and (eq (key-event-type event) :character)
           (member (key-event-code event) +quit-characters+ :test #'char=))
      (and (eq (key-event-type event) :special)
           (eq (key-event-code event) :control-c))))

(defun world-toggle-help-overlay (world)
  "Add WORLD's :HELP-OVERLAY CREATURE (see MAKE-HELP-OVERLAY, art-decor.lisp)
if none is present, or remove it if one already is, returning WORLD. Bound to
the `h` key."
  (if (find :help-overlay (world-%creatures world) :key #'creature-kind)
      (%set-world-creatures
       world
       (remove :help-overlay (world-%creatures world) :key #'creature-kind))
      (%add-world-creature world (make-help-overlay world)))
  world)

(defun character-key-event-p (event code)
  "True when decoded cl-tty-kit KEY-EVENT is a :CHARACTER event whose code is
CODE, case-sensitively -- the shape every single-letter binding below shares,
factored out so each binding states only which character it cares about."
  (and (eq (key-event-type event) :character) (char= (key-event-code event) code)))

(defun world-toggle-pause (world)
  "Toggle WORLD-PAUSED-P, returning WORLD. Bound to the space key."
  (setf (world-paused-p world) (not (world-paused-p world)))
  (world-refresh-hud world)
  world)

(defun world-spawn-random-guest (world)
  "Force-spawn a random special guest in WORLD immediately, returning WORLD.
Bound to the `g' key; see RANDOM-GUEST-KIND and SPAWN-GUEST-NOW, spawn.lisp."
  (spawn-guest-now world (random-guest-kind))
  world)

(defparameter +school-no-room-message+ "The tank is too full for a school")

(defun world-spawn-school (world)
  "Spawn a school of fish in WORLD immediately when it fits under
WORLD-MAX-FISH (SPAWN-SCHOOL-IF-ROOM, spawn.lisp), or say why not in the status
bar, returning WORLD. Bound to the `c' key."
  (unless (spawn-school-if-room world)
    (world-notify world +school-no-room-message+))
  world)

(defun world-spawn-ship (world)
  "Spawn a ship that stops and lowers its anchor (MAKE-SHIP, art-guests.lisp)
immediately, returning WORLD. Bound to the `a' key; like every key spawn it
ignores the +MAX-BIG-EVENTS+ cap."
  (spawn-guest-now world :ship)
  world)

(defun world-spawn-submarine (world)
  "Spawn a submarine (SPAWN-SUBMARINE-NOW, art-submarine.lisp) immediately,
returning WORLD. Bound to the `m' key."
  (spawn-submarine-now world)
  world)

(defparameter +diver-no-chest-message+ "No treasure chest for a diver")

(defparameter +diver-busy-message+ "A diver is already out")

(defun world-spawn-diver (world)
  "Send a diver for the treasure chest (SPAWN-DIVER-NOW, art-treasure.lisp)
immediately, returning WORLD. When none can go, the status bar says why: the
screen is too small to hold a chest, or a diver is already out for it. Bound
to the `d' key."
  (unless (spawn-diver-now world)
    (world-notify world (if (find-creature-of-kind world :dinghy)
                            +diver-busy-message+
                            +diver-no-chest-message+)))
  world)

(defparameter +key-bindings+
  (list (cons (list #\r #\R) #'world-redraw)
        (cons (list #\Space) #'world-toggle-pause)
        (cons (list #\+ #\=) #'world-increase-fish-count)
        (cons (list #\- #\_) #'world-decrease-fish-count)
        (cons (list #\g #\G) #'world-spawn-random-guest)
        (cons (list #\c #\C) #'world-spawn-school)
        (cons (list #\a #\A) #'world-spawn-ship)
        (cons (list #\m #\M) #'world-spawn-submarine)
        (cons (list #\d #\D) #'world-spawn-diver)
        (cons (list #\t #\T) #'world-cycle-theme)
        (cons (list #\u #\U) #'world-toggle-hud)
        (cons (list #\h #\H) #'world-toggle-help-overlay))
  "Every ordinary key binding as data: each entry maps the CHARACTERs that
trigger it to the one-argument (WORLD) action WORLD-APPLY-KEY-EVENT below
runs for it. Quit (q/Q/Ctrl-C) and shark-spawn (s/S, gated on
WORLD-SHARK-ENABLED-P) are handled directly in WORLD-APPLY-KEY-EVENT instead
of here, since neither is a plain \"these characters run this action\"
mapping: quit also matches a non-character :SPECIAL Ctrl-C event, and shark
spawn depends on WORLD state beyond which key was pressed.")

(defun character-event-action (event)
  "Return the action +KEY-BINDINGS+ maps decoded cl-tty-kit KEY-EVENT EVENT's
character to, or NIL when EVENT is not a :CHARACTER event bound to any entry."
  (and (eq (key-event-type event) :character)
       (cdr (assoc (key-event-code event) +key-bindings+
                    :test (lambda (code characters) (member code characters :test #'char=))))))

(defun world-apply-key-event (world event)
  "Apply one decoded cl-tty-kit KEY-EVENT to WORLD, returning WORLD.
An event satisfying QUIT-KEY-EVENT-P (q, Q, or Ctrl-C) sets WORLD-QUITP; s/S
force-spawns a shark immediately when WORLD-SHARK-ENABLED-P is true
(SPAWN-SHARK-NOW, spawn.lisp; a no-op under --no-shark); every other bound
key runs the action +KEY-BINDINGS+ maps it to (see CHARACTER-EVENT-ACTION).
Every other event (including :SPECIAL keys such as arrows, which this
application does not bind) is ignored."
  (cond
    ((quit-key-event-p event) (setf (world-quitp world) t))
    ((and (or (character-key-event-p event #\s) (character-key-event-p event #\S))
          (world-shark-enabled-p world))
     (spawn-shark-now world))
    (t (let ((action (character-event-action event)))
         (when action (funcall action world)))))
  world)

(defun world-apply-key-events (world events)
  "Apply each of EVENTS to WORLD in order via WORLD-APPLY-KEY-EVENT, returning
WORLD."
  (dolist (event events) (world-apply-key-event world event))
  world)
