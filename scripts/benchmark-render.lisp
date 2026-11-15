;;;; Deterministic renderer benchmark for local regression investigation.

(require :asdf)

(let ((root (uiop:pathname-parent-directory-pathname *load-pathname*)))
  (asdf:load-asd (merge-pathnames #p"cl-asciiquarium.asd" root)))

(asdf:load-system "cl-asciiquarium")

(defparameter +benchmark-width+ 160)
(defparameter +benchmark-height+ 48)
(defparameter +benchmark-fish-count+ 200)
(defparameter +benchmark-frames+ 5000)
(defparameter +benchmark-samples+ 7)
(defparameter +benchmark-full-redraw-creature-count+ 64)

(defmacro %measure-per-iteration (iterations &body body)
  "Evaluate BODY and return milliseconds and bytes allocated per ITERATIONS."
  (let ((count (gensym "COUNT"))
        (start-time (gensym "START-TIME"))
        (start-consed (gensym "START-CONSED")))
    `(let ((,count ,iterations))
       (sb-ext:gc :full t)
       (let ((,start-time (get-internal-real-time))
             (,start-consed (sb-ext:get-bytes-consed)))
         ,@body
         (values (* 1000.0d0
                    (/ (- (get-internal-real-time) ,start-time)
                       internal-time-units-per-second
                       ,count))
                 (round (/ (- (sb-ext:get-bytes-consed) ,start-consed)
                           ,count)))))))

(defun %median (samples)
  (nth (floor (length samples) 2) (sort (copy-list samples) #'<)))

(defun %report-benchmark (label time-unit iteration-unit elapsed allocations)
  (format t "~&~A: median ~,3F ~A (min ~,3F, max ~,3F), ~:D bytes/~A (~D samples x ~D iterations)~%"
          label
          (%median elapsed)
          time-unit
          (apply #'min elapsed)
          (apply #'max elapsed)
          (%median allocations)
          iteration-unit
          +benchmark-samples+
          +benchmark-frames+))

(defun make-benchmark-world (&key predatorp)
  (let ((cl:*random-state* (sb-ext:seed-random-state 424242)))
    (let ((world (cl-asciiquarium:make-world :width +benchmark-width+
                                             :height +benchmark-height+
                                             :fish-count +benchmark-fish-count+)))
      (when predatorp
        (let ((shark (cl-asciiquarium:make-shark world :facing :right)))
          (setf (cl-tty-kit:entity-x (cl-asciiquarium::creature-entity shark)) 0
                (cl-tty-kit:entity-y (cl-asciiquarium::creature-entity shark)) 0
                (cl-tty-kit:entity-dx (cl-asciiquarium::creature-entity shark)) 0)
          (cl-asciiquarium::%add-world-creature world shark)))
      world)))

  (defun benchmark-renderer (label advancep)
  (let ((elapsed nil)
        (allocations nil))
    (dotimes (sample +benchmark-samples+)
      (declare (ignore sample))
      (let* ((world (make-benchmark-world))
             (renderer (cl-tty-kit:make-renderer +benchmark-width+ +benchmark-height+))
             (stream (make-broadcast-stream)))
        (cl-asciiquarium:render-frame renderer world :stream stream)
        (multiple-value-bind (milliseconds bytes)
            (%measure-per-iteration +benchmark-frames+
              (loop repeat +benchmark-frames+
                    do (when advancep
                         (cl-asciiquarium:world-advance world))
                       (cl-asciiquarium:render-frame renderer world :stream stream)))
          (cl-asciiquarium:shutdown-renderer renderer)
          (push milliseconds elapsed)
          (push bytes allocations))))
      (%report-benchmark label "ms/frame" "frame" elapsed allocations)))

  (defun benchmark-full-redraw (label)
    "Measure a changed-world repaint without simulation-side allocations."
    (let ((elapsed nil)
          (allocations nil))
      (dotimes (sample +benchmark-samples+)
        (declare (ignore sample))
        (let* ((world (make-benchmark-world)) (renderer (cl-tty-kit:make-renderer +benchmark-width+ +benchmark-height+)) (stream (make-broadcast-stream)) (moving-creatures (loop for creature in (cl-asciiquarium::world-%creatures world) repeat +benchmark-full-redraw-creature-count+ collect creature))) (cl-asciiquarium:render-frame renderer world :stream stream) (multiple-value-bind (milliseconds bytes) (%measure-per-iteration +benchmark-frames+ (loop repeat +benchmark-frames+ do (dolist (creature moving-creatures) (incf (cl-tty-kit:entity-x (cl-asciiquarium::creature-entity creature)))) (cl-asciiquarium:render-frame renderer world :stream stream))) (cl-asciiquarium:shutdown-renderer renderer) (push milliseconds elapsed) (push bytes allocations))))
      (%report-benchmark label "ms/frame" "frame" elapsed allocations)))

(defparameter +benchmark-output-frames+ 100
  "Frames each output-size measurement averages over. The waterline, ripple,
and current animate on their own periods, so one frame's size depends on
which phase it lands on; a fixed run of frames from the same seeded start
gives a comparable mean.")

(defun %frame-output-bytes (renderer world)
  (length
   (sb-ext:string-to-octets
    (with-output-to-string (stream)
      (cl-asciiquarium:render-frame renderer world :stream stream))
    :external-format :utf-8)))

(defun %benchmark-output-bytes (label step)
  "Render the seeded benchmark world once, then +BENCHMARK-OUTPUT-FRAMES+ more
times, calling STEP (a function of the world and its first
+BENCHMARK-FULL-REDRAW-CREATURE-COUNT+ creatures) before each. Report and
return the total UTF-8 bytes those frames write to the terminal."
  (let* ((world (make-benchmark-world))
         (renderer (cl-tty-kit:make-renderer +benchmark-width+ +benchmark-height+))
         (moving-creatures
           (loop for creature in (cl-asciiquarium::world-%creatures world)
                 repeat +benchmark-full-redraw-creature-count+
                 collect creature))
         (total 0))
    (unwind-protect
         (progn
           (cl-asciiquarium:render-frame renderer world :stream (make-broadcast-stream))
           ;; WORLD-ADVANCE draws from *RANDOM-STATE*; a fixed seed makes
           ;; every run, before and after a change, render the same frames.
           (let ((cl:*random-state* (sb-ext:seed-random-state 4242)))
             (dotimes (frame +benchmark-output-frames+)
               (funcall step world moving-creatures)
               (incf total (%frame-output-bytes renderer world)))))
      (cl-asciiquarium:shutdown-renderer renderer))
    (format t "~&~A output: mean ~,1F bytes/frame (~:D bytes over ~D frames)~%"
            label (/ total +benchmark-output-frames+) total +benchmark-output-frames+)
    total))

(defun benchmark-update-loop (label &key predatorp)
  (let ((elapsed nil)
        (allocations nil))
    (dotimes (sample +benchmark-samples+)
      (declare (ignore sample))
      (let ((world (make-benchmark-world :predatorp predatorp)))
        (multiple-value-bind (milliseconds bytes)
            (%measure-per-iteration +benchmark-frames+
              (loop repeat +benchmark-frames+
                    do (cl-asciiquarium:world-advance world)))
          (push milliseconds elapsed)
          (push bytes allocations))))
    (%report-benchmark label "ms/tick" "tick" elapsed allocations)))

  (benchmark-renderer "Steady renderer" nil)
  (benchmark-full-redraw "Changed-world renderer")
  (benchmark-renderer "Advanced renderer" t)
(benchmark-update-loop "Update loop without predator")
(benchmark-update-loop "Update loop with predator" :predatorp t)
  (unless (zerop (%benchmark-output-bytes "Steady renderer"
                                         (lambda (world moving) (declare (ignore world moving)))))
    (error "Expected every steady renderer frame to write 0 bytes."))
  (%benchmark-output-bytes "Changed-world renderer"
                           (lambda (world moving)
                             (declare (ignore world))
                             (dolist (creature moving)
                               (incf (cl-tty-kit:entity-x
                                      (cl-asciiquarium::creature-entity creature))))))
(%benchmark-output-bytes "Advanced renderer"
                         (lambda (world moving)
                           (declare (ignore moving))
                           (cl-asciiquarium:world-advance world)))
(defparameter +worst-case-seed+ 590)
(defparameter +worst-case-frames+ 300)

(defun %worst-case-kind-count (world kind)
  (count kind
         (cl-asciiquarium::world-%creatures world)
         :key #'cl-asciiquarium::creature-kind
         :test #'eq))

(defun %validate-worst-case-world (world)
  (unless (and (= 40 (%worst-case-kind-count world :fish))
               (= 2 (cl-asciiquarium::big-event-count world))
               (= 1 (%worst-case-kind-count world :sub))
               (= 1 (%worst-case-kind-count world :dinghy))
               (= 1 (%worst-case-kind-count world :diver))
               (= 1 (%worst-case-kind-count world :rope))
               (eq :moonlight (cl-asciiquarium::world-theme world))
               (eq :storm (cl-asciiquarium::world-weather world)))
    (error "Worst case benchmark scene was not preserved."))
  world)

(defun %make-worst-case-world ()
  (let ((world (cl-asciiquarium:make-world :width 160
                                           :height 48
                                           :fish-count 40
                                           :max-fish 40)))
    (cl-asciiquarium::world-change-daypart world :moonlight)
    (cl-asciiquarium::world-advance-weather world)
    (cl-asciiquarium::world-advance-weather world)
    (cl-asciiquarium::spawn-submarine-now world)
    (unless (cl-asciiquarium::spawn-diver-now world)
      (error "Worst case benchmark could not spawn a diver."))
    (dotimes (tick 100)
      (declare (ignore tick))
      (cl-asciiquarium:world-advance world))
    (%validate-worst-case-world world)))

(defun benchmark-worst-case ()
  (let ((elapsed nil)
        (allocations nil)
        (terminal-output nil))
    (dotimes (sample +benchmark-samples+)
      (declare (ignore sample))
      (let* ((*random-state* (sb-ext:seed-random-state +worst-case-seed+))
             (world (%make-worst-case-world))
             (renderer (cl-tty-kit:make-renderer 160 48))
             (stream (make-broadcast-stream)))
        (unwind-protect
             (progn
               (cl-asciiquarium:render-frame renderer world :stream stream)
               (multiple-value-bind (milliseconds bytes)
                   (%measure-per-iteration +worst-case-frames+
                     (loop repeat +worst-case-frames+
                           do (cl-asciiquarium:world-advance world)
                              (cl-asciiquarium:render-frame renderer world :stream stream)))
                 (%validate-worst-case-world world)
                 (push milliseconds elapsed)
                 (push bytes allocations)))
          (cl-asciiquarium:shutdown-renderer renderer)))
      (let* ((*random-state* (sb-ext:seed-random-state +worst-case-seed+))
             (world (%make-worst-case-world))
             (renderer (cl-tty-kit:make-renderer 160 48))
             (total 0))
        (unwind-protect
             (progn
               (cl-asciiquarium:render-frame renderer world :stream (make-broadcast-stream))
               (dotimes (frame +worst-case-frames+)
                 (declare (ignore frame))
                 (cl-asciiquarium:world-advance world)
                 (incf total (%frame-output-bytes renderer world)))
               (%validate-worst-case-world world)
               (push (/ total (coerce +worst-case-frames+ 'double-float)) terminal-output))
          (cl-asciiquarium:shutdown-renderer renderer))))
    (format t
            "~&Worst case: median ~,3F ms/frame, ~:D bytes/frame, ~,1F terminal output bytes/frame (~D samples x ~D frames)~%"
            (%median elapsed)
            (%median allocations)
            (%median terminal-output)
            +benchmark-samples+
            +worst-case-frames+)))

(benchmark-worst-case)
