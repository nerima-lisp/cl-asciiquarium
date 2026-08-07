(in-package #:cl-asciiquarium)

(defparameter *static-sprite-prototypes* (make-hash-table :test #'eq)
  "Maps static creature kinds to colored and monochrome prepared sprites.")

(defun %static-sprite-prototype (kind art color)
  "Return KIND's immutable prepared sprite for the active color mode."
  (let* ((prototypes
           (or (gethash kind *static-sprite-prototypes*)
               (setf (gethash kind *static-sprite-prototypes*)
                     (make-array 2 :initial-element nil))))
         (index (if *monochrome* 0 1)))
    (or (aref prototypes index)
        (setf (aref prototypes index)
              (make-creature :kind kind
                             :frames (list (copy-seq art))
                             :style (unless *monochrome* (solid-style color))
                             :x 0
                             :y 0
                             :policy :none)))))

(defun %sprite-blit-runs (text style)
  "Prepare non-space horizontal runs as flat X, Y, SCREEN, WIDTH quadruples."
  (let ((run-count 0)
        (in-run nil))
    (loop for character across text
          do (cond
        ((char= character #\Newline)
          (setf in-run nil))
        ((char= character #\Space)
          (setf in-run nil))
        ((not in-run)
          (incf run-count)
          (setf in-run t))))
    (let ((runs (make-array (* 4 run-count)))
          (run-index 0)
          (row 0)
          (line-start 0)
          (text-length (length text)))
      (loop for line-end = (or (position #\Newline text :start line-start) text-length)
            do (loop with column = 0
              while (< column (- line-end line-start))
              do (if (char= #\Space (char text (+ line-start column))) (incf column)
            (let* ((run-start column)
                   (run-end
                  (or
                    (position #\Space text :start (+ line-start run-start) :end line-end)
                    line-end))
                   (run-text (subseq text (+ line-start run-start) run-end))
                   (source (make-screen (length run-text) 1)))
              (dotimes (offset (length run-text))
                (cl-tty-kit:screen-put-cell source offset 0 (char run-text offset) :style style))
              (setf (svref runs run-index) run-start
                    (svref runs (1+ run-index)) row
                    (svref runs (+ 2 run-index)) source
                    (svref runs (+ 3 run-index)) (length run-text))
              (incf run-index 4)
              (setf column (- run-end line-start))))) (when (= line-end text-length)
          (return runs)) (setf line-start (1+ line-end)) (incf row)))))

(defun %copy-creature-frames (frames)
  (map
    (quote simple-vector)
    (lambda (frame)
      (copy-seq frame))
    frames))

(defun %rebuild-creature-blit-runs (creature)
  (let* ((count (length (creature-%frames creature)))
         (normal (make-array count))
         (mirrored (make-array count))
         (style (creature-%style creature)))
    (dotimes (index count)
      (setf (aref normal index) (%sprite-blit-runs (aref (creature-%frames creature) index) style)
            (aref mirrored index) (%sprite-blit-runs (aref (creature-%mirrored-frames creature) index) style)))
    (setf (creature-%frame-runs creature) normal
          (creature-%mirrored-frame-runs creature) mirrored)
    creature))

(defun %rebuild-creature-frame-caches (creature)
  (let* ((frames (creature-%frames creature))
         (count (length frames))
         (mirrored (make-array count))
         (widths (make-array count))
         (heights (make-array count)))
    (when (zerop count)
      (error "CREATURE-FRAMES must contain at least one frame."))
    (dotimes (index count)
      (let ((frame (aref frames index)))
        (setf (aref mirrored index) (mirror-sprite-text frame))
        (multiple-value-bind (width height) (sprite-dimensions frame)
          (setf (aref widths index) width
                (aref heights index) height))))
    (setf (creature-%mirrored-frames creature) mirrored
          (creature-%frame-widths creature) widths
          (creature-%frame-heights creature) heights
          (creature-frame-index creature) (mod (creature-frame-index creature) count))
    (%rebuild-creature-blit-runs creature)))

(defun %set-creature-frames (creature frames)
  (let ((frame-vector (%copy-creature-frames (coerce frames 'simple-vector))))
    (when (zerop (length frame-vector))
      (error "CREATURE-FRAMES must contain at least one frame."))
    (setf (creature-%frames creature) frame-vector)
    (%rebuild-creature-frame-caches creature)
    frames))

(defun %set-creature-style (creature style)
  (setf (creature-%style creature) (copy-tree style))
  (%rebuild-creature-blit-runs creature)
  style)

(defun %creature-dimensions-current (creature)
  (let ((index (creature-frame-index creature)))
    (values
      (aref (creature-%frame-widths creature) index)
      (aref (creature-%frame-heights creature) index))))

(defun %creature-bounds-current (creature)
  (multiple-value-bind (width height) (%creature-dimensions-current creature)
    (values
      (round (creature-x creature))
      (round (creature-y creature))
      width
      height)))
