;;;; src/input.lisp -- turning decoded cl-tty-kit KEY-EVENTs into WORLD state
;;;; changes: `q' to quit, `r' to redraw/reshuffle.
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

(defun world-apply-key-event (world event)
  "Apply one decoded cl-tty-kit KEY-EVENT to WORLD, returning WORLD.
An event satisfying QUIT-KEY-EVENT-P (q, Q, or Ctrl-C) sets WORLD-QUITP; a
:CHARACTER event with code #\\r or #\\R calls WORLD-REDRAW. Every other
event (including other :SPECIAL keys such as arrows, which this application
does not bind) is ignored."
  (cond
    ((quit-key-event-p event) (setf (world-quitp world) t))
    ((and (eq (key-event-type event) :character)
          (member (key-event-code event) '(#\r #\R) :test #'char=))
     (world-redraw world)))
  world)

(defun world-apply-key-events (world events)
  "Apply each of EVENTS to WORLD in order via WORLD-APPLY-KEY-EVENT, returning
WORLD."
  (dolist (event events) (world-apply-key-event world event))
  world)
