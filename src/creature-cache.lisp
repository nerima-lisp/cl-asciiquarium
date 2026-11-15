(in-package #:cl-asciiquarium)

(defun %frame-vector (frames)
  (etypecase frames
    (string (vector frames))
    (list (coerce frames 'simple-vector))
    (vector (coerce frames 'simple-vector))))

(declaim (inline %sprite-cell-opaque-p))
(defun %sprite-cell-opaque-p (art-line mask-line column)
  (or (char/= #\Space (char art-line column))
      (and mask-line (char/= #\Space (char mask-line column)))))

(defun %masked-space-style (style)
  "Return the style a masked space cell takes from its role STYLE: STYLE's
foreground color as the cell's background, so the masked area reads as a solid
fill (a cloud's body, a sand band, the status bar). STYLE is returned as is
when it carries no background, which is how the :ANSI16 and :MONO modes keep
their promise never to paint one."
  (let ((foreground (find :fg style :key (lambda (item) (and (consp item) (first item)))))
        (background-p (find :bg style :key (lambda (item) (and (consp item) (first item))))))
    (if (and foreground background-p)
        (make-style (cons :bg (rest foreground)))
        style)))

(defun %sprite-run-screen (art-line mask-line start end style role-styles)
  (let ((source (make-screen (- end start) 1)))
    (loop for column from start below end
          for character = (char art-line column)
          for mask-character = (and mask-line (char mask-line column))
          do (screen-put-cell
              source (- column start) 0 character
              :style (cond
                       ((or (null mask-character) (char= #\Space mask-character)) style)
                       ((char= #\Space character)
                        (%masked-space-style (cdr (assoc mask-character role-styles))))
                       (t (cdr (assoc mask-character role-styles))))))
    source))

(defun %sprite-blit-runs (text style &optional mask role-styles)
  "Prepare opaque horizontal runs of TEXT as flat X, Y, SCREEN triples. Without
MASK a cell is opaque exactly when its character is not a space, and every
cell takes STYLE. With MASK (already validated against TEXT's line shape, see
%VALIDATE-CREATURE-MASKS) a cell is also opaque when its mask character is not
a space, and such a cell takes the style ROLE-STYLES maps that character to.
Resolving each cell's style here, once per prepared frame, is what keeps
per-character coloring off the render path."
  (let ((runs '())
        (mask-lines (and mask (split-sprite-lines mask))))
    (loop for art-line in (split-sprite-lines text)
          for row from 0
          for mask-line = (pop mask-lines)
          for width = (length art-line)
          do (loop with column = 0
                   while (< column width)
                   do (if (%sprite-cell-opaque-p art-line mask-line column)
                          (let ((end (or (loop for index from column below width
                                               unless (%sprite-cell-opaque-p
                                                       art-line mask-line index)
                                                 return index)
                                         width)))
                            (push column runs)
                            (push row runs)
                            (push (%sprite-run-screen art-line mask-line column end
                                                      style role-styles)
                                  runs)
                            (setf column end))
                          (incf column))))
    (coerce (nreverse runs) 'simple-vector)))

(defun %validate-creature-masks (frames masks role-styles)
  "Signal ASCIIQUARIUM-INVALID-MASK unless MASKS has one mask per frame of
FRAMES, each with the same number of lines and the same length per line, and
every non-space mask character has a ROLE-STYLES entry."
  (unless (= (length masks) (length frames))
    (error 'asciiquarium-invalid-mask
           :frame-index (length frames) :line nil
           :detail (format nil "~D masks for ~D frames"
                           (length masks) (length frames))))
  (loop for frame across frames
        for mask across masks
        for frame-index from 0
        for art-lines = (split-sprite-lines frame)
        for mask-lines = (split-sprite-lines mask)
        do (unless (= (length art-lines) (length mask-lines))
             (error 'asciiquarium-invalid-mask
                    :frame-index frame-index :line nil
                    :detail (format nil "~D mask lines for ~D art lines"
                                    (length mask-lines) (length art-lines))))
           (loop for art-line in art-lines
                 for mask-line in mask-lines
                 for line from 0
                 do (unless (= (length art-line) (length mask-line))
                      (error 'asciiquarium-invalid-mask
                             :frame-index frame-index :line line
                             :detail (format nil "mask is ~D wide, art is ~D"
                                             (length mask-line) (length art-line))))
                    (loop for character across mask-line
                          unless (or (char= character #\Space)
                                     (assoc character role-styles))
                            do (error 'asciiquarium-invalid-mask
                                      :frame-index frame-index :line line
                                      :detail (format nil "mask character ~S has no role style"
                                                      character)))))
  masks)

(defun %copy-creature-frames (frames)
  (map
    (quote simple-vector)
    (lambda (frame)
      (copy-seq frame))
    frames))

(defun %materialize-creature-frames (creature)
  (when (or (creature-%frames-shared-p creature)
            (not (creature-%frames-escaped-p creature)))
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
         (style (creature-%style creature))
         (masks (creature-%masks creature))
         (mirrored-masks (creature-%mirrored-masks creature))
         (role-styles (creature-%role-styles creature)))
    (dotimes (index count)
      (setf (aref normal index)
            (%sprite-blit-runs (aref (creature-%frames creature) index) style
                               (and masks (aref masks index)) role-styles)
            (aref mirrored index)
            (%sprite-blit-runs (aref (creature-%mirrored-frames creature) index) style
                               (and mirrored-masks (aref mirrored-masks index))
                               role-styles)))
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
      (error 'asciiquarium-invalid-argument :value frames :expected "at least one sprite frame"))
    (dotimes (index count)
      (let ((frame (aref frames index)))
        (setf (aref mirrored index) (mirror-sprite-text frame))
        (multiple-value-bind (width height) (sprite-dimensions frame)
          (setf (aref widths index) width
                (aref heights index) height))))
    (setf (creature-%mirrored-frames creature) mirrored
          (creature-%mirrored-masks creature) (let ((masks (creature-%masks creature)))
                                                (and masks
                                                     (%validate-creature-masks
                                                      frames masks
                                                      (creature-%role-styles creature))
                                                     (map 'simple-vector
                                                          #'mirror-sprite-mask
                                                          masks)))
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

(defun %set-creature-frames (creature frames &key (escaped-p nil escaped-p-supplied-p)
                                                 masks role-styles)
  "Replace CREATURE's frames and rebuild every derived cache. MASKS and
ROLE-STYLES replace the previous ones too, so new frames without MASKS draw
unmasked in the creature's STYLE (KILL-FISH's death frame relies on this)."
  (let ((frame-vector (if *ascii*
                          (map 'simple-vector #'ascii-text frames)
                          (coerce frames 'simple-vector))))
    (when (zerop (length frame-vector))
      (error 'asciiquarium-invalid-argument :value frames :expected "at least one sprite frame"))
    (setf (creature-%frames creature) frame-vector
          (creature-%frames-shared-p creature) nil
          (creature-%masks creature) (and masks (coerce masks 'simple-vector))
          (creature-%role-styles creature) (and masks role-styles)
          (creature-%frames-escaped-p creature) (if escaped-p-supplied-p escaped-p
        (creature-%frames-escaped-p creature)))
    (%rebuild-creature-frame-caches creature)
    frames))

(defvar *recolored-sprite-prototypes* (make-hash-table :test #'equal)
  "Recolored prototypes for private fixed art only. Variable art and public
frame aliases are rebuilt in place. %DECOR-PROTOTYPE clears this table when
screen dimensions change, alongside the background prototypes.")

(defun %recolored-sprite-prototype (frames masks style role-styles)
  (let* ((frame-key (coerce frames 'list))
         (mask-key (coerce masks 'list))
         (key (list frame-key mask-key style role-styles)))
    (declare (dynamic-extent key))
    (or (gethash key *recolored-sprite-prototypes*)
        (let ((prototype
                (make-creature :kind :recolored-sprite-prototype
                               :frames (%copy-creature-frames frames)
                               :masks (and masks (%copy-creature-frames masks))
                               :style (copy-tree style) :role-styles (copy-tree role-styles)
                               :%trusted-frames-p t :%trusted-style-p t
                               :x 0 :y 0 :policy :none)))
          ;; Keys own their strings and styles: a public frames/style alias
          ;; must never mutate a key already stored in the table.
          (setf (first key) (coerce (creature-%frames prototype) 'list)
                (second key) (coerce (creature-%masks prototype) 'list)
                (third key) (creature-%style prototype)
                (fourth key) (creature-%role-styles prototype)
                (gethash (copy-list key) *recolored-sprite-prototypes*) prototype)))))

(defun %set-creature-colors (creature &key style role-styles)
  (%ensure-creature-caches-current creature)
  (setf (creature-%style creature) style
        (creature-%style-shared-p creature) nil
        (creature-%role-styles creature) (and (creature-%masks creature) role-styles))
  (%rebuild-creature-blit-runs creature)
  creature)


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

(defun %set-fixed-creature-colors (creature &key style role-styles)
  ;; Only fixed internal art may enter the shared table. Public frame aliases
  ;; can change indefinitely, even after a previous successful recoloring.
  (when (creature-%frames-escaped-p creature)
    (return-from %set-fixed-creature-colors
      (%set-creature-colors creature :style style :role-styles role-styles)))
  (let ((frames (creature-%frames creature))
        (shared-p (creature-%frames-shared-p creature)))
    (%adopt-sprite-prototype
     creature (%recolored-sprite-prototype frames (creature-%masks creature)
                                           style (and (creature-%masks creature) role-styles)))
    (setf (creature-%frames creature) frames
          (creature-%frames-shared-p creature) shared-p))
  creature)
