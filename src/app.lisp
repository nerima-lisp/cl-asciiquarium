;;;; src/app.lisp -- the thin real-IO loop, kept separate from the pure
;;;; WORLD-ADVANCE state transition (update.lisp) per the split
;;;; examples/renderer-loop.lisp and examples/event-loop.lisp establish in
;;;; cl-tty-kit: everything below does real terminal I/O and calls
;;;; TICK-LOOP-RUN-REALTIME; nothing in update.lisp, collision.lisp, or
;;;; spawn.lisp does.
(in-package #:cl-asciiquarium)

(defun make-world-poller (renderer stream decoder)
  "Return a TICK-LOOP-RUN-REALTIME :POLL callback that keeps a WORLD state
in sync with the controlling terminal before every tick's pure advance step:
resize WORLD and RENDERER via cl-tty-kit:MAKE-TERMINAL-SIZE-POLLER when the
terminal's size has changed since the last poll, then apply any key events
cl-tty-kit:MAKE-STREAM-INPUT-POLLER decodes from STREAM through DECODER.
Both pollers keep their own state across ticks (the last-seen terminal size,
and any escape sequence split across reads), so this closure only needs to
compose them once per RUN rather than reimplementing either."
  (let ((size-poller (make-terminal-size-poller))
        (input-poller (make-stream-input-poller stream :decoder decoder)))
    (lambda (state)
      (multiple-value-bind (columns rows) (funcall size-poller state 0)
        (when (and columns rows)
          (world-resize state columns rows)
          (renderer-resize renderer columns rows)))
      (world-apply-key-events state (funcall input-poller state 0)))))

(defun quit-on-signal (world)
  "The action RUN's SIGTERM/SIGHUP handler performs: set WORLD-QUITP, so the
tick loop notices on its next STOP check and returns normally, letting
WITH-TERMINAL-SESSION's own UNWIND-PROTECT restore the terminal exactly as it
does for the `q' key -- rather than an external `kill' or a closed
controlling terminal ending the process mid-raw-mode, with the terminal left
needing a manual `reset'/`stty sane' to recover."
  (setf (world-quitp world) t))

(defun install-quit-signal-handler (world)
  "Install QUIT-ON-SIGNAL as WORLD's SIGTERM and SIGHUP handler, so an
external `kill' or a closed controlling terminal quits exactly as cleanly as
the `q' key. Not itself unit-tested (see QUIT-ON-SIGNAL for the tested
logic): sending a real signal to exercise this would risk terminating the
test runner itself, which is exactly the real-terminal/real-process boundary
RUN is already outside TEST_STANDARD.md's unit-test scope for (see
t/app-test.lisp)."
  (flet ((handle (signal info context)
           (declare (ignore signal info context))
           (quit-on-signal world)))
    (sb-sys:enable-interrupt sb-unix:sigterm #'handle)
    (sb-sys:enable-interrupt sb-unix:sighup #'handle))
  (values))

(defun run (&key (width +default-width+) (height +default-height+) fish-count seed
            (interval 1/20) (stream *standard-output*) (shark-enabled-p t) monochrome-p)
  "Run the aquarium in the real terminal until `q' is pressed, or SIGTERM/
SIGHUP arrives from outside (see INSTALL-QUIT-SIGNAL-HANDLER) -- both quit
exactly as cleanly, restoring the terminal via WITH-TERMINAL-SESSION's
UNWIND-PROTECT rather than leaving it in raw/alternate-screen mode. WIDTH and
HEIGHT size the initial WORLD (a resize is then picked up automatically, see
MAKE-WORLD-POLLER); SEED, when supplied, seeds *RANDOM-STATE* for a
reproducible run; INTERVAL is the target seconds between frames, forwarded to
cl-tty-kit:TICK-LOOP-RUN-REALTIME; SHARK-ENABLED-P and MONOCHROME-P forward the
--no-shark and --monochrome CLI flags (cli.lisp) to MAKE-WORLD and *MONOCHROME*
(creature.lisp) respectively."
  (when seed
    (setf *random-state* (sb-ext:seed-random-state seed)))
  ;; LET*, not LET: MAKE-WORLD's init-form must run after *MONOCHROME* is
  ;; bound, since it constructs every background/fish creature (via
  ;; SOLID-STYLE, creature.lisp) right away -- LET's parallel-binding
  ;; semantics would evaluate MAKE-WORLD against the outer, unbound
  ;; *MONOCHROME* instead.
  (let* ((*monochrome* monochrome-p)
         (world (make-world :width width :height height
                             :fish-count (or fish-count (default-fish-count-for-dimensions width height))
                             :shark-enabled-p shark-enabled-p))
         (renderer (make-renderer width height))
         (decoder (make-input-decoder)))
    (with-raw-mode ()
      (with-terminal-session (session-stream :stream stream :hide-cursor t :alternate-screen t)
        (install-quit-signal-handler world)
        (unwind-protect
             (tick-loop-run-realtime
              world
              #'world-advance
              (lambda (state) (render-frame renderer state :stream session-stream))
              #'world-quitp
              :stream session-stream
              :interval interval
              :poll (make-world-poller renderer *standard-input* decoder))
          (sb-sys:enable-interrupt sb-unix:sigterm :default)
          (sb-sys:enable-interrupt sb-unix:sighup :default))))))
