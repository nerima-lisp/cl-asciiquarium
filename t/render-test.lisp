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
      (push creature (world-creatures world))
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 1)) :to-be #\Z)))
  (it "clears the screen before repainting, so a creature that has moved leaves no trail"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (creature (make-creature :world world :kind :marker :frames (list "Z") :x 5 :y 1)))
      (push creature (world-creatures world))
      (draw-world screen world)
      (setf (entity-x (creature-entity creature)) 10)
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 1)) :to-be #\Space)))
  (it "preserves creature order when z values are equal"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (first (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 4 :z 1))
           (second (make-creature :world world :kind :marker :frames (list "B") :x 5 :y 4 :z 1)))
      (setf (world-creatures world) (list first second))
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 4)) :to-be #\B)))
  (progn
  (it "invalidates the cached paint order when a creature is pushed"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (back (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 4 :z 1))
           (front (make-creature :world world :kind :marker :frames (list "B") :x 5 :y 4 :z 2)))
      (push back (world-creatures world))
      (draw-world screen world)
      (push front (world-creatures world))
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 4)) :to-be #\B)))
  (it "invalidates the cached paint order when a creature z value changes"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (first (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 4 :z 1))
           (second (make-creature :world world :kind :marker :frames (list "B") :x 5 :y 4 :z 2)))
      (setf (world-creatures world) (list first second))
      (draw-world screen world)
      (setf (creature-z first) 3)
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 4)) :to-be #\A)))
  (it "invalidates the cached paint order after destructive list replacement"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (back (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 4 :z 1))
           (front (make-creature :world world :kind :marker :frames (list "B") :x 5 :y 4 :z 2))
           (replacement (make-creature :world world :kind :marker :frames (list "C") :x 5 :y 4 :z 3)))
      (setf (world-creatures world) (list back front))
      (draw-world screen world)
      (setf (car (world-creatures world)) replacement)
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 4)) :to-be #\C))))
  (it "preserves transparent spaces and clips prepared runs at negative coordinates"
    (let* ((world (tiny-world :width 4 :height 2 :fish-count 0))
           (screen (make-screen 4 2))
           (back (make-creature :world world :kind :marker
                                :frames (list (format nil "BBBB~%BBBB"))
                                :x 0 :y 0 :z 1))
           (front (make-creature :world world :kind :marker
                                 :frames (list (format nil " X X~%XYZ"))
                                 :x -1 :y 0 :z 2)))
      (setf (world-creatures world) (list back front))
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
      (push creature (world-creatures world))
      (draw-world screen world)
      (expect (cl-tty-kit:cell-style (screen-cell screen 0 0)) :to-equal '(:bold))
      (setf (creature-style creature) '(:underline))
      (draw-world screen world)
      (expect (cl-tty-kit:cell-style (screen-cell screen 0 0)) :to-equal '(:underline))))
  (it "rebuilds normal and mirrored prepared runs when frames change"
    (let* ((world (tiny-world :width 4 :height 2 :fish-count 0))
           (screen (make-screen 4 2))
           (creature (make-creature :world world :kind :marker :x 0 :y 0 :z 2 :frames (list "A<"))))
      (push creature (world-creatures world))
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

(describe "render-frame"
  (it "produces non-empty output for the first frame of a populated world"
    (with-seeded-random-state (6)
      (let ((world (make-world :width 20 :height 10 :fish-count 2))
            (renderer (make-renderer 20 10)))
        (expect (plusp (length (render-frame renderer world))) :to-be-truthy)))))

(progn
  (describe "render-order cache escape tracking"
    (it "returns the raw creature list and permanently marks it escaped"
      (let* ((world (tiny-world))
             (creatures (world-creatures world)))
        (expect creatures :to-be (cl-asciiquarium::world-%creatures world))
        (expect (cl-asciiquarium::world-render-order-escaped-p world) :to-be-truthy)))
    (it "detects a delayed destructive mutation through a setter alias"
      (let* ((world (tiny-world :width 20 :height 10))
             (screen (make-screen 20 10))
             (back (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 4 :z 1))
             (front (make-creature :world world :kind :marker :frames (list "B") :x 5 :y 4 :z 2))
             (replacement (make-creature :world world :kind :marker :frames (list "C") :x 5 :y 4 :z 3))
             (alias (list back front)))
        (setf (world-creatures world) alias)
        (draw-world screen world)
        (setf (car alias) replacement)
        (draw-world screen world)
        (expect (cell-char (screen-cell screen 5 4)) :to-be (code-char 67))))
    (it "does not scan snapshots on an unescaped cache hit"
      (let ((world (tiny-world)))
        (cl-asciiquarium::%world-render-order world)
        (setf (cl-asciiquarium::world-render-order-creatures world) #()
              (cl-asciiquarium::world-render-order-z-values world) #())
        (expect (cl-asciiquarium::world-render-order-escaped-p world) :to-be nil)
        (expect (cl-asciiquarium::%world-render-order-cache-valid-p world) :to-be-truthy)))))
