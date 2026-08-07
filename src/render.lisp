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
  (sb-thread:with-mutex (*renderer-ownership-lock*)
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
      (let* ((snapshots
              (or (%renderer-frame-state-snapshots state)
                  (setf (%renderer-frame-state-snapshots state)
                        (make-hash-table :test (function eq)))))
             (rectangles (%renderer-frame-state-dirty-rectangles state))
             (removed-creatures nil)
             (cache-rebuild-count 0)
             (generation (incf (%renderer-frame-state-generation state))))
        (setf (%dirty-rectangles-count rectangles) 0)
        (if (and (>= (length render-order)
                     +render-frame-parallel-minimum-creatures+)
                 (%renderer-frame-state-parallel-cache-hot-p state))
            (progn
              (%prepare-render-snapshots-parallel state render-order snapshots)
              (let ((results (%renderer-frame-state-parallel-results state)))
                (loop for creature in render-order
                      for index from 0
                      for result = (aref results index)
                      do (when (%apply-render-preparation
                                creature result snapshots rectangles
                                screen-width screen-height generation)
                           (incf cache-rebuild-count)))))
            (dolist (creature render-order)
              (let ((result (%make-render-preparation-result)))
                (%prepare-render-result
                 result
                 (gethash creature snapshots)
                 creature)
                (when (%apply-render-preparation
                       creature result snapshots rectangles
                       screen-width screen-height generation)
                  (incf cache-rebuild-count)))))
        (setf (%renderer-frame-state-parallel-cache-hot-p state)
              (and (>= (length render-order)
                       +render-frame-parallel-minimum-creatures+)
                   (>= cache-rebuild-count
                       +render-frame-parallel-minimum-cache-rebuilds+)))
        (maphash
         (lambda (creature snapshot)
           (unless (= (%creature-render-snapshot-seen-generation snapshot)
                      generation)
             (%add-clipped-dirty-rectangle rectangles snapshot
                                            screen-width screen-height)
             (push creature removed-creatures)))
         snapshots)
        (dolist (creature removed-creatures)
          (remhash creature snapshots))
        (let ((render-order-changed-p
                (not (%render-orders-equal-p
                      (%renderer-frame-state-render-order state)
                      render-order)))
              (full-redraw-p nil))
          (when render-order-changed-p
            (dolist (creature render-order)
              (%add-clipped-dirty-rectangle
               rectangles
               (gethash creature snapshots)
               screen-width
               screen-height)))
          (when (or (%dirty-rectangles-cover-half-screen-p
                     rectangles screen-width screen-height)
                    (%dirty-rectangles-exceed-render-budget-p
                     rectangles render-order))
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
                        do (cl-tty-kit:screen-fill-rect
                            screen x y width height #\Space)
                           (dolist (creature render-order)
                             (%creature-blit-clipped
                              screen
                              (gethash creature snapshots)
                              x y width height)))))))
        (%record-renderer-frame renderer screen render-order state)
        (setf (%renderer-frame-state-last-world-tick state)
              (world-tick world))))
    (renderer-render renderer :stream stream)))
