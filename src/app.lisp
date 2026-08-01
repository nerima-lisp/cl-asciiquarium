;;;; src/app.lisp -- the thin real-IO loop, kept separate from the pure
;;;; WORLD-ADVANCE state transition (update.lisp) per the split
;;;; examples/renderer-loop.lisp and examples/event-loop.lisp establish in
;;;; cl-tty-kit: everything below does real terminal I/O and calls
;;;; TICK-LOOP-RUN-REALTIME; nothing in update.lisp, collision.lisp, or
;;;; spawn.lisp does.
(in-package #:cl-asciiquarium)

(defun %read-available-string (stream)
  "Return every character currently buffered on STREAM without blocking, as a
string. Used instead of cl-tty-kit's fd-level FD-READ-OCTETS because
*STANDARD-INPUT* here is a plain character stream on the controlling
terminal, not a bare fd this application owns the non-blocking mode of;
READ-CHAR-NO-HANG already returns NIL rather than blocking when nothing is
buffered."
  (with-output-to-string (out)
    (loop for char = (read-char-no-hang stream nil nil)
          while char
          do (write-char char out))))

(defun %poll-input-events (decoder stream)
  "Feed any input currently available on STREAM through DECODER, returning
the decoded KEY-EVENTs (or NIL when nothing was available)."
  (let ((chunk (%read-available-string stream)))
    (if (plusp (length chunk))
        (decode-input-chunk decoder chunk)
        nil)))

(defun %poll-resize (world renderer)
  "Resize WORLD and RENDERER to the controlling terminal's current size when
it differs from WORLD's own, returning WORLD. cl-tty-kit polls rather than
traps SIGWINCH (see its terminal-size.lisp file header), so this application
does the same: it is called once per tick from the realtime loop below."
  (multiple-value-bind (columns rows) (terminal-size)
    (when (and columns rows
               (or (/= columns (world-width world)) (/= rows (world-height world))))
      (world-resize world columns rows)
      (renderer-resize renderer columns rows)))
  world)

(defun %advance-with-io (world renderer decoder)
  "The realtime loop's ADVANCE function: poll for a resize and for key input,
apply any decoded key events, then run the one pure simulation step."
  (%poll-resize world renderer)
  (world-apply-key-events world (%poll-input-events decoder *standard-input*))
  (world-advance world))

(defun run (&key (width +default-width+) (height +default-height+) fish-count seed
            (interval 1/20) (stream *standard-output*))
  "Run the aquarium in the real terminal until `q' is pressed. WIDTH and
HEIGHT size the initial WORLD (a resize is then picked up automatically, see
%POLL-RESIZE); SEED, when supplied, seeds *RANDOM-STATE* for a reproducible
run; INTERVAL is the target seconds between frames, forwarded to
cl-tty-kit:TICK-LOOP-RUN-REALTIME."
  (when seed
    (setf *random-state* (sb-ext:seed-random-state seed)))
  (let ((world (make-world :width width :height height
                            :fish-count (or fish-count +default-fish-count+)))
        (renderer (make-renderer width height))
        (decoder (make-input-decoder)))
    (with-raw-mode ()
      (with-terminal-session (session-stream :stream stream :hide-cursor t :alternate-screen t)
        (tick-loop-run-realtime
         world
         (lambda (state) (%advance-with-io state renderer decoder))
         (lambda (state) (render-frame renderer state))
         (lambda (state) (world-quitp state))
         :stream session-stream
         :interval interval)))))
