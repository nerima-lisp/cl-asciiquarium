;;;; src/art-weather.lisp -- the weather's sprites: one sheet creature per
;;;; weather covering the sky and the water's surface, and the lightning
;;;; flash. Rain is frames of the one sheet rather than a creature per drop,
;;;; so a rainy tick creates nothing. Every pattern comes from the cell's
;;;; coordinates, never from *RANDOM-STATE*.
(in-package #:cl-asciiquarium)

(defparameter +weather-sheet-kinds+ '(:rain-sheet :storm-sheet)
  "The CREATURE-KIND of each weather's sheet; :CLEAR has none.")

(defparameter +weather-frame-count+ 4
  "Frames in a sheet's loop. The drop patterns repeat every four rows, so
four frames of one row each loop without a seam.")

(defun %weather-frames (rows width cell)
  "Return (VALUES FRAMES MASKS), +WEATHER-FRAME-COUNT+ frames ROWS by WIDTH.
CELL is called with FRAME, ROW, and COLUMN and returns the cell's character
and mask role, or NIL for a transparent cell."
  (let ((frames '()) (masks '()))
    (dotimes (frame +weather-frame-count+)
      (let ((art (make-array (list rows width) :initial-element #\Space))
            (mask (make-array (list rows width) :initial-element #\Space)))
        (dotimes (row rows)
          (dotimes (column width)
            (multiple-value-bind (character role) (funcall cell frame row column)
              (when character
                (setf (aref art row column) character
                      (aref mask row column) role)))))
        (push (%grid-text art) frames)
        (push (%grid-text mask) masks)))
    (values (nreverse frames) (nreverse masks))))

(defun %falling-row (row frame)
  "The phase of ROW in FRAME: a drop one row lower in the next frame has the
same phase, which is what makes the pattern fall."
  (mod (- row frame) +weather-frame-count+))

(defun make-rain-sheet (world)
  "Create the rain: #\\' falling through the sky rows, and ripples on the
row under the waterline. NIL when the screen has no sky row."
  (let ((waterline (world-waterline-row world)))
    (when (plusp waterline)
      (%make-cached-decor
       world :rain-sheet (list :rain-sheet (world-width world) waterline)
       (lambda ()
         (%weather-frames
          (+ waterline 2) (world-width world)
          (lambda (frame row column)
            (cond ((< row waterline)
                   (when (zerop (mod (+ (* 3 column) (* 7 (%falling-row row frame))) 11))
                     (values +rain-drop-glyph+ #\r)))
                  ((> row waterline)
                   (when (zerop (mod (+ column (* 5 frame)) 13))
                     (values +rain-ripple-glyph+ #\o)))))))
       +rain-sheet-roles+ :z 2 :frame-period 3))))

(defun make-storm-sheet (world)
  "Create the storm: a dark cloud band on the top sky rows, #\\/ rain
slanting down to the left below it, and choppy crests on the waterline. NIL
when the screen has no sky row."
  (let ((waterline (world-waterline-row world)))
    (when (plusp waterline)
      (let ((cloud-rows (min 2 (1- waterline))))
        (%make-cached-decor
         world :storm-sheet (list :storm-sheet (world-width world) waterline)
         (lambda ()
           (%weather-frames
            (1+ waterline) (world-width world)
            (lambda (frame row column)
              (cond ((< row cloud-rows)
                     ;; A single cloud row uses the motif's lower, wider line.
                     (let* ((line (+ row (- 2 cloud-rows)))
                            (art (nth line +storm-cloud-motif+))
                            (mask (nth line +storm-cloud-mask-motif+))
                            (index (mod column (length art))))
                       (unless (char= (char mask index) #\Space)
                         (values (char art index) (char mask index)))))
                    ((< row waterline)
                     ;; ROW + COLUMN is constant along a drop's path down and
                     ;; to the left.
                     (when (zerop (mod (+ (* 3 (+ row column)) (* 7 (%falling-row row frame))) 8))
                       (values +storm-drop-glyph+ #\r)))
                    (t
                     (when (zerop (mod (+ column (* 3 frame)) 5))
                       (values +storm-chop-glyph+ #\w)))))))
         +storm-sheet-roles+ :z 2 :frame-period 2)))))

(defun make-weather-sheet (world)
  "Create the sheet for WORLD's current weather, or NIL for clear skies."
  (ecase (world-weather world)
    (:clear nil)
    (:rain (make-rain-sheet world))
    (:storm (make-storm-sheet world))))

(defparameter +flash-ticks+ 2
  "How many ticks a lightning flash stays on screen.")

(defun make-flash (world x)
  "Create a lightning flash: every sky row lit white, with a zigzag bolt
down column X. NIL when the screen has no sky row. Its runs are the shared
lit sky's (one prototype per screen geometry and theme) followed by the bolt's
own one-cell runs, which the blit draws over them, so a strike builds runs
for the bolt only."
  (let ((rows (world-waterline-row world))
        (width (world-width world)))
    (when (plusp rows)
      (let ((sky (%decor-prototype
                  world (list :flash-sky width rows) +flash-roles+
                  (lambda ()
                    (values (list (%grid-text (make-array (list rows width)
                                                          :initial-element #\Space)))
                            (list (%grid-text (make-array (list rows width)
                                                          :initial-element #\w)))))))
            (art (make-array (list rows width) :initial-element #\Space))
            (mask (make-array (list rows width) :initial-element #\w))
            (bolt-mask (make-array (list rows width) :initial-element #\Space)))
        (dotimes (row rows)
          (let ((column (max 0 (- x (mod row 2)))))
            (setf (aref art row column) (if (evenp row) #\/ #\\)
                  (aref mask row column) #\z
                  (aref bolt-mask row column) #\z)))
        (let* ((art (%grid-text art))
               (mask (%grid-text mask))
               (bolt-mask (%grid-text bolt-mask))
               (style (creature-%style sky))
               (role-styles (creature-%role-styles sky))
               (flash (make-creature :world world :kind :flash :%sprite-prototype sky
                                     :z 3 :policy :none :x 0 :y 0 :dx 0 :dy 0
                                     :ttl +flash-ticks+ :data (list :roles +flash-roles+))))
          (setf (creature-%frames flash) (vector art)
                (creature-%frames-shared-p flash) nil
                (creature-%prepared-frames flash) (vector (copy-seq art))
                (creature-%masks flash) (vector mask)
                (creature-%mirrored-frames flash) (vector (mirror-sprite-text art))
                (creature-%mirrored-masks flash) (vector (mirror-sprite-mask mask))
                (creature-%frame-runs flash)
                (vector (concatenate 'simple-vector
                                     (aref (creature-%frame-runs sky) 0)
                                     (%sprite-blit-runs art style bolt-mask role-styles)))
                (creature-%mirrored-frame-runs flash)
                (vector (concatenate 'simple-vector
                                     (aref (creature-%mirrored-frame-runs sky) 0)
                                     (%sprite-blit-runs (mirror-sprite-text art) style
                                                        (mirror-sprite-mask bolt-mask)
                                                        role-styles))))
          flash)))))

(dolist (kind '(:rain-sheet :storm-sheet :flash))
  (register-creature-restyler kind #'restyle-decor))
