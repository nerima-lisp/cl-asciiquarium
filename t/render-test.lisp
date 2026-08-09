(in-package #:cl-asciiquarium/test)

(describe "draw-world"
  (it "returns the screen it was given"
    (let* ((world (tiny-world :width 20 :height 10))
           (screen (make-screen 20 10)))
      (expect (draw-world screen world) :to-be screen)))
  (it "paints a creature's non-space characters onto the screen"
    ;; Y=1 sits above +WATERLINE-ROW+ (2), clear of every background creature
    ;; TINY-WORLD populates (waterline at Y=2, castle and seaweed lower still),
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
      (setf (entity-x (cl-asciiquarium::creature-entity creature)) 10)
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
    (let* ((world (make-world :width 4 :height 2 :fish-count 0
                              :hud-visible-p nil))
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
    (setf (entity-x (cl-asciiquarium::creature-entity creature)) 10)
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
  ;; Only a strict subset moves. Each mover contributes one dirty rectangle
  ;; (its old and new bounds touch and coalesce), and
  ;; %DIRTY-RECTANGLES-EXCEED-RENDER-BUDGET-P trips once
  ;; 4 * rectangles >= creatures -- so two movers over nine creatures (8 < 9)
  ;; keeps the clipped-blit branch. Moving all of them, as this test once did,
  ;; trips the budget and makes RENDER-FRAME fall back to DRAW-WORLD, which
  ;; would leave the comparison below checking DRAW-WORLD against itself.
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (expected (make-screen 20 10))
         (sentinel-column 19)
         (sentinel-row 9)
         (creatures
          (loop for character across "ABCDEFGHI"
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
                         1)))
         (screen nil))
    (cl-asciiquarium::%set-world-creatures world creatures)
    (render-frame renderer world)
    (setf screen (cl-asciiquarium::renderer-screen renderer))
    ;; A cell no dirty rectangle covers. The clipped-blit branch never writes
    ;; outside its rectangles; the fallback branch runs DRAW-WORLD, whose
    ;; SCREEN-CLEAR wipes the whole screen. Surviving ink is therefore an
    ;; observation of which branch executed, and it does not route through the
    ;; render-budget predicates that made the choice.
    (cl-tty-kit:screen-fill-rect screen sentinel-column sentinel-row 1 1 #\!)
    (dolist (creature (list (first creatures) (third creatures)))
      (incf (entity-y (cl-asciiquarium::creature-entity creature))))
    (render-frame renderer world)
    (expect (cell-char (screen-cell screen sentinel-column sentinel-row))
            :to-be #\!)
    (cl-asciiquarium::draw-world expected world)
    (dotimes (row 10)
      (dotimes (column 20)
        (unless (and (= column sentinel-column) (= row sentinel-row))
          (expect
           (cell-char (screen-cell screen column row))
           :to-be
           (cell-char (screen-cell expected column row))))))))
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
    (incf (entity-x (cl-asciiquarium::creature-entity mover)))
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
   (it "recreates renderer state after an explicit shutdown" (let* ((world (tiny-world :width 20 :height 10 :fish-count 0)) (renderer (make-renderer 20 10))) (unwind-protect (progn (render-frame renderer world) (expect (gethash renderer cl-asciiquarium::*renderer-frame-states*) :to-be-truthy) (shutdown-renderer renderer) (expect (gethash renderer cl-asciiquarium::*renderer-frame-states*) :to-be-falsy) (expect (stringp (render-frame renderer world)) :to-be-truthy)) (shutdown-renderer renderer))))
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
      (setf (entity-x (cl-asciiquarium::creature-entity creature)) 10)
      (render-frame renderer world)
      (expect (gethash creature snapshots) :to-be snapshot)))))
   (it
    "preserves non-square snapshot metadata during validation"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (creature
            (make-creature
             :world
             world
             :kind
             :marker
             :frames
             (list (format nil "AB~%CD~%EF"))
             :x
             5
             :y
             1
             :facing
             :right
             :z
             2)))
      (multiple-value-bind (snapshot ignored)
          (cl-asciiquarium::%snapshot-creature-for-rendering creature)
        (declare (ignore ignored))
        (multiple-value-bind
              (current-p x y width height runs frame-index facing z cache-rebuilt-p)
            (cl-asciiquarium::%creature-render-snapshot-current-p
             snapshot
             creature)
          (expect current-p :to-be-truthy)
          (expect x :to-be 5)
          (expect y :to-be 1)
          (expect width :to-be 2)
          (expect height :to-be 3)
          (expect runs :to-be
                  (cl-asciiquarium::%creature-render-snapshot-runs snapshot))
          (expect frame-index :to-be 0)
          (expect facing :to-be :right)
          (expect z :to-be 2)
          (expect cache-rebuilt-p :to-be-falsy))))))

(describe
 "render-frame parallel preparation"
 (it
    "arms parallel cache preparation after heavy invalidation"
    (let* ((world (tiny-world :width 80 :height 10 :fish-count 0))
           (renderer (make-renderer 80 10))
           (creatures
            (loop for index below 64
                  collect (make-creature
                           :world
                           world
                           :kind
                           :marker
                           :frames
                           (list "A")
                           :x
                           index
                           :y
                           1))))
      (unwind-protect
           (progn
             (cl-asciiquarium::%set-world-creatures world creatures)
             (render-frame renderer world)
             (let ((state
                     (gethash renderer cl-asciiquarium::*renderer-frame-states*)))
               (expect
                (cl-asciiquarium::%renderer-frame-state-executor state)
                :to-be
                nil)
               (loop for creature in creatures
                     do (setf (aref (creature-frames creature) 0) "B"))
               (render-frame renderer world)
               (expect
                (cl-asciiquarium::%renderer-frame-state-parallel-cache-hot-p state)
                :to-be-truthy)
               (expect
                (cl-asciiquarium::%renderer-frame-state-executor state)
                :to-be
                nil)
               (loop for creature in creatures
                     do (setf (aref (creature-frames creature) 0) "C"))
               (render-frame renderer world)
               (let* ((executor
                       (cl-asciiquarium::%renderer-frame-state-executor state))
                      (inputs
                       (cl-asciiquarium::%renderer-frame-state-parallel-input-snapshots
                        state))
                      (results
                       (cl-asciiquarium::%renderer-frame-state-parallel-results state)))
                 (expect executor :to-be-truthy)
                 (expect (length inputs) :to-be 64)
                 (expect (length results) :to-be 64)
                 (loop for creature in creatures
                       do (setf (aref (creature-frames creature) 0) "D"))
                 (render-frame renderer world)
                 (expect
                  (cl-asciiquarium::%renderer-frame-state-executor state)
                  :to-be
                  executor)
                 (expect
                  (cl-asciiquarium::%renderer-frame-state-parallel-input-snapshots state)
                  :to-be
                  inputs)
                 (expect
                  (cl-asciiquarium::%renderer-frame-state-parallel-results state)
                  :to-be
                  results))))
        (shutdown-renderer renderer)))))

(it
 "keeps parallel cache preparation output-equivalent to serial preparation"
 (let* ((serial-world (tiny-world :width 80 :height 10 :fish-count 0))
        (parallel-world (tiny-world :width 80 :height 10 :fish-count 0))
        (serial-renderer (make-renderer 80 10))
        (parallel-renderer (make-renderer 80 10))
        (serial-creatures
         (loop for index below 64
               collect (make-creature
                        :world
                        serial-world
                        :kind
                        :marker
                        :frames
                        (list "A")
                        :x
                        index
                        :y
                        1)))
        (parallel-creatures
         (loop for index below 64
               collect (make-creature
                        :world
                        parallel-world
                        :kind
                        :marker
                        :frames
                        (list "A")
                        :x
                        index
                        :y
                        1)))
        (serial-output nil)
        (parallel-output nil))
   (unwind-protect
        (progn
          (cl-asciiquarium::%set-world-creatures serial-world serial-creatures)
          (cl-asciiquarium::%set-world-creatures parallel-world parallel-creatures)
          (render-frame serial-renderer serial-world)
          (render-frame parallel-renderer parallel-world)
          (loop for creature in serial-creatures
                do (setf (aref (creature-frames creature) 0) "B"))
          (loop for creature in parallel-creatures
                do (setf (aref (creature-frames creature) 0) "B"))
          (setf serial-output (render-frame serial-renderer serial-world))
          (let ((state
                  (gethash parallel-renderer cl-asciiquarium::*renderer-frame-states*)))
            (setf
             (cl-asciiquarium::%renderer-frame-state-parallel-cache-hot-p state)
             t))
          (setf parallel-output (render-frame parallel-renderer parallel-world))
          (let ((state
                  (gethash parallel-renderer cl-asciiquarium::*renderer-frame-states*)))
            (expect
             (cl-asciiquarium::%renderer-frame-state-executor state)
             :to-be-truthy))
          (expect parallel-output :to-equal serial-output))
     (shutdown-renderer serial-renderer)
     (shutdown-renderer parallel-renderer))))

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
        (setf (entity-dx (cl-asciiquarium::creature-entity creature)) 0))
      (setf (entity-dx (cl-asciiquarium::creature-entity first)) 1)
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

(defun %render-frame-took-incremental-branch-p (renderer width height)
  "Whether the frame RENDERER just composed took the clipped-blit branch rather
than the DRAW-WORLD fallback. RENDER-FRAME picks between them from the dirty
rectangles it retains on its frame state, and neither the rectangle buffer nor
the recorded render order is reset until the next frame begins, so the decision
is still readable afterwards. Used only to prove the equivalence harness below
actually exercised the incremental path -- never as its oracle."
  (let* ((state (gethash renderer cl-asciiquarium::*renderer-frame-states*))
         (rectangles
          (cl-asciiquarium::%renderer-frame-state-dirty-rectangles state))
         (render-order
          (cl-asciiquarium::%renderer-frame-state-render-order state)))
    (not (or (cl-asciiquarium::%dirty-rectangles-cover-half-screen-p
              rectangles width height)
             (cl-asciiquarium::%dirty-rectangles-exceed-render-budget-p
              rectangles render-order)))))

(defun %render-frame-seed-divergence (width height seed frame-count)
  "Advance two identically seeded WIDTH by HEIGHT worlds in lockstep, painting
one with repeated RENDER-FRAME calls so incremental state accumulates across
frames, and the other with a DRAW-WORLD full repaint. Return (VALUES REPORT
INCREMENTAL-FRAMES): REPORT is NIL when every frame agreed cell-for-cell, or a
string naming the first frame that diverged and a sample of its differing
cells; INCREMENTAL-FRAMES counts how many frames took the clipped-blit branch.

DRAW-WORLD is a sound control precisely because it shares no code with the
clipped-blit path -- it clears and repaints through CREATURE-BLIT, which passes
no clip arguments at all -- so this compares two independent renderers rather
than one delegating to the other."
  (let ((incremental-world
         (with-seeded-random-state (seed)
           (make-world :width width :height height)))
        (control-world
         (with-seeded-random-state (seed)
           (make-world :width width :height height)))
        (renderer (make-renderer width height))
        (control-screen (make-screen width height))
        (incremental-frames 0))
    (unwind-protect
         (values
          (loop for frame below frame-count
                do (render-frame renderer incremental-world)
                   (cl-asciiquarium::draw-world control-screen control-world)
                   (when (%render-frame-took-incremental-branch-p
                          renderer width height)
                     (incf incremental-frames))
                   (let* ((screen (cl-asciiquarium::renderer-screen renderer))
                          (differences
                           (loop for row below height
                                 nconc
                                 (loop for column below width
                                       for actual
                                         = (cell-char
                                            (screen-cell screen column row))
                                       for control
                                         = (cell-char
                                            (screen-cell
                                             control-screen column row))
                                       unless (char= actual control)
                                         collect (list column row
                                                       actual control)))))
                     (when differences
                       (return
                         (format
                          nil
                          "~Dx~D seed ~D frame ~D diverged in ~D of ~D cells; ~
first ~D as (COLUMN ROW INCREMENTAL FULL-REPAINT): ~{~S~^ ~}"
                          width height seed frame (length differences)
                          (* width height)
                          (min 8 (length differences))
                          (subseq differences
                                  0 (min 8 (length differences)))))))
                   ;; Re-seeding per tick keeps both worlds drawing the same
                   ;; random numbers even though they advance separately; a
                   ;; single shared state would let the first world's draws
                   ;; desynchronise the second and produce divergence that says
                   ;; nothing about rendering.
                   (with-seeded-random-state ((+ seed frame))
                     (world-advance incremental-world))
                   (with-seeded-random-state ((+ seed frame))
                     (world-advance control-world)))
          incremental-frames)
      (shutdown-renderer renderer))))

(defun %render-frame-equivalence-divergence (width height seeds frame-count)
  "Run %RENDER-FRAME-SEED-DIVERGENCE over each of SEEDS, returning (VALUES
REPORT TOTAL-INCREMENTAL-FRAMES) for the first seed that diverged, or NIL and
the total when none did. Several seeds rather than one lucky seed: a single
world is a thin sample of the geometries that expose a clipping defect."
  (let ((incremental-frames 0))
    (dolist (seed seeds (values nil incremental-frames))
      (multiple-value-bind (report seed-incremental-frames)
          (%render-frame-seed-divergence width height seed frame-count)
        (incf incremental-frames seed-incremental-frames)
        (when report
          (return (values report incremental-frames)))))))

(describe
 "render-frame full-repaint equivalence"
 ;; The incremental path had no cell-for-cell control anywhere in this suite,
 ;; which is how a real clipping defect survived: %CREATURE-BLIT-CLIPPED
 ;; expresses its entire right and bottom clip through SCREEN-BLIT's :WIDTH and
 ;; :HEIGHT arguments, and cl-tty-kit 1.5.0 ignores both. A creature that
 ;; overlaps a dirty rectangle therefore repaints its whole sprite, spilling
 ;; outside the region that was cleared; where that spill lands on a creature
 ;; with a higher Z that does not intersect the rectangle at all -- and so is
 ;; skipped by the bounds test -- the lower creature wins a cell that a full
 ;; repaint gives to the higher one.
 (it
  "matches a full repaint cell-for-cell at every frame of an 80x24 world"
  (multiple-value-bind (report incremental-frames)
      (%render-frame-equivalence-divergence 80 24 '(1 2 3) 120)
    ;; Assert the branch under test actually ran before trusting agreement:
    ;; the fallback branch is DRAW-WORLD, so a run that never went incremental
    ;; would be comparing the control against itself.
    (expect (plusp incremental-frames) :to-be-truthy)
    (expect report :to-be nil)))
 (it
  "matches a full repaint cell-for-cell at every frame of a 40x12 world"
  ;; The small size is not redundant with the large one. Dirty rectangles
  ;; bisect sprites far more often here, and creatures crowd together: every
  ;; seed sampled diverges at 40x12 while only a tenth of them do at 80x24.
  (multiple-value-bind (report incremental-frames)
      (%render-frame-equivalence-divergence 40 12 '(1 2 3) 120)
    (expect (plusp incremental-frames) :to-be-truthy)
    (expect report :to-be nil))))
