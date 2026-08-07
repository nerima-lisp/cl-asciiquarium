;;;; src/render.lisp -- painting a WORLD onto a cl-tty-kit SCREEN.
(in-package #:cl-asciiquarium)

(defun draw-world (screen world)
  "Clear SCREEN and paint every creature in WORLD onto it back-to-front by
CREATURE-Z, returning SCREEN. Painting order, not a z-buffer, is what
establishes layering here -- see cl-tty-kit's entity.lisp file header, which
calls this out as the intended use of SPRITE-BLIT paint order. Prepared
non-transparent runs are composited with SCREEN-BLIT without reparsing sprite
text during drawing."
  (screen-clear screen)
  (dolist (creature (%world-render-order world))
    (creature-blit screen creature))
  screen)

(defstruct (%creature-render-snapshot
            (:constructor
             %make-creature-render-snapshot
             (x y width height runs frame-index facing z))) x
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
             (width height snapshots render-order dirty-rectangles generation
              last-world-tick)))
  width
  height
  snapshots
  render-order
  dirty-rectangles
  generation
  last-world-tick)

;; A weak key prevents renderer-specific snapshots from retaining a renderer.
(defvar *renderer-frame-states* (make-hash-table :test #'eq :weakness :key))

;; The clipped-blit fast path makes work proportional to dirty area, rather
;; than to the number of changed creatures.  Recompose locally until the
;; rectangles cover at least half the screen; after that, clearing and painting
;; once is cheaper and bounds the worst case.
(defconstant +render-frame-full-redraw-area-denominator+ 2)

(defconstant +render-frame-full-redraw-rectangle-denominator+ 4)

(defun %dirty-rectangles-cover-half-screen-p (rectangles screen-width screen-height)
  (let ((data (%dirty-rectangles-data rectangles)))
    (>= (* +render-frame-full-redraw-area-denominator+
           (loop for index below (%dirty-rectangles-count rectangles)
                 for offset = (* index 4)
                 sum (* (aref data (+ offset 2)) (aref data (+ offset 3)))))
        (* screen-width screen-height))))


  (defun %dirty-rectangles-exceed-render-budget-p (rectangles render-order)
  "Whether local layer checks cost more than a single full repaint."
  (let ((rectangle-count (%dirty-rectangles-count rectangles))
        (creature-count (length render-order)))
    (and (> rectangle-count 1)
         (plusp creature-count)
         (>= (* +render-frame-full-redraw-rectangle-denominator+ rectangle-count)
             creature-count))))
  (defun %add-dirty-rectangle (rectangles left top right bottom)
  "Add a rectangle, coalescing all touching regions in the reusable buffer."
  (let ((index 0)
        (count (%dirty-rectangles-count rectangles))
        (data (%dirty-rectangles-data rectangles)))
    (loop while (< index count)
          for offset = (* index 4)
          for existing-left = (aref data offset)
          for existing-top = (aref data (1+ offset))
          for existing-right = (+ existing-left (aref data (+ offset 2)))
          for existing-bottom = (+ existing-top (aref data (+ offset 3)))
          do (if (and (<= left existing-right)
                      (<= existing-left right)
                      (<= top existing-bottom)
                      (<= existing-top bottom))
                 (progn
                   (setf left (min left existing-left)
                         top (min top existing-top)
                         right (max right existing-right)
                         bottom (max bottom existing-bottom))
                   (decf count)
                   (when (< index count)
                     (let ((last-offset (* count 4)))
                       (setf (aref data offset) (aref data last-offset)
                             (aref data (1+ offset)) (aref data (1+ last-offset))
                             (aref data (+ offset 2)) (aref data (+ last-offset 2))
                             (aref data (+ offset 3)) (aref data (+ last-offset 3)))))
                   (setf index 0))
                 (incf index)))
    (when (> (* 4 (1+ count)) (length data))
      (setf data (adjust-array data (* 2 (length data)))
            (%dirty-rectangles-data rectangles) data))
    (let ((offset (* count 4)))
      (setf (aref data offset) left
            (aref data (1+ offset)) top
            (aref data (+ offset 2)) (- right left)
            (aref data (+ offset 3)) (- bottom top)
            (%dirty-rectangles-count rectangles) (1+ count)))
    rectangles))



(defun %snapshot-creature-for-rendering (creature)
  (%ensure-creature-caches-current creature)
  (multiple-value-bind (x y width height) (creature-bounds creature)
    (let ((frame-index (creature-frame-index creature))
          (facing (creature-facing creature)))
      (%make-creature-render-snapshot
       x
       y
       width
       height
       (if (eq facing :left) (aref
                              (creature-%mirrored-frame-runs creature)
                              frame-index)
         (aref (creature-%frame-runs creature) frame-index))
       frame-index
       facing
       (creature-z creature)))))

(defun %creature-render-snapshot-current-p (snapshot creature)
  (%ensure-creature-caches-current creature)
  (multiple-value-bind (x y width height) (%creature-bounds-current creature)
    (let* ((frame-index (creature-frame-index creature))
           (facing (creature-facing creature))
           (runs
            (if (eq facing :left) (aref
                                   (creature-%mirrored-frame-runs creature)
                                   frame-index)
              (aref (creature-%frame-runs creature) frame-index)))
           (z (creature-z creature)))
      (values
       (and
        (= (%creature-render-snapshot-x snapshot) x)
        (= (%creature-render-snapshot-y snapshot) y)
        (= (%creature-render-snapshot-width snapshot) width)
        (= (%creature-render-snapshot-height snapshot) height)
        (eq (%creature-render-snapshot-runs snapshot) runs)
        (= (%creature-render-snapshot-frame-index snapshot) frame-index)
        (eq (%creature-render-snapshot-facing snapshot) facing)
        (= (%creature-render-snapshot-z snapshot) z))
       x
       y
       width
       height
       runs
       frame-index
       facing
       z))))

(defun %add-clipped-dirty-rectangle (rectangles snapshot screen-width screen-height)
  (let* ((left (max 0 (%creature-render-snapshot-x snapshot)))
         (top (max 0 (%creature-render-snapshot-y snapshot)))
         (right (min screen-width
                     (+ (%creature-render-snapshot-x snapshot)
                        (%creature-render-snapshot-width snapshot))))
         (bottom (min screen-height
                      (+ (%creature-render-snapshot-y snapshot)
                         (%creature-render-snapshot-height snapshot)))))
    (if (and (< left right) (< top bottom))
        (%add-dirty-rectangle rectangles left top right bottom)
        rectangles)))

(defun %render-orders-equal-p (left right)
  (and
   (= (length left) (length right))
   (loop for left-creature in left
         for right-creature in right
         always (eq left-creature right-creature))))

(defun %creature-blit-clipped (screen snapshot clip-x clip-y clip-width clip-height)
  (declare (optimize (speed 3) (safety 1) (debug 0))
           (type fixnum clip-x clip-y clip-width clip-height))
  (let* ((clip-right (+ clip-x clip-width))
         (clip-bottom (+ clip-y clip-height))
         (runs (%creature-render-snapshot-runs snapshot))
         (x (%creature-render-snapshot-x snapshot))
         (y (%creature-render-snapshot-y snapshot))
         (right (+ x (%creature-render-snapshot-width snapshot)))
         (bottom (+ y (%creature-render-snapshot-height snapshot))))
    (when (and (< x clip-right) (< clip-x right)
               (< y clip-bottom) (< clip-y bottom))
      (loop for offset fixnum from 0 below (length runs) by 3
            for source = (svref runs (+ offset 2))
            for dest-x fixnum = (+ x (svref runs offset))
            for dest-y fixnum = (+ y (svref runs (1+ offset)))
            for left fixnum = (max clip-x dest-x)
            for top fixnum = (max clip-y dest-y)
            for right fixnum = (min clip-right (+ dest-x (screen-width source)))
            for bottom fixnum = (min clip-bottom (+ dest-y (screen-height source)))
            when (and (< left right) (< top bottom))
              do (cl-tty-kit:screen-blit screen source
                                           :dest-x left
                                           :dest-y top
                                           :src-x (- left dest-x)
                                           :src-y (- top dest-y)
                                           :width (- right left)
                                           :height (- bottom top))))))

(defun %record-renderer-frame (renderer screen render-order state)
  (setf (%renderer-frame-state-width state) (screen-width screen)
        (%renderer-frame-state-height state) (screen-height screen))
  (unless (%render-orders-equal-p
           (%renderer-frame-state-render-order state)
           render-order)
    (setf (%renderer-frame-state-render-order state) (copy-list render-order)))
  (setf (gethash renderer *renderer-frame-states*) state))

(defun render-frame (renderer world &key stream)
  "Incrementally compose WORLD onto RENDERER and return its terminal diff, or write it to STREAM."
  (let* ((screen (renderer-screen renderer))
         (screen-width (screen-width screen))
         (screen-height (screen-height screen))
         (render-order (%world-render-order world))
         (state (gethash renderer *renderer-frame-states*)))
    (unless state
      (setf state (%make-renderer-frame-state
                   screen-width
                   screen-height
                   (make-hash-table :test (function eq))
                   nil
                   (%make-dirty-rectangles)
                   0
                   nil)))
    (let ((snapshots
           (or
            (%renderer-frame-state-snapshots state)
            (setf (%renderer-frame-state-snapshots state)
                  (make-hash-table :test (function eq)))))
          (rectangles (%renderer-frame-state-dirty-rectangles state))
          (removed-creatures nil)
          (full-redraw-p nil)
          (generation (incf (%renderer-frame-state-generation state))))
      (setf (%dirty-rectangles-count rectangles) 0)
      (macrolet ((collect-dirty-rectangle (snapshot)
                   `(%add-clipped-dirty-rectangle
                     rectangles
                     ,snapshot
                     screen-width
                     screen-height)))
        (dolist (creature render-order)
          (let ((snapshot (gethash creature snapshots)))
            (if snapshot
                (multiple-value-bind (current-p x y width height runs frame-index facing z)
                    (%creature-render-snapshot-current-p snapshot creature)
                  (unless current-p
                    (collect-dirty-rectangle snapshot)
                    (setf (%creature-render-snapshot-x snapshot) x
                          (%creature-render-snapshot-y snapshot) y
                          (%creature-render-snapshot-width snapshot) width
                          (%creature-render-snapshot-height snapshot) height
                          (%creature-render-snapshot-runs snapshot) runs
                          (%creature-render-snapshot-frame-index snapshot) frame-index
                          (%creature-render-snapshot-facing snapshot) facing
                          (%creature-render-snapshot-z snapshot) z)
                    (collect-dirty-rectangle snapshot)))
                (progn
                  (setf snapshot (%snapshot-creature-for-rendering creature)
                        (gethash creature snapshots) snapshot)
                  (collect-dirty-rectangle snapshot)))
            (setf (%creature-render-snapshot-seen-generation snapshot) generation)))
        (maphash
         (lambda (creature snapshot)
           (unless (= (%creature-render-snapshot-seen-generation snapshot) generation)
             (collect-dirty-rectangle snapshot)
             (push creature removed-creatures)))
         snapshots)
        (dolist (creature removed-creatures)
          (remhash creature snapshots))
        (let ((render-order-changed-p
               (not
                (%render-orders-equal-p
                 (%renderer-frame-state-render-order state)
                 render-order))))
          (when render-order-changed-p
            (dolist (creature render-order)
              (collect-dirty-rectangle (gethash creature snapshots))))
          (when (or
                 (%dirty-rectangles-cover-half-screen-p rectangles screen-width screen-height)
                 (%dirty-rectangles-exceed-render-budget-p rectangles render-order))
            (setf full-redraw-p t))
          (if full-redraw-p
              (draw-world screen world)
              (cl-tty-kit:with-screen-batch
               (screen)
               (let ((data (%dirty-rectangles-data rectangles)))
                 (loop for index below (%dirty-rectangles-count rectangles)
                       for offset = (* index 4)
                       for x = (aref data offset)
                       for y = (aref data (1+ offset))
                       for width = (aref data (+ offset 2))
                       for height = (aref data (+ offset 3))
                       do (cl-tty-kit:screen-fill-rect screen x y width height #\Space)
                          (dolist (creature render-order)
                            (%creature-blit-clipped
                             screen
                             (gethash creature snapshots)
                             x
                             y
                             width
                             height)))))))
        (%record-renderer-frame renderer screen render-order state)
        (setf (%renderer-frame-state-last-world-tick state) (world-tick world))))
    (renderer-render renderer :stream stream)))
