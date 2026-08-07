;;;; t/app-test.lisp
;;;;
;;;; RUN and INSTALL-QUIT-SIGNAL-HANDLER are deliberately not exercised here:
;;;; both only do anything observable through a real controlling terminal or a
;;;; real delivered signal (and sending one to exercise the latter would risk
;;;; terminating the test runner itself), which is exactly the boundary
;;;; TEST_STANDARD.md reserves for a real-implementation test, not a unit
;;;; test -- see t/cli-test.lisp's header comment for the same reasoning
;;;; applied to RUN-HANDLER. QUIT-ON-SIGNAL is the plain, directly callable
;;;; logic INSTALL-QUIT-SIGNAL-HANDLER wires to SIGTERM/SIGHUP, so that part
;;;; is unit-tested below. MAKE-WORLD-POLLER's returned closure takes its
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
