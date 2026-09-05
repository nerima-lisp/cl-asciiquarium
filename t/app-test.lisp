;;;; t/app-test.lisp
;;;;
;;;; INSTALL-QUIT-SIGNAL-HANDLER is still not exercised here: delivering a real
;;;; SIGTERM to prove it would risk terminating the test runner itself.
;;;; QUIT-ON-SIGNAL is the plain, directly callable logic it wires to
;;;; SIGTERM/SIGHUP, so that part is unit-tested below.
;;;;
;;;; RUN is exercised through its injectable output stream. Only
;;;; CL-TTY-KIT:ENABLE-RAW-MODE needs to be stubbed for these tests.
;;;; MAKE-WORLD-POLLER's returned closure takes its
;;;; STREAM as a plain argument rather than reading *STANDARD-INPUT* directly,
;;;; so a WITH-INPUT-FROM-STRING stream exercises its input branch directly
;;;; without any of that; its resize branch is exercised too, because
;;;; CL-TTY-KIT:TERMINAL-SIZE returns (VALUES NIL NIL) whenever FD 0 is not a
;;;; real terminal, which is always true under `nix flake check' and
;;;; `sbcl --script run-tests.lisp' alike, so this environment already is the
;;;; "no resize available" case.
(in-package #:cl-asciiquarium/test)

(describe "make-world-poller"
  (it "applies key events decoded from the stream to the world"
    (with-input-from-string (stream "q")
      (let* ((world (tiny-world :width 20 :height 10))
             (poll (cl-asciiquarium::make-world-poller
                    (make-renderer 20 10) stream (make-input-decoder))))
        (funcall poll world)
        (expect (world-quitp world) :to-be-truthy))))

  (it "resizes the world and renderer when the terminal size poller has both dimensions"
    (let* ((size-poller-symbol 'cl-asciiquarium::make-terminal-size-poller)
           (input-poller-symbol 'cl-asciiquarium::make-stream-input-poller)
           (original-size-poller (symbol-function size-poller-symbol))
           (original-input-poller (symbol-function input-poller-symbol))
           (world (tiny-world :width 20 :height 10))
           (renderer (make-renderer 20 10)))
      (unwind-protect
           (progn
             (setf (symbol-function size-poller-symbol)
                   (lambda ()
                     (lambda (state timeout)
                       (declare (ignore state timeout))
                       (values 73 31))))
             (setf (symbol-function input-poller-symbol)
                   (lambda (stream &key decoder)
                     (declare (ignore stream decoder))
                     (lambda (state timeout)
                       (declare (ignore state timeout))
                       nil)))
             (funcall (cl-asciiquarium::make-world-poller renderer nil nil)
                      world)
             (expect (world-width world) :to-be 73)
             (expect (world-height world) :to-be 31)
             (expect (cl-tty-kit:renderer-width renderer) :to-be 73)
             (expect (cl-tty-kit:renderer-height renderer) :to-be 31))
        ;; Restore the global function cells even if an assertion fails.
        (setf (symbol-function size-poller-symbol) original-size-poller
              (symbol-function input-poller-symbol) original-input-poller))))

  (it "leaves world and renderer alone when nothing is buffered and no terminal size is available"
    (with-input-from-string (stream "")
      (let* ((world (tiny-world :width 20 :height 10))
             (poll (cl-asciiquarium::make-world-poller
                    (make-renderer 20 10) stream (make-input-decoder))))
        (funcall poll world)
        (expect (world-quitp world) :to-be-null)
        (expect (world-width world) :to-be 20)))))

(describe "quit-on-signal"
  (it "sets world-quitp, the same flag the q key sets, so a SIGTERM/SIGHUP quits exactly as cleanly"
    (let ((world (tiny-world)))
      (cl-asciiquarium::quit-on-signal world)
      (expect (world-quitp world) :to-be-truthy))))

;; Written out rather than taken from CL-TTY-KIT:ANSI-SHOW-CURSOR and friends,
;; which are the very functions WITH-TERMINAL-SESSION emits through: reusing
;; them would make the comparison agree by construction. These are the standard
;; DEC private-mode sequences, confirmed against the emitted bytes.
(defparameter +show-cursor-sequence+
  (format nil "~C[?25h" (code-char 27)))
(defparameter +exit-alternate-screen-sequence+
  (format nil "~C[?1049l" (code-char 27)))

(defun %terminal-restored-p (output)
  "Whether OUTPUT ends with the full restoration sequence, cursor shown and
then alternate screen exited. Checked as a SUFFIX, not a substring: emitting
those bytes somewhere in the middle and then writing more escape sequences
would leave a real terminal just as wrecked."
  (let ((suffix (concatenate 'string
                             +show-cursor-sequence+
                             +exit-alternate-screen-sequence+)))
    (and (>= (length output) (length suffix))
         (string= suffix output :start2 (- (length output) (length suffix))))))

(defun %run-under-stubbed-terminal (tick-loop-action)
  "Drive RUN with only the real-terminal boundary stubbed out, and report what
it did. Returns (VALUES OUTCOME OUTPUT DISABLE-RAW-MODE-CALLS), where OUTCOME is
:RETURNED-NORMALLY or the condition RUN signalled.

RUN's whole body sits inside CL-TTY-KIT:WITH-RAW-MODE, which runs its body only
WHEN (ENABLE-RAW-MODE FD) succeeds -- and on the non-terminal FD 0 that
`sbcl --script' always has, ENABLE-RAW-MODE signals RAW-MODE-OPERATION-FAILED.
Stubbing that one exported function is what makes any path through RUN reachable
here. Everything else is real: the session escape sequences are captured through
RUN's own :STREAM argument, and the UNWIND-PROTECT under test is untouched.

TICK-LOOP-ACTION replaces CL-TTY-KIT:TICK-LOOP-RUN-REALTIME and receives the
WORLD, so a test can make the loop return normally, quit through QUIT-ON-SIGNAL,
or signal."
  (let* ((enable-symbol 'cl-tty-kit:enable-raw-mode)
         (disable-symbol 'cl-tty-kit:disable-raw-mode)
         (loop-symbol 'cl-tty-kit:tick-loop-run-realtime)
         (original-enable (symbol-function enable-symbol))
         (original-disable (symbol-function disable-symbol))
         (original-loop (symbol-function loop-symbol))
         (disable-raw-mode-calls 0)
         (captured (make-string-output-stream))
         (outcome nil))
    (unwind-protect
         (progn
           (setf (symbol-function enable-symbol)
                 (lambda (&optional (fd 0)) (declare (ignore fd)) t))
           (setf (symbol-function disable-symbol)
                 (lambda (&optional (fd 0))
                   (declare (ignore fd))
                   (incf disable-raw-mode-calls)
                   t))
           (setf (symbol-function loop-symbol)
                 (lambda (world advance render stop &rest options)
                   (declare (ignore advance render stop options))
                   (funcall tick-loop-action world)))
           (setf outcome
                 (handler-case
                     (progn (cl-asciiquarium::run :width 20 :height 10
                                                  :fish-count 0
                                                  :stream captured)
                            :returned-normally)
                   (error (condition) condition))))
      (setf (symbol-function enable-symbol) original-enable
            (symbol-function disable-symbol) original-disable
            (symbol-function loop-symbol) original-loop)
      ;; RUN installs real SIGTERM/SIGHUP handlers and resets them in its own
      ;; cleanup. Reset again here so that a failure *inside* RUN cannot leave
      ;; this image's signal disposition altered for every later test.
      (sb-sys:enable-interrupt sb-unix:sigterm :default)
      (sb-sys:enable-interrupt sb-unix:sighup :default))
    (values outcome (get-output-stream-string captured) disable-raw-mode-calls)))

(describe
 "run terminal restoration"
 ;; Keep the error path covered: cleanup must restore the terminal when RUN
 ;; exits through an unhandled condition.
 (it
  "restores the terminal when an unhandled error escapes the tick loop"
  (multiple-value-bind (outcome output disable-raw-mode-calls)
      (%run-under-stubbed-terminal
       (lambda (world)
         (declare (ignore world))
         (error "simulated unhandled error inside the tick loop")))
    (expect (typep outcome 'error) :to-be-truthy)
    ;; The original condition must survive the cleanup rather than being
    ;; replaced by something signalled while unwinding.
    (expect (search "simulated unhandled error" (princ-to-string outcome))
            :to-be-truthy)
    (expect (%terminal-restored-p output) :to-be-truthy)
    (expect disable-raw-mode-calls :to-be 1)))
 (it
  "restores the terminal when the loop stops because a signal set world-quitp"
  (let ((signalled-world nil))
    (multiple-value-bind (outcome output disable-raw-mode-calls)
        (%run-under-stubbed-terminal
         (lambda (world)
           ;; Exactly what RUN's SIGTERM/SIGHUP handler does, which is what
           ;; lets the loop return normally instead of dying mid-raw-mode.
           (cl-asciiquarium::quit-on-signal world)
           (setf signalled-world world)
           world))
      (expect outcome :to-be :returned-normally)
      (expect (world-quitp signalled-world) :to-be-truthy)
      (expect (%terminal-restored-p output) :to-be-truthy)
      (expect disable-raw-mode-calls :to-be 1))))
 (it
  "restores the terminal when the loop returns normally, as it does for q"
  (multiple-value-bind (outcome output disable-raw-mode-calls)
      (%run-under-stubbed-terminal (lambda (world) world))
    (expect outcome :to-be :returned-normally)
    (expect (%terminal-restored-p output) :to-be-truthy)
    (expect disable-raw-mode-calls :to-be 1)))
 (it
  "enters the alternate screen and hides the cursor before running the loop"
  ;; The restoration assertions above would be satisfied trivially if setup had
  ;; never happened, so pin that the session was actually entered.
  (let ((entered nil))
    (multiple-value-bind (outcome output disable-raw-mode-calls)
        (%run-under-stubbed-terminal
         (lambda (world) (setf entered t) world))
      (declare (ignore outcome disable-raw-mode-calls))
      (expect entered :to-be-truthy)
      (expect (search (format nil "~C[?1049h" (code-char 27)) output)
              :to-be 0)
      (expect (search (format nil "~C[?25l" (code-char 27)) output)
              :to-be-truthy)))))
