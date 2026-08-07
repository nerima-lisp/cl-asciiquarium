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

(defun %creature-blit-clipped (screen snapshot clip-x clip-y clip-width clip-height)
  (let* ((clip-right (+ clip-x clip-width))
         (clip-bottom (+ clip-y clip-height))
         (runs (%creature-render-snapshot-runs snapshot))
         (x (%creature-render-snapshot-x snapshot))
         (y (%creature-render-snapshot-y snapshot))
         (width (%creature-render-snapshot-width snapshot))
         (height (%creature-render-snapshot-height snapshot)))
    (when (and (< x clip-right) (< clip-x (+ x width))
               (< y clip-bottom) (< clip-y (+ y height)))
      (loop for offset from 0 below (length runs) by 4
            for source = (svref runs (+ offset 2))
            for source-width = (svref runs (+ offset 3))
            for dest-x = (+ x (svref runs offset))
            for dest-y = (+ y (svref runs (1+ offset)))
            for left = (max clip-x dest-x)
            for top = (max clip-y dest-y)
            for right = (min clip-right (+ dest-x source-width))
            for bottom = (min clip-bottom (1+ dest-y))
            when (and (< left right) (< top bottom))
              do (cl-tty-kit:screen-blit
          screen
          source
          :src-x
          (- left dest-x)
          :src-y
          (- top dest-y)
          :width
          (- right left)
          :height
          (- bottom top)
          :dest-x
          left
          :dest-y
          top)))))

(defun %record-renderer-frame (renderer screen render-order state)
  (setf (%renderer-frame-state-width state) (screen-width screen)
        (%renderer-frame-state-height state) (screen-height screen)
        (%renderer-frame-state-render-order state) render-order)
  (setf (gethash renderer *renderer-frame-states*) state))

(defun render-frame (renderer world &key stream)
  "Incrementally compose WORLD onto RENDERER and return its terminal diff, or write it to STREAM."
  (let* ((screen (renderer-screen renderer))
         (screen-width (screen-width screen))
         (screen-height (screen-height screen))
         (render-order (%world-render-order world))
         (state (gethash renderer *renderer-frame-states*))
         (full-redraw-p (or (null state)
                            (/= screen-width (%renderer-frame-state-width state))
                            (/= screen-height (%renderer-frame-state-height state)))))
    (unless state
      (setf state (%make-renderer-frame-state
                   screen-width screen-height
                   (make-hash-table :test (function eq)) nil
                   (%make-dirty-rectangles) 0 nil)))
    ;; A dense, consecutive simulation update is already cheaper to paint than to reconcile.
    (when (and (not full-redraw-p)
               (= (world-tick world)
                  (1+ (%renderer-frame-state-last-world-tick state)))
               (> (world-render-change-count world)
                  +render-frame-full-redraw-change-threshold+))
      (draw-world screen world)
      (%record-renderer-frame renderer screen render-order state)
      (setf (%renderer-frame-state-last-world-tick state) (world-tick world))
      (return-from render-frame (renderer-render renderer :stream stream)))
    (let ((snapshots (or (%renderer-frame-state-snapshots state)
                         (setf (%renderer-frame-state-snapshots state)
                               (make-hash-table :test (function eq)))))
          (rectangles (%reset-dirty-rectangles
                       (%renderer-frame-state-dirty-rectangles state)))
          (removed-creatures nil)
          (changed-creature-count 0)
          (generation (incf (%renderer-frame-state-generation state))))
      (macrolet ((note-change ()
                   (quote (progn
                            (incf changed-creature-count)
                            (when (and (not full-redraw-p)
                                       (> changed-creature-count
                                          +render-frame-full-redraw-change-threshold+))
                              (setf full-redraw-p t)))))
                 (collect-dirty-rectangle (snapshot)
                   `(unless full-redraw-p
                      (%add-clipped-dirty-rectangle
                       rectangles ,snapshot screen-width screen-height))))
        (dolist (creature render-order)
          (let ((snapshot (gethash creature snapshots)))
            (if snapshot
                (multiple-value-bind (current-p x y width height runs frame-index facing z)
                    (%creature-render-snapshot-current-p snapshot creature)
                  (unless current-p
                    (note-change)
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
                  (note-change)
                  (collect-dirty-rectangle snapshot)))
            (setf (%creature-render-snapshot-seen-generation snapshot) generation)))
        (maphash (lambda (creature snapshot)
                   (unless (= (%creature-render-snapshot-seen-generation snapshot) generation)
                     (note-change)
                     (collect-dirty-rectangle snapshot)
                     (push creature removed-creatures)))
                 snapshots)
        (dolist (creature removed-creatures)
          (remhash creature snapshots))
        (let ((render-order-changed-p
                (not (%render-orders-equal-p (%renderer-frame-state-render-order state)
                                             render-order))))
          (when render-order-changed-p
            (setf changed-creature-count
                  (max changed-creature-count
                       (length render-order)
                       (length (%renderer-frame-state-render-order state))))
            (when (> changed-creature-count +render-frame-full-redraw-change-threshold+)
              (setf full-redraw-p t))
            (unless full-redraw-p
              (dolist (creature render-order)
                (collect-dirty-rectangle (gethash creature snapshots)))))
          (if full-redraw-p
              (draw-world screen world)
              (cl-tty-kit:with-screen-batch (screen)
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
                               screen (gethash creature snapshots) x y width height)))))))
        (%record-renderer-frame renderer screen render-order state)
        (progn
          (setf (%renderer-frame-state-last-world-tick state) (world-tick world))
          (when (and (not full-redraw-p)
                     (zerop changed-creature-count))
            (return-from render-frame (if stream stream ""))))))
    (renderer-render renderer :stream stream)))
