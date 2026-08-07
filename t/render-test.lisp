(in-package #:cl-asciiquarium/test)

(describe "draw-world"
  (it "returns the screen it was given"
    (let* ((world (tiny-world :width 20 :height 10))
           (screen (make-screen 20 10)))
      (expect (draw-world screen world) :to-be screen)))
  (it "paints a creature's non-space characters onto the screen"
    ;; Y=1 sits above +WATERLINE-ROW+ (5), clear of every background creature.
    ;; TINY-WORLD populates (waterline at Y=5, castle and seaweed lower still),
    ;; so this cell has no art to collide with the marker.
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (creature (make-creature :world world :kind :marker :frames (list "Z") :x 5 :y 1)))
      (cl-asciiquarium::%add-world-creature world creature)
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 1)) :to-be #\Z)))
  (it "clears the screen before repainting, so a creature that has moved leaves no trail"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (creature (make-creature :world world :kind :marker :frames (list "Z") :x 5 :y 1)))
      (cl-asciiquarium::%add-world-creature world creature)
      (draw-world screen world)
      (setf (entity-x (creature-entity creature)) 10)
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 1)) :to-be #\Space)))
  (it "preserves creature order when z values are equal"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (first (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 4 :z 1))
           (second (make-creature :world world :kind :marker :frames (list "B") :x 5 :y 4 :z 1)))
      (cl-asciiquarium::%set-world-creatures world (list first second))
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 4)) :to-be #\B)))
  (progn
  (it "invalidates the cached paint order when a creature is pushed"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (back (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 4 :z 1))
           (front (make-creature :world world :kind :marker :frames (list "B") :x 5 :y 4 :z 2)))
      (cl-asciiquarium::%add-world-creature world back)
      (draw-world screen world)
      (cl-asciiquarium::%add-world-creature world front)
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 4)) :to-be #\B)))
  (it "rebuilds cached paint order after explicit z-order invalidation" (let* ((world (tiny-world :width 20 :height 10 :fish-count 0)) (screen (make-screen 20 10)) (first (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 4 :z 1)) (second (make-creature :world world :kind :marker :frames (list "B") :x 5 :y 4 :z 2))) (cl-asciiquarium::%set-world-creatures world (list first second)) (draw-world screen world) (setf (creature-z first) 3) (cl-asciiquarium::%invalidate-world-render-order world) (draw-world screen world) (expect (cell-char (screen-cell screen 5 4)) :to-be #\A))))
  (it "preserves transparent spaces and clips prepared runs at negative coordinates"
    (let* ((world (tiny-world :width 4 :height 2 :fish-count 0))
           (screen (make-screen 4 2))
           (back (make-creature :world world :kind :marker
                                :frames (list (format nil "BBBB~%BBBB"))
                                :x 0 :y 0 :z 1))
           (front (make-creature :world world :kind :marker
                                 :frames (list (format nil " X X~%XYZ"))
                                 :x -1 :y 0 :z 2)))
      (cl-asciiquarium::%set-world-creatures world (list back front))
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 0 0)) :to-be #\X)
      (expect (cell-char (screen-cell screen 1 0)) :to-be #\B)
      (expect (cell-char (screen-cell screen 2 0)) :to-be #\X)
      (expect (cell-char (screen-cell screen 0 1)) :to-be #\Y)
      (expect (cell-char (screen-cell screen 1 1)) :to-be #\Z)))
  (it "rebuilds prepared runs when style changes"
    (let* ((world (tiny-world :width 4 :height 2 :fish-count 0))
           (screen (make-screen 4 2))
           (creature (make-creature :world world :kind :marker :x 0 :y 0
                                    :frames (list "Z") :style '(:bold))))
      (cl-asciiquarium::%add-world-creature world creature)
      (draw-world screen world)
      (expect (cl-tty-kit:cell-style (screen-cell screen 0 0)) :to-equal '(:bold))
      (setf (creature-style creature) '(:underline))
      (draw-world screen world)
      (expect (cl-tty-kit:cell-style (screen-cell screen 0 0)) :to-equal '(:underline))))
  (it "rebuilds normal and mirrored prepared runs when frames change"
    (let* ((world (tiny-world :width 4 :height 2 :fish-count 0))
           (screen (make-screen 4 2))
           (creature (make-creature :world world :kind :marker :x 0 :y 0 :z 2 :frames (list "A<"))))
      (cl-asciiquarium::%add-world-creature world creature)
      (setf (creature-frames creature) (list "B<")
            (creature-facing creature) :left)
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 0 0)) :to-be #\>)
      (expect (cell-char (screen-cell screen 1 0)) :to-be #\B)))
  (it "matches sprite-blit for transparency mirroring clipping Unicode and replaced style"
    (dolist (case (list (list (format nil " A °~%BC") :right -1 0)
                        (list (format nil "<° ~% D") :left 2 -1)))
      (destructuring-bind (art facing x y) case
        (let* ((expected (make-screen 5 2))
               (actual (make-screen 5 2))
               (creature (make-creature :kind :marker :frames (list art)
                                        :facing facing :x x :y y :style '(:bold)))
               (painted-art (if (eq facing :left) (mirror-sprite-text art) art)))
          (setf (creature-style creature) '(:underline))
          (cl-tty-kit:sprite-blit expected painted-art x y :style '(:underline))
          (cl-asciiquarium::creature-blit actual creature)
          (dotimes (row 2)
            (dotimes (column 5)
              (expect (cell-char (screen-cell actual column row))
                      :to-be (cell-char (screen-cell expected column row)))
              (expect (cl-tty-kit:cell-style (screen-cell actual column row))
                      :to-equal (cl-tty-kit:cell-style
                                 (screen-cell expected column row))))))))))

(describe
 "%add-dirty-rectangle"
 (it
  "merges touching rectangles but leaves separated regions alone"
  (let ((rectangles (cl-asciiquarium::%make-dirty-rectangles)))
    (dolist (rectangle (list (list 0 0 1 1) (list 1 0 2 1) (list 4 0 5 1)))
      (destructuring-bind (left top right bottom) rectangle
        (cl-asciiquarium::%add-dirty-rectangle rectangles left top right bottom)))
    (expect (cl-asciiquarium::%dirty-rectangles-count rectangles) :to-be 2)
    (let ((data (cl-asciiquarium::%dirty-rectangles-data rectangles)))
      (expect
       (loop for index below (cl-asciiquarium::%dirty-rectangles-count rectangles)
             for offset = (* index 4)
             thereis (and (= (aref data offset) 0)
                          (= (aref data (1+ offset)) 0)
                          (= (aref data (+ offset 2)) 2)
                          (= (aref data (+ offset 3)) 1)))
       :to-be-truthy)
      (expect
       (loop for index below (cl-asciiquarium::%dirty-rectangles-count rectangles)
             for offset = (* index 4)
             thereis (and (= (aref data offset) 4)
                          (= (aref data (1+ offset)) 0)
                          (= (aref data (+ offset 2)) 1)
                          (= (aref data (+ offset 3)) 1)))
       :to-be-truthy)))))

(describe
 "%dirty-rectangles-exceed-render-budget-p"
 (it
  "switches to a full repaint when separated regions dominate layer checks"
  (let ((rectangles (cl-asciiquarium::%make-dirty-rectangles)))
    (dolist (left (list 0 2 4 6))
      (cl-asciiquarium::%add-dirty-rectangle rectangles left 0 (1+ left) 1))
    (expect
     (cl-asciiquarium::%dirty-rectangles-exceed-render-budget-p
      rectangles
      (list :first :second :third :fourth :fifth :sixth :seventh :eighth))
     :to-be-truthy)))
 (it
  "keeps a single local region incremental"
  (let ((rectangles (cl-asciiquarium::%make-dirty-rectangles)))
    (cl-asciiquarium::%add-dirty-rectangle rectangles 0 0 1 1)
    (expect
     (cl-asciiquarium::%dirty-rectangles-exceed-render-budget-p
      rectangles
      (list :first :second :third :fourth))
     :to-be-falsy))))

(describe
 "render-frame"
 (it
  "produces non-empty output for the first frame of a populated world"
  (with-seeded-random-state
   (6)
   (let ((world (make-world :width 20 :height 10 :fish-count 2))
         (renderer (make-renderer 20 10)))
     (expect (plusp (length (render-frame renderer world))) :to-be-truthy))))
 (it
  "emits no diff for an unchanged second frame"
  (let ((world (tiny-world :width 20 :height 10 :fish-count 0))
        (renderer (make-renderer 20 10)))
    (render-frame renderer world)
    (expect (render-frame renderer world) :to-equal "")))
 (it
  "clears a creature's old location after it moves"
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (creature
          (make-creature
           :world
           world
           :kind
           :marker
           :frames
           (list "Z")
           :x
           5
           :y
           1)))
    (cl-asciiquarium::%add-world-creature world creature)
    (render-frame renderer world)
    (setf (entity-x (creature-entity creature)) 10)
    (render-frame renderer world)
    (expect
     (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 5 1))
     :to-be
     #\Space)
    (expect
     (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 10 1))
     :to-be
     #\Z)))
 (it
  "recomposes overlap after explicit z-order invalidation"
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (back
          (make-creature
           :world
           world
           :kind
           :marker
           :frames
           (list "A")
           :x
           5
           :y
           1
           :z
           1))
         (front
          (make-creature
           :world
           world
           :kind
           :marker
           :frames
           (list "B")
           :x
           5
           :y
           1
           :z
           2)))
    (cl-asciiquarium::%set-world-creatures world (list back front))
    (render-frame renderer world)
    (setf (creature-z back) 3)
    (cl-asciiquarium::%invalidate-world-render-order world)
    (render-frame renderer world)
    (expect
     (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 5 1))
     :to-be
     #\A)))
 (it
  "matches a full redraw after sparse changes beyond six creatures"
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (expected (make-screen 20 10))
         (creatures
          (loop for character across "ABCDEFG"
                for x from 1 by 2
                collect (make-creature
                         :world
                         world
                         :kind
                         :marker
                         :frames
                         (list (string character))
                         :x
                         x
                         :y
                         1))))
    (cl-asciiquarium::%set-world-creatures world creatures)
    (render-frame renderer world)
    (dolist (creature creatures)
      (incf (entity-y (creature-entity creature))))
    (render-frame renderer world)
    (draw-world expected world)
    (dotimes (row 10)
      (dotimes (column 20)
        (expect
         (cell-char
          (screen-cell (cl-asciiquarium::renderer-screen renderer) column row))
         :to-be
         (cell-char (screen-cell expected column row)))))))
 (it
  "leaves distant sprites intact while recomposing a local dirty rectangle"
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (mover
          (make-creature
           :world
           world
           :kind
           :marker
           :frames
           (list "M")
           :x
           1
           :y
           1))
         (distant
          (make-creature
           :world
           world
           :kind
           :marker
           :frames
           (list (format nil "FF~%FF"))
           :x
           15
           :y
           1)))
    (cl-asciiquarium::%set-world-creatures world (list mover distant))
    (render-frame renderer world)
    (incf (entity-x (creature-entity mover)))
    (render-frame renderer world)
    (let ((screen (cl-asciiquarium::renderer-screen renderer)))
      (expect (cell-char (screen-cell screen 1 1)) :to-be #\Space)
      (expect (cell-char (screen-cell screen 2 1)) :to-be #\M)
      (expect (cell-char (screen-cell screen 15 1)) :to-be #\F)
      (expect (cell-char (screen-cell screen 16 1)) :to-be #\F)
      (expect (cell-char (screen-cell screen 15 2)) :to-be #\F)))))

(progn
  (describe
   "render-frame output modes"
   (it
    "returns a diff string when no stream is supplied"
    (let ((world (tiny-world :width 20 :height 10 :fish-count 0))
          (renderer (make-renderer 20 10)))
      (expect (stringp (render-frame renderer world)) :to-be-truthy)))
   (it
    "writes directly to and returns an explicit stream"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (renderer (make-renderer 20 10))
           (stream (make-string-output-stream)))
      (expect (render-frame renderer world :stream stream) :to-be stream)
      (expect (plusp (length (get-output-stream-string stream))) :to-be-truthy))))
  (describe
   "render-frame snapshot reuse"
   (it
    "retains a creature snapshot across still and moved frames"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (renderer (make-renderer 20 10))
           (creature
            (make-creature
             :world
             world
             :kind
             :marker
             :frames
             (list "Z")
             :x
             5
             :y
             1)))
      (cl-asciiquarium::%add-world-creature world creature)
      (render-frame renderer world)
      (let* ((state (gethash renderer cl-asciiquarium::*renderer-frame-states*))
             (snapshots
              (cl-asciiquarium::%renderer-frame-state-snapshots state))
             (snapshot (gethash creature snapshots)))
        (render-frame renderer world)
        (expect (gethash creature snapshots) :to-be snapshot)
        (setf (entity-x (creature-entity creature)) 10)
        (render-frame renderer world)
        (expect (gethash creature snapshots) :to-be snapshot))))))

(describe
 "render-frame removal"
 (it
  "clears the last rendered location of a removed creature"
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (creature
          (make-creature
           :world
           world
           :kind
           :marker
           :frames
           (list "Z")
           :x
           5
           :y
           1)))
    (cl-asciiquarium::%add-world-creature world creature)
    (render-frame renderer world)
    (cl-asciiquarium::%set-world-creatures world nil)
    (render-frame renderer world)
    (expect
     (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 5 1))
     :to-be
     #\Space))))
(describe "render-frame mirrored snapshots" (it "reuses left-facing runs without changing the rendered sprite" (let* ((world (tiny-world :width 20 :height 10 :fish-count 0)) (renderer (make-renderer 20 10)) (creature (make-creature :world world :kind :marker :frames (list "abc") :facing :left :x 5 :y 1))) (cl-asciiquarium::%add-world-creature world creature) (render-frame renderer world) (let* ((state (gethash renderer cl-asciiquarium::*renderer-frame-states*)) (snapshots (cl-asciiquarium::%renderer-frame-state-snapshots state)) (snapshot (gethash creature snapshots))) (render-frame renderer world) (expect (gethash creature snapshots) :to-be snapshot) (let ((screen (cl-asciiquarium::renderer-screen renderer))) (expect (cell-char (screen-cell screen 5 1)) :to-be #\c) (expect (cell-char (screen-cell screen 6 1)) :to-be #\b) (expect (cell-char (screen-cell screen 7 1)) :to-be #\a))))))

(describe
 "render-frame full redraw fast path"
 (it
  "keeps snapshots when a large static world advances"
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (creatures
          (loop for character across "ABCDEFG"
                for x from 1 by 2
                collect (make-creature
                         :world
                         world
                         :kind
                         :marker
                         :frames
                         (list (string character))
                         :x
                         x
                         :y
                         1))))
    (cl-asciiquarium::%set-world-creatures world creatures)
    (render-frame renderer world)
    (let* ((state (gethash renderer cl-asciiquarium::*renderer-frame-states*))
           (snapshots (cl-asciiquarium::%renderer-frame-state-snapshots state)))
      (world-advance world)
      (render-frame renderer world)
      (expect
       (cl-asciiquarium::%renderer-frame-state-snapshots state)
       :to-be
       snapshots)
      (expect (hash-table-p snapshots) :to-be-truthy)
      (expect
       (cl-asciiquarium::%renderer-frame-state-last-world-tick state)
       :to-be
       (world-tick world)))))
 (it
  "reconciles retained snapshots after an incremental moving frame"
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (creatures
          (loop for character across "ABCDEFG"
                for x from 1 by 2
                collect (make-creature
                         :world
                         world
                         :kind
                         :marker
                         :frames
                         (list (string character))
                         :x
                         x
                         :y
                         1
                         :dx
                         1))))
    (cl-asciiquarium::%set-world-creatures world creatures)
    (render-frame renderer world)
    (let* ((state (gethash renderer cl-asciiquarium::*renderer-frame-states*))
           (snapshots (cl-asciiquarium::%renderer-frame-state-snapshots state))
           (first (first creatures)))
      (world-advance world)
      (render-frame renderer world)
      (expect
       (cl-asciiquarium::%creature-render-snapshot-x (gethash first snapshots))
       :to-be
       2)
      (dolist (creature creatures)
        (setf (entity-dx (creature-entity creature)) 0))
      (setf (entity-dx (creature-entity first)) 1)
      (world-advance world)
      (render-frame renderer world)
      (expect
       (cl-asciiquarium::%creature-render-snapshot-x (gethash first snapshots))
       :to-be
       3)
      (expect
       (cl-asciiquarium::%renderer-frame-state-last-world-tick state)
       :to-be
       (world-tick world))))))
