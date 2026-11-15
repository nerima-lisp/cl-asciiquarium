(in-package #:cl-asciiquarium)

(defun vertical-line-frames (glyph max-length)
  "Frames for a line hanging down: frame N is N lines of GLYPH, for N from 0
(a single space) to MAX-LENGTH, built up front so a tick only picks a frame
index and never builds a string."
  (loop for length from 0 to max-length
        collect (if (zerop length)
                    " "
                    (format nil "~{~A~^~%~}" (make-list length :initial-element glyph)))))

(defvar *vertical-line-prototypes* (make-hash-table :test #'equal))

(defvar *vertical-line-prototype-width* 0)

(defvar *vertical-line-prototype-height* 0)

(defun %vertical-line-capacity (world &optional line)
  (let ((capacity (world-height world)))
    (flet ((include-line (creature)
             (let ((spec (getf (creature-data creature) :line-spec)))
               (when (and spec (not (creature-removep creature)))
                 (setf capacity (max capacity (+ (second spec) (creature-frame-index creature))))))))
      (dolist (creature (world-%creatures world)) (include-line creature))
      (when line (include-line line)))
    capacity))

(defun %trim-vertical-line-prototypes (capacity)
  (maphash
   (lambda (key prototype)
     (declare (ignore key))
     (let* ((spec (getf (creature-data prototype) :line-spec))
            (count (1+ (- capacity (second spec)))))
       (when (> (length (creature-%frames prototype)) count)
         ;; Replace only the outer vectors. Existing creatures keep their
         ;; references; immutable frame strings and run screens are untouched.
         (setf (creature-%frames prototype) (subseq (creature-%frames prototype) 0 count)
               (creature-%prepared-frames prototype) (subseq (creature-%prepared-frames prototype) 0 count)
               (creature-%mirrored-frames prototype) (subseq (creature-%mirrored-frames prototype) 0 count)
               (creature-%frame-widths prototype) (subseq (creature-%frame-widths prototype) 0 count)
               (creature-%frame-heights prototype) (subseq (creature-%frame-heights prototype) 0 count)
               (creature-%frame-runs prototype) (subseq (creature-%frame-runs prototype) 0 count)
               (creature-%mirrored-frame-runs prototype) (subseq (creature-%mirrored-frame-runs prototype) 0 count)))))
   *vertical-line-prototypes*))

(defun %vertical-line-prototype (world spec &optional line)
  (unless (and (= (world-width world) *vertical-line-prototype-width*)
               (= (world-height world) *vertical-line-prototype-height*))
    (clrhash *vertical-line-prototypes*)
    (setf *vertical-line-prototype-width* (world-width world)
          *vertical-line-prototype-height* (world-height world)))
  (let* ((theme (world-theme world))
         (key (list spec theme (effective-color-mode) *ascii*))
         (prototype (gethash key *vertical-line-prototypes*))
         (capacity (%vertical-line-capacity world line))
         (count (1+ (- capacity (second spec)))))
    (declare (dynamic-extent key))
    (%trim-vertical-line-prototypes capacity)
    (if (and prototype (= (length (creature-%frames prototype)) count))
        prototype
        (setf (gethash (copy-list key) *vertical-line-prototypes*)
              (make-creature :kind :vertical-line-prototype
                             :frames (nthcdr (second spec)
                                             (vertical-line-frames (first spec) capacity))
                             :style (funcall (third spec) theme)
                             :%trusted-frames-p t :%trusted-style-p t
                             :x 0 :y 0 :policy :none :data (list :line-spec spec))))))

(defun restyle-vertical-line (world line)
  (%adopt-sprite-prototype
   line (%vertical-line-prototype world (getf (creature-data line) :line-spec) line)))

(defun refresh-vertical-lines (world)
  (dolist (creature (world-%creatures world))
    (when (getf (creature-data creature) :line-spec)
      (restyle-vertical-line world creature))))
