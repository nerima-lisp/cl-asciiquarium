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

(defvar *stubbed-advance* nil
  "The advance function RUN handed the stubbed tick loop, bound while a
%RUN-UNDER-STUBBED-TERMINAL action runs.")

(defun %run-under-stubbed-terminal (tick-loop-action &rest run-arguments)
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
or signal; it can tick through *STUBBED-ADVANCE*. RUN-ARGUMENTS go to RUN
ahead of the defaults, which include a :DEX-PATH in a directory that does not
exist, so no test reads or writes the real dex file."
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
                   (declare (ignore render stop options))
                   (let ((*stubbed-advance* advance))
                     (funcall tick-loop-action world))))
           (setf outcome
                 (handler-case
                     (progn (apply #'cl-asciiquarium::run
                                   (append run-arguments
                                           (list :width 20 :height 10 :fish-count 0
                                                 :stream captured
                                                 :dex-path (merge-pathnames
                                                            (format nil "aq-no-dex-~36R/zukan.sexp"
                                                                    (random most-positive-fixnum
                                                                            (make-random-state t)))
                                                            (uiop:temporary-directory)))))
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

(describe
 "run mouse reporting"
 (it
  "turns on press-and-release reporting for the session and off before restoring the terminal"
  (multiple-value-bind (outcome output)
      (%run-under-stubbed-terminal (lambda (world) world))
    (expect outcome :to-be :returned-normally)
    (let ((on (search (cl-tty-kit:ansi-enable-mouse :normal) output))
          (off (search (cl-tty-kit:ansi-disable-mouse :normal) output :from-end t)))
      (expect on :to-be-truthy)
      (expect off :to-be-truthy)
      (expect (< on off) :to-be-truthy))
    (expect (%terminal-restored-p output) :to-be-truthy))))

(describe
 "run and the dex file"
 (it
  "starts from the stored species, unknown ones included, and saves each new discovery"
  (with-temporary-directory (dir "aq-run-dex-")
    (let ((path (merge-pathnames "zukan.sexp" dir))
          (stored nil)
          (notification :unset))
      (cl-asciiquarium::save-zukan path '(:golden :kraken))
      (expect (%run-under-stubbed-terminal
               (lambda (world)
                 (setf stored (copy-list (cl-asciiquarium::world-discovered-species world)))
                 (cl-asciiquarium::%add-world-creature world (make-fish world :species :dart))
                 (funcall *stubbed-advance* world)
                 (setf notification (cl-asciiquarium::world-notification world))
                 world)
               :dex-path path)
              :to-be :returned-normally)
      (expect (sort stored #'string<) :to-equal '(:golden :kraken))
      (expect (sort (cl-asciiquarium::load-zukan path) #'string<) :to-equal '(:dart :golden :kraken))
      (expect notification :to-be nil))))
 (it
  "says an unreadable file will not be saved, and leaves it as it was"
  (with-temporary-directory (dir "aq-run-dex-")
    (let ((path (merge-pathnames "zukan.sexp" dir))
          (notification nil))
      (with-open-file (stream path :direction :output)
        (write-string "(:zukan 1 :species (:dart" stream))
      (expect (%run-under-stubbed-terminal
               (lambda (world)
                 (cl-asciiquarium::%add-world-creature world (make-fish world :species :eel))
                 (funcall *stubbed-advance* world)
                 (setf notification (cl-asciiquarium::world-notification world))
                 world)
               :dex-path path)
              :to-be :returned-normally)
      (expect notification :to-equal "dex file unreadable; not saving")
      (expect (uiop:read-file-string path) :to-equal "(:zukan 1 :species (:dart")
      (expect (uiop:directory-files dir) :to-equal (list path))))))

(defun %request-snapshot (world)
  (funcall (cl-asciiquarium::make-world-poller
            (make-renderer (world-width world) (world-height world))
            (make-string-input-stream "p") (make-input-decoder))
           world))

(describe
 "make-frame-drawer and the p key"
 (it
  "leaves the request to the drawer, so the poller saves nothing"
  (with-input-from-string (stream "p")
    (let ((world (tiny-world :width 20 :height 10)))
      (funcall (cl-asciiquarium::make-world-poller (make-renderer 20 10) stream
                                                   (make-input-decoder))
               world)
      (expect (cl-asciiquarium::world-snapshot-requested-p world) :to-be t)
      (expect (cl-asciiquarium::world-notification world) :to-be nil))))
 (it
  "draws the frame, then saves the renderer's screen, clears the request, and reports the file"
  (with-temporary-directory (dir "aq-drawer-snapshot-")
    (let* ((world (tiny-world :width 20 :height 10))
           (renderer (make-renderer 20 10 :initial-cell (world-background-cell world)))
           (draw (cl-asciiquarium::make-frame-drawer renderer (make-broadcast-stream)
                                                     :snapshot-directory dir)))
      (%request-snapshot world)
      (funcall draw world)
      (expect (cl-asciiquarium::world-snapshot-requested-p world) :to-be nil)
      (expect (uiop:string-prefix-p "Saved " (cl-asciiquarium::world-notification world))
              :to-be-truthy)
      (let ((files (uiop:directory-files dir)))
        (expect (length files) :to-be 1)
        (expect (uiop:read-file-string (first files) :external-format :utf-8)
                :to-equal (format nil "~A~%" (cl-asciiquarium::screen-text
                                               (cl-asciiquarium::renderer-screen renderer))))))))
 (it
  "returns what render-frame returns"
  (let* ((world (tiny-world :width 20 :height 10))
         (stream (make-string-output-stream))
         (draw (cl-asciiquarium::make-frame-drawer (make-renderer 20 10) stream)))
    (expect (multiple-value-list (funcall draw world))
            :to-equal (multiple-value-list
                       (render-frame (make-renderer 20 10) world :stream stream)))))
 (it
  "reports a failure when the directory does not exist"
  (with-temporary-directory (dir "aq-drawer-snapshot-")
    (let* ((world (tiny-world :width 20 :height 10))
           (draw (cl-asciiquarium::make-frame-drawer
                  (make-renderer 20 10) (make-broadcast-stream)
                  :snapshot-directory (merge-pathnames "missing/" dir))))
      (%request-snapshot world)
      (funcall draw world)
      (expect (cl-asciiquarium::world-snapshot-requested-p world) :to-be nil)
      (expect (cl-asciiquarium::world-notification world) :to-equal "Snapshot failed")
      (expect (uiop:directory-files dir) :to-be nil))))
 (it
  "saves nothing when no key asked for it"
  (with-temporary-directory (dir "aq-drawer-snapshot-")
    (let ((world (tiny-world :width 20 :height 10)))
      (funcall (cl-asciiquarium::make-frame-drawer (make-renderer 20 10) (make-broadcast-stream)
                                                   :snapshot-directory dir)
               world)
      (expect (uiop:directory-files dir) :to-be nil)
      (expect (cl-asciiquarium::world-notification world) :to-be nil)))))

(defun %hud-art (world)
  (creature-art (find :hud (cl-asciiquarium::world-%creatures world)
                      :key #'cl-asciiquarium::creature-kind)))

(describe
 "notifications on an 80-column status bar"
 (it
  "shows the saved snapshot's file name"
  (with-temporary-directory (dir "aq-drawer-snapshot-")
    (let ((world (tiny-world :width 80 :height 24)))
      (%request-snapshot world)
      (funcall (cl-asciiquarium::make-frame-drawer
                (make-renderer 80 24 :initial-cell (world-background-cell world))
                (make-broadcast-stream) :snapshot-directory dir)
               world)
      (let ((name (file-namestring (first (uiop:directory-files dir)))))
        (expect (search (concatenate 'string "Saved " name) (%hud-art world)) :to-be-truthy)))))
 (it
  "shows that the dex file is unreadable"
  (with-temporary-directory (dir "aq-run-dex-")
    (let ((path (merge-pathnames "zukan.sexp" dir))
          (art nil))
      (with-open-file (stream path :direction :output)
        (write-string "(:zukan" stream))
      (%run-under-stubbed-terminal (lambda (world) (setf art (%hud-art world)) world)
                                   :dex-path path :width 80 :height 24)
      (expect (search "dex file unreadable; not saving" art) :to-be-truthy)))))

(describe
 "make-world-poller, a resize, and the p key in one poll"
 (it
  "leaves the request to the drawer, which saves the resized frame it draws next"
  (let* ((size-poller-symbol 'cl-asciiquarium::make-terminal-size-poller)
         (original-size-poller (symbol-function size-poller-symbol)))
    (with-temporary-directory (dir "aq-drawer-snapshot-")
      (with-input-from-string (stream "p")
        (unwind-protect
             (let ((sizes (list (list 73 31))))
               (setf (symbol-function size-poller-symbol)
                     (lambda ()
                       (lambda (state timeout)
                         (declare (ignore state timeout))
                         (values-list (pop sizes)))))
               (let* ((world (tiny-world :width 20 :height 10))
                      (renderer (make-renderer 20 10 :initial-cell (world-background-cell world)))
                      (poll (cl-asciiquarium::make-world-poller
                             renderer stream (make-input-decoder)))
                      (draw (cl-asciiquarium::make-frame-drawer
                             renderer (make-broadcast-stream) :snapshot-directory dir)))
                 (funcall draw world)
                 (funcall poll world)
                 (expect (cl-asciiquarium::world-snapshot-requested-p world) :to-be t)
                 (expect (uiop:directory-files dir) :to-be nil)
                 ;; The resized world drawn from scratch, before the saved
                 ;; notice changes the status bar.
                 (let ((expected (format nil "~{~A~^~%~}~%"
                                         (mapcar (lambda (row) (string-right-trim " " row))
                                                 (%drawn-rows world)))))
                   (funcall draw world)
                   (expect (cl-asciiquarium::world-snapshot-requested-p world) :to-be nil)
                   (let ((files (uiop:directory-files dir)))
                     (expect (length files) :to-be 1)
                     (expect (uiop:read-file-string (first files) :external-format :utf-8)
                             :to-equal expected)))))
          (setf (symbol-function size-poller-symbol) original-size-poller)))))))

(defun %snapshots-of-a-real-run (keys sizes)
  "Run RUN through the real tick loop with KEYS on standard input, the terminal
reporting the sizes in SIZES (one (COLUMNS ROWS) per poll, then none), and
snapshots going to a fresh directory, until a key quits. Only raw mode, the
terminal size poller, and the snapshot directory are stubbed. Returns the
contents of every snapshot file RUN saved."
  (let* ((enable-symbol 'cl-tty-kit:enable-raw-mode)
         (disable-symbol 'cl-tty-kit:disable-raw-mode)
         (size-poller-symbol 'cl-asciiquarium::make-terminal-size-poller)
         (directory-symbol 'cl-asciiquarium::default-snapshot-directory)
         (originals (mapcar #'symbol-function
                            (list enable-symbol disable-symbol size-poller-symbol
                                  directory-symbol))))
    (with-temporary-directory (dir "aq-run-snapshot-")
      (unwind-protect
           (progn
             (setf (symbol-function enable-symbol)
                   (lambda (&optional (fd 0)) (declare (ignore fd)) t)
                   (symbol-function disable-symbol)
                   (lambda (&optional (fd 0)) (declare (ignore fd)) t)
                   (symbol-function size-poller-symbol)
                   (lambda ()
                     (lambda (state timeout)
                       (declare (ignore state timeout))
                       (values-list (pop sizes))))
                   (symbol-function directory-symbol)
                   (lambda () dir))
             (with-input-from-string (*standard-input* keys)
               (cl-asciiquarium::run :width 20 :height 10 :fish-count 0 :interval 1/100
                                     :stream (make-broadcast-stream)
                                     :dex-path (merge-pathnames "missing/zukan.sexp" dir)))
             (mapcar (lambda (file) (uiop:read-file-string file :external-format :utf-8))
                     (uiop:directory-files dir)))
        (loop for symbol in (list enable-symbol disable-symbol size-poller-symbol
                                  directory-symbol)
              for original in originals
              do (setf (symbol-function symbol) original))
        (sb-sys:enable-interrupt sb-unix:sigterm :default)
        (sb-sys:enable-interrupt sb-unix:sighup :default)))))

(describe
 "run, the p key, and q in one input batch"
 (it
  "saves the snapshot before quitting"
  (expect (length (%snapshots-of-a-real-run "pq" nil)) :to-be 1))
 (it
  "saves the resized frame before quitting when a resize came in the same poll"
  (let ((snapshots (%snapshots-of-a-real-run "pq" (list (list 73 31)))))
    (expect (length snapshots) :to-be 1)
    (let ((rows (uiop:split-string (string-right-trim '(#\Newline) (first snapshots))
                                   :separator '(#\Newline))))
      (expect (length rows) :to-be 31)
      (expect (notevery (lambda (row) (string= (string-trim " " row) "")) rows)
              :to-be-truthy)))))
