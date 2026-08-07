(in-package #:cl-asciiquarium)

(defun %sprite-blit-runs (text style)
  "Prepare non-space horizontal runs as flat X, Y, SCREEN triples."
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
    (let ((runs (make-array (* 3 run-count)))
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
                    (svref runs (+ 2 run-index)) source)
              (incf run-index 3)
              (setf column (- run-end line-start))))) (when (= line-end text-length)
          (return runs)) (setf line-start (1+ line-end)) (incf row)))))

(defun %copy-creature-frames (frames)
  (map
    (quote simple-vector)
    (lambda (frame)
      (copy-seq frame))
    frames))

(defun %materialize-creature-frames (creature)
  (when (creature-%frames-shared-p creature)
    (setf (creature-%frames creature) (%copy-creature-frames (creature-%frames creature))
          (creature-%frames-shared-p creature) nil))
  creature)

(defun %materialize-creature-style (creature)
  (when (creature-%style-shared-p creature)
    (setf (creature-%style creature) (copy-tree (creature-%style creature))
          (creature-%style-shared-p creature) nil))
  creature)

(defun %rebuild-creature-blit-runs (creature)
  (let* ((count (length (creature-%frames creature)))
         (normal (make-array count))
         (mirrored (make-array count))
         (style (creature-%style creature)))
    (dotimes (index count)
      (setf (aref normal index) (%sprite-blit-runs (aref (creature-%frames creature) index) style)
            (aref mirrored index) (%sprite-blit-runs (aref (creature-%mirrored-frames creature) index) style)))
    (setf (creature-%frame-runs creature) normal
          (creature-%mirrored-frame-runs creature) mirrored
          (creature-%prepared-frames creature) (%copy-creature-frames (creature-%frames creature))
          (creature-%prepared-style creature) (copy-tree style))
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

(defun %ensure-creature-caches-current (creature)
  (cond
    ((and
        (creature-%frames-escaped-p creature)
        (let ((frames (creature-%frames creature))
              (prepared-frames (creature-%prepared-frames creature)))
          (not
            (and
              (= (length frames) (length prepared-frames))
              (loop for frame across frames
                    for prepared-frame across prepared-frames
                    always (string= frame prepared-frame))))))
      (%rebuild-creature-frame-caches creature)
      (values creature t))
    ((and
        (creature-%style-escaped-p creature)
        (not (equal (creature-%style creature) (creature-%prepared-style creature))))
      (%rebuild-creature-blit-runs creature)
      (values creature t))
    (t
      (values creature nil))))

(defun %set-creature-frames (creature frames &key (escaped-p nil escaped-p-supplied-p))
  (let ((frame-vector (coerce frames 'simple-vector)))
    (when (zerop (length frame-vector))
      (error "CREATURE-FRAMES must contain at least one frame."))
    (setf (creature-%frames creature) frame-vector
          (creature-%frames-shared-p creature) nil
          (creature-%frames-escaped-p creature) (if escaped-p-supplied-p escaped-p
        (creature-%frames-escaped-p creature)))
    (%rebuild-creature-frame-caches creature)
    frames))

(defun %set-creature-style (creature style &key (escaped-p nil escaped-p-supplied-p))
  (setf (creature-%style creature) style
        (creature-%style-shared-p creature) nil
        (creature-%style-escaped-p creature) (if escaped-p-supplied-p escaped-p
      (creature-%style-escaped-p creature)))
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
