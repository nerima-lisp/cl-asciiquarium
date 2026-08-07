;;;; src/render-state.lisp -- private incremental-renderer state and dirty regions.
(in-package #:cl-asciiquarium)

(defstruct (%creature-render-snapshot
    (:constructor
      %make-creature-render-snapshot
      (x y width height runs frame-index facing z)))
  x
  y
  width
  height
  runs
  frame-index
  facing
  z
  (seen-generation 0))

(defstruct (%dirty-rectangles
    (:constructor %make-dirty-rectangles (&optional (capacity 16))))
  (data (make-array capacity :element-type 'fixnum))
  (count 0 :type fixnum))

(defstruct (%renderer-frame-state
    (:constructor
      %make-renderer-frame-state
      (width height snapshots render-order dirty-rectangles generation last-world-tick)))
  width
  height
  snapshots
  render-order
  dirty-rectangles
  generation
  last-world-tick)

;; A weak key prevents renderer-specific snapshots from retaining a renderer.
(defvar *renderer-frame-states* (make-hash-table :test #'eq :weakness :key))

;; Measurements show dirty-region composition wins through six changed creatures;
;; beyond that, redrawing the whole world is faster.
(defconstant +render-frame-full-redraw-change-threshold+ 6)

(defun %snapshot-creature-for-rendering (creature)
  (multiple-value-bind (x y width height) (creature-bounds creature)
    (let ((frame-index (creature-frame-index creature))
          (facing (creature-facing creature)))
      (%make-creature-render-snapshot
       x y width height
       (if (eq facing :left)
           (aref (creature-%mirrored-frame-runs creature) frame-index)
           (aref (creature-%frame-runs creature) frame-index))
       frame-index facing (creature-z creature)))))

(defun %creature-render-snapshot-current-p (snapshot creature)
  (multiple-value-bind (x y width height) (%creature-bounds-current creature)
    (let* ((frame-index (creature-frame-index creature))
           (facing (creature-facing creature))
           (runs (if (eq facing :left)
                     (aref (creature-%mirrored-frame-runs creature) frame-index)
                     (aref (creature-%frame-runs creature) frame-index)))
           (z (creature-z creature)))
      (values
       (and (= (%creature-render-snapshot-x snapshot) x)
            (= (%creature-render-snapshot-y snapshot) y)
            (= (%creature-render-snapshot-width snapshot) width)
            (= (%creature-render-snapshot-height snapshot) height)
            (eq (%creature-render-snapshot-runs snapshot) runs)
            (= (%creature-render-snapshot-frame-index snapshot) frame-index)
            (eq (%creature-render-snapshot-facing snapshot) facing)
            (= (%creature-render-snapshot-z snapshot) z))
       x y width height runs frame-index facing z))))

(defun %reset-dirty-rectangles (rectangles)
  (setf (%dirty-rectangles-count rectangles) 0)
  rectangles)

(defun %ensure-dirty-rectangle-capacity (rectangles required)
  (let ((data (%dirty-rectangles-data rectangles)))
    (when (< (length data) required)
      (let ((replacement
              (make-array (max required (* 2 (length data))) :element-type 'fixnum)))
        (replace replacement data)
        (setf (%dirty-rectangles-data rectangles) replacement
              data replacement)))
    data))

(defun %add-dirty-rectangle (rectangles left top right bottom)
  (let ((index 0)
        (count (%dirty-rectangles-count rectangles))
        (data (%dirty-rectangles-data rectangles)))
    (loop while (< index count)
          for offset = (* index 4)
          for existing-left = (aref data offset)
          for existing-top = (aref data (1+ offset))
          for existing-right = (+ existing-left (aref data (+ offset 2)))
          for existing-bottom = (+ existing-top (aref data (+ offset 3)))
          do (if (and (<= left existing-right) (<= existing-left right)
                      (<= top existing-bottom) (<= existing-top bottom))
                 (progn
                   (setf left (min left existing-left)
                         top (min top existing-top)
                         right (max right existing-right)
                         bottom (max bottom existing-bottom))
                   (let ((last-offset (* (1- count) 4)))
                     (setf (aref data offset) (aref data last-offset)
                           (aref data (1+ offset)) (aref data (1+ last-offset))
                           (aref data (+ offset 2)) (aref data (+ last-offset 2))
                           (aref data (+ offset 3)) (aref data (+ last-offset 3))))
                   (decf count)
                   (setf index 0))
                 (incf index)))
    (setf data (%ensure-dirty-rectangle-capacity rectangles (* 4 (1+ count))))
    (let ((offset (* count 4)))
      (setf (aref data offset) left
            (aref data (1+ offset)) top
            (aref data (+ offset 2)) (- right left)
            (aref data (+ offset 3)) (- bottom top)))
    (setf (%dirty-rectangles-count rectangles) (1+ count))
    rectangles))

(defun %add-clipped-dirty-rectangle (rectangles snapshot screen-width screen-height)
  (let* ((left (max 0 (%creature-render-snapshot-x snapshot)))
         (top (max 0 (%creature-render-snapshot-y snapshot)))
         (right (min screen-width
                     (+ (%creature-render-snapshot-x snapshot)
                        (%creature-render-snapshot-width snapshot))))
         (bottom (min screen-height
                      (+ (%creature-render-snapshot-y snapshot)
                         (%creature-render-snapshot-height snapshot)))))
    (when (and (< left right) (< top bottom))
      (%add-dirty-rectangle rectangles left top right bottom))
    rectangles))

(defun %render-orders-equal-p (left right)
  (or (eq left right)
      (and (= (length left) (length right))
           (loop for left-creature in left
                 for right-creature in right
                 always (eq left-creature right-creature)))))
