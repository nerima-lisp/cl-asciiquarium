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
