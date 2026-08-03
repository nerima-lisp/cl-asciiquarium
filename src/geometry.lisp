;;;; src/geometry.lisp -- sprite text helpers shared by every creature kind.
;;;;
;;;; Nothing here is aquarium-specific: splitting sprite text into lines,
;;;; measuring it, and mirroring it left-to-right are generic operations that
;;;; every creature (fish, shark, ship, ...) reuses instead of each defining
;;;; its own. This is the "one shape" scope-discipline rule applied one level
;;;; below CREATURE itself.
(in-package #:cl-asciiquarium)

(defun clamp (value low high)
  "Return VALUE clamped to the inclusive range [LOW, HIGH]."
  (max low (min high value)))

(defun split-sprite-lines (text)
  "Split TEXT on #\\Newline into a list of lines, mirroring cl-tty-kit's own
internal sprite line-splitter (not exported, so reimplemented here)."
  (loop with start = 0
        with lines = '()
        for newline-position = (position #\Newline text :start start)
        do (push (subseq text start (or newline-position (length text))) lines)
           (if newline-position
               (setf start (1+ newline-position))
               (return (nreverse lines)))))

(defun sprite-dimensions (text)
  "Return (VALUES WIDTH HEIGHT) for multi-line sprite TEXT: HEIGHT is the
number of lines, WIDTH the length of the longest one."
  (let ((lines (split-sprite-lines text)))
    (values (reduce #'max lines :key #'length :initial-value 0)
            (length lines))))

(defparameter +mirror-char-table+
  '((#\( . #\)) (#\) . #\()
    (#\< . #\>) (#\> . #\<)
    (#\/ . #\\) (#\\ . #\/)
    (#\[ . #\]) (#\] . #\[)
    (#\{ . #\}) (#\} . #\{))
  "Maps a directional glyph to the glyph it should become when its sprite is
mirrored left-to-right. A character absent from this table (letters, digits,
symmetric glyphs) mirrors to itself.")

(defun mirror-char (char)
  "Return CHAR's mirror-image glyph per +MIRROR-CHAR-TABLE+, or CHAR itself."
  (or (cdr (assoc char +mirror-char-table+ :test #'char=)) char))

(defun mirror-line (line)
  "Return LINE reversed with every character mirrored via MIRROR-CHAR."
  (map 'string #'mirror-char (reverse line)))

(defun mirror-sprite-text (text)
  "Return multi-line sprite TEXT flipped left-to-right: each line is reversed
and its directional glyphs swapped via MIRROR-CHAR, so a creature authored
facing right can reuse the same art facing left instead of a second hand-drawn
copy."
  (format nil "~{~A~^~%~}" (mapcar #'mirror-line (split-sprite-lines text))))

(defun sprite-width (text)
  "Return only the WIDTH of SPRITE-DIMENSIONS, for the common case of an
off-screen spawn point that needs just the horizontal extent."
  (nth-value 0 (sprite-dimensions text)))

(defun rects-overlap-p (ax ay aw ah bx by bw bh)
  "Return true when the two axis-aligned boxes (AX, AY, AW, AH) and
(BX, BY, BW, BH) overlap. Touching edges do not count as overlap."
  (and (< ax (+ bx bw)) (< bx (+ ax aw))
       (< ay (+ by bh)) (< by (+ ay ah))))

(defun random-between (low high)
  "Return a random integer in the inclusive range [LOW, HIGH], drawn from the
ambient CL:*RANDOM-STATE* so callers (and tests, via SB-EXT:SEED-RANDOM-STATE)
control reproducibility by binding *RANDOM-STATE*, never by this function
holding its own generator."
  (+ low (random (1+ (- high low)))))

(defun random-facing ()
  "Return :LEFT or :RIGHT with equal probability, from the ambient
CL:*RANDOM-STATE* (see RANDOM-BETWEEN). Every off-screen crossing factory
(MAKE-FISH, MAKE-SHARK, MAKE-SHIP, MAKE-DUCK-LINE) draws its default FACING
this same way."
  (if (zerop (random 2)) :left :right))

(defun off-screen-entry (facing art-width world-width speed)
  "Return (VALUES X DX) placing a creature fully off WORLD-WIDTH on the edge
opposite FACING (:LEFT or :RIGHT), moving at SPEED toward the far edge so it
visibly crosses the screen. Shared by every off-screen crossing factory
(MAKE-SHARK, MAKE-SHIP, MAKE-DUCK-LINE): a :RIGHT-facing creature starts
ART-WIDTH off the left edge moving right; a :LEFT-facing one starts at
WORLD-WIDTH moving left."
  (if (eq facing :right)
      (values (- art-width) speed)
      (values world-width (- speed))))
