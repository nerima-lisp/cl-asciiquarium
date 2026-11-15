;;;; src/app.lisp -- the thin real-IO loop, kept separate from the pure
;;;; WORLD-ADVANCE state transition (update.lisp) per the split
;;;; examples/renderer-loop.lisp and examples/event-loop.lisp establish in
;;;; cl-tty-kit: everything below does real terminal I/O and calls
;;;; TICK-LOOP-RUN-REALTIME; nothing in update.lisp, collision.lisp, or
;;;; spawn.lisp does.
(in-package #:cl-asciiquarium)

(defun default-snapshot-directory ()
  "The directory the `p' key saves snapshots in: XDG_PICTURES_DIR from the
environment when it is absolute, otherwise the current directory."
  (snapshot-directory (uiop:getenv "XDG_PICTURES_DIR") (uiop:getcwd)))

(defun make-world-poller (renderer stream decoder
                          &key (snapshot-directory (default-snapshot-directory)))
  "Return a TICK-LOOP-RUN-REALTIME :POLL callback that keeps a WORLD state
in sync with the controlling terminal before every tick's pure advance step:
resize WORLD and RENDERER via cl-tty-kit:MAKE-TERMINAL-SIZE-POLLER when the
terminal's size has changed since the last poll, then apply any key events
cl-tty-kit:MAKE-STREAM-INPUT-POLLER decodes from STREAM through DECODER.
Both pollers keep their own state across ticks (the last-seen terminal size,
and any escape sequence split across reads), so this closure only needs to
compose them once per RUN rather than reimplementing either. When a key
asked for a snapshot (WORLD-REQUEST-SNAPSHOT), the renderer's screen, still
the frame drawn just before the key was read, is saved in SNAPSHOT-DIRECTORY
and the status bar reports the file or the failure; the report comes after
the picture, so it is not in it. On a poll that resized the renderer, its
screen holds no frame yet, so the request waits for the next poll."
  (let ((size-poller (make-terminal-size-poller))
        (input-poller (make-stream-input-poller stream :decoder decoder)))
    (lambda (state)
      (let ((resized-p nil))
        (multiple-value-bind (columns rows) (funcall size-poller state 0)
          (when (and columns rows)
            (setf resized-p t)
            (world-resize state columns rows)
            (renderer-resize renderer columns rows
                             :initial-cell (world-background-cell state))))
        (world-apply-key-events state (funcall input-poller state 0))
        (when (and (world-snapshot-requested-p state) (not resized-p))
          (setf (world-snapshot-requested-p state) nil)
          (world-notify state (snapshot-notification
                               (save-snapshot (renderer-screen renderer) snapshot-directory
                                              (get-universal-time))))))
      state)))

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
the `q' key. The signal boundary is not unit-tested; see t/app-test.lisp."
  (flet ((handle (signal info context)
           (declare (ignore signal info context))
           (quit-on-signal world)))
    (sb-sys:enable-interrupt sb-unix:sigterm #'handle)
    (sb-sys:enable-interrupt sb-unix:sighup #'handle))
  (values))

(defparameter +dex-unreadable-message+ "dex file unreadable; not saving")

(defun default-zukan-path ()
  "The dex file's pathname for this process's XDG_STATE_HOME and home."
  (zukan-path (uiop:getenv "XDG_STATE_HOME") (user-homedir-pathname)))

(defun make-zukan-advancer (path saved-count)
  "Return a TICK-LOOP-RUN-REALTIME advance function: WORLD-ADVANCE, then save
the discovered species to the dex file at PATH when a species was discovered
since the last save (ZUKAN-SAVE-IF-GROWN). SAVED-COUNT is how many species the
file held when it was read."
  (lambda (world)
    (world-advance world)
    (setf saved-count (zukan-save-if-grown world path saved-count))
    world))

(defun run (&key (width +default-width+) (height +default-height+) fish-count
            (max-fish +default-max-fish+) seed
            (interval 1/20) (stream *standard-output*) (shark-enabled-p t)
            monochrome-p (theme :abyss) (color-mode :ansi16) ascii-p calm-p
            (daycycle-p t) (dex-path (default-zukan-path)))
  "Run the aquarium in the real terminal until `q' is pressed, or SIGTERM/
SIGHUP arrives from outside (see INSTALL-QUIT-SIGNAL-HANDLER) -- both quit
exactly as cleanly, restoring the terminal via WITH-TERMINAL-SESSION's
UNWIND-PROTECT rather than leaving it in raw/alternate-screen mode. WIDTH and
HEIGHT size the initial WORLD (a resize is then picked up automatically, see
MAKE-WORLD-POLLER); SEED, when supplied, seeds *RANDOM-STATE* for a
reproducible run; INTERVAL is the target seconds between frames, forwarded to
cl-tty-kit:TICK-LOOP-RUN-REALTIME; SHARK-ENABLED-P and MONOCHROME-P forward the
--no-shark and --monochrome CLI flags (cli.lisp) to MAKE-WORLD and *MONOCHROME*
(creature.lisp) respectively. THEME selects the initial visual palette; it
accepts one of +VISUAL-THEMES+ and can be changed while running. COLOR-MODE
(one of +COLOR-MODES+, from --color) and ASCII-P (--ascii) bind *COLOR-MODE*
and *ASCII*, both read only as creatures are prepared. MAX-FISH (--max-fish),
CALM-P (--calm), and DAYCYCLE-P (NIL under --no-daycycle) go to MAKE-WORLD.
DEX-PATH is the dex file (LOAD-ZUKAN): its species start the world's
discoveries, and each new discovery is saved to it. When it is unreadable the
status bar says so and this run never writes it."
  (when seed
    (setf *random-state* (sb-ext:seed-random-state seed)))
  (multiple-value-bind (known-species dex-writable-p) (load-zukan dex-path)
    ;; LET*, not LET: MAKE-WORLD's init-form must run after *MONOCHROME* is
    ;; bound, since it constructs every background/fish creature (via
    ;; SOLID-STYLE, creature.lisp) right away -- LET's parallel-binding
    ;; semantics would evaluate MAKE-WORLD against the outer, unbound
    ;; *MONOCHROME* instead.
    (let* ((*monochrome* monochrome-p)
           (*color-mode* color-mode)
           (*ascii* ascii-p)
           (world (make-world :width width :height height
                               :fish-count (or fish-count +default-fish-count+)
                               :max-fish max-fish
                               :calm-p calm-p
                               :daycycle-p daycycle-p
                               :shark-enabled-p shark-enabled-p
                               :theme theme
                               :ticks-per-second (max 1 (round 1 interval))
                               :discovered-species known-species))
           (renderer (make-renderer width height
                                    :initial-cell (world-background-cell world)))
           (decoder (make-input-decoder)))
      (with-raw-mode ()
        ;; :NORMAL reports button presses and releases only, which is all the
        ;; left-click food needs; the session turns reporting off again on exit.
        (with-terminal-session (session-stream :stream stream :hide-cursor t :alternate-screen t
                                               :mouse :normal)
          (install-quit-signal-handler world)
          (unless dex-writable-p
            (world-notify world +dex-unreadable-message+))
          (unwind-protect
               (tick-loop-run-realtime
                world
                (if dex-writable-p
                    (make-zukan-advancer dex-path (length known-species))
                    #'world-advance)
                (lambda (state) (render-frame renderer state :stream session-stream))
                #'world-quitp
                :stream session-stream
                :interval interval
                :poll (make-world-poller renderer *standard-input* decoder))
            (sb-sys:enable-interrupt sb-unix:sigterm :default)
            (sb-sys:enable-interrupt sb-unix:sighup :default)
            (shutdown-renderer renderer)))))))
