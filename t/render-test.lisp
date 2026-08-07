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
      (world-add-creature world creature)
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 1)) :to-be #\Z)))
  (it "clears the screen before repainting, so a creature that has moved leaves no trail"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (creature (make-creature :world world :kind :marker :frames (list "Z") :x 5 :y 1)))
      (world-add-creature world creature)
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
      (world-add-creature world back)
      (draw-world screen world)
      (world-add-creature world front)
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 4)) :to-be #\B)))
  (it "keeps creation-time z order in the cached paint order"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (first (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 4 :z 1))
           (second (make-creature :world world :kind :marker :frames (list "B") :x 5 :y 4 :z 2)))
      (setf (world-creatures world) (list first second))
      (draw-world screen world)
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 4)) :to-be #\B)))
  (it "copies a creature-list setter value before caching it"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (back (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 4 :z 1))
           (front (make-creature :world world :kind :marker :frames (list "B") :x 5 :y 4 :z 2))
           (replacement (make-creature :world world :kind :marker :frames (list "C") :x 5 :y 4 :z 3)))
      (setf (world-creatures world) (list back front))
      (draw-world screen world)
      (let ((alias (list replacement)))
        (setf (world-creatures world) alias)
        (setf (car alias) front))
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
      (world-add-creature world creature)
      (draw-world screen world)
      (expect (cl-tty-kit:cell-style (screen-cell screen 0 0)) :to-equal '(:bold))
      (setf (creature-style creature) '(:underline))
      (draw-world screen world)
      (expect (cl-tty-kit:cell-style (screen-cell screen 0 0)) :to-equal '(:underline))))
  (it "rebuilds normal and mirrored prepared runs when frames change"
    (let* ((world (tiny-world :width 4 :height 2 :fish-count 0))
           (screen (make-screen 4 2))
           (creature (make-creature :world world :kind :marker :x 0 :y 0 :z 2 :frames (list "A<"))))
      (world-add-creature world creature)
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
         (creature (make-creature :world world :kind :marker :frames (list "Z") :x 5 :y 1)))
    (world-add-creature world creature)
    (render-frame renderer world)
    (setf (entity-x (creature-entity creature)) 10)
    (render-frame renderer world)
    (expect (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 5 1)) :to-be #\Space)
    (expect (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 10 1)) :to-be #\Z)))

 (it
  "merges touching dirty rectangles while preserving the composed screen"
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (expected (make-screen 20 10))
         (first (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 1))
         (second (make-creature :world world :kind :marker :frames (list "B") :x 6 :y 1)))
    (setf (world-creatures world) (list first second))
    (render-frame renderer world)
    (incf (entity-x (creature-entity first)))
    (incf (entity-x (creature-entity second)))
    (render-frame renderer world)
    (let* ((state (gethash renderer cl-asciiquarium::*renderer-frame-states*))
           (rectangles (cl-asciiquarium::%renderer-frame-state-dirty-rectangles state)))
      (expect (cl-asciiquarium::%dirty-rectangles-count rectangles) :to-be 1))
    (draw-world expected world)
    (dotimes (row 10)
      (dotimes (column 20)
        (expect
         (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) column row))
         :to-be
         (cell-char (screen-cell expected column row)))))))

 (it
  "matches a full redraw when a dirty rectangle excludes another sprite"
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (expected (make-screen 20 10))
         (still (make-creature :world world :kind :marker :frames (list "S") :x 1 :y 1))
         (moved (make-creature :world world :kind :marker :frames (list "M") :x 15 :y 1)))
    (setf (world-creatures world) (list still moved))
    (render-frame renderer world)
    (incf (entity-x (creature-entity moved)))
    (render-frame renderer world)
    (draw-world expected world)
    (dotimes (row 10)
      (dotimes (column 20)
        (expect
         (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) column row))
         :to-be
         (cell-char (screen-cell expected column row)))))))

 (it
  "recomposes overlap after an art update without changing z-order"
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (back (make-creature :world world :kind :marker :frames (list "A") :x 5 :y 1 :z 1))
         (front (make-creature :world world :kind :marker :frames (list "B") :x 5 :y 1 :z 2)))
    (setf (world-creatures world) (list back front))
    (render-frame renderer world)
    (setf (creature-frames back) (list "C"))
    (render-frame renderer world)
    (expect (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 5 1)) :to-be #\B)))
 (it
  "falls back to a full redraw when more than six creatures change"
  (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
         (renderer (make-renderer 20 10))
         (expected (make-screen 20 10))
         (creatures
          (loop for character across "ABCDEFG"
                for x from 1 by 2
                collect (make-creature :world world :kind :marker :frames (list (string character)) :x x :y 1))))
    (setf (world-creatures world) creatures)
    (render-frame renderer world)
    (dolist (creature creatures)
      (incf (entity-y (creature-entity creature))))
    (render-frame renderer world)
    (draw-world expected world)
    (dotimes (row 10)
      (dotimes (column 20)
        (expect
         (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) column row))
         :to-be
         (cell-char (screen-cell expected column row))))))))

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
        (expect (plusp (length (get-output-stream-string stream))) :to-be-truthy)))
    (it
      "writes nothing to an explicit stream for an unchanged frame"
      (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
             (renderer (make-renderer 20 10))
             (stream (make-string-output-stream)))
        (render-frame renderer world :stream stream)
        (get-output-stream-string stream)
        (expect (render-frame renderer world :stream stream) :to-be stream)
        (expect (get-output-stream-string stream) :to-equal ""))))
  (describe
    "render-frame snapshot reuse"
    (it
      "retains a creature snapshot across still and moved frames"
      (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
             (renderer (make-renderer 20 10))
             (creature (make-creature :world world :kind :marker :frames (list "Z") :x 5 :y 1)))
        (world-add-creature world creature)
        (render-frame renderer world)
        (let* ((state (gethash renderer cl-asciiquarium::*renderer-frame-states*))
               (snapshots (cl-asciiquarium::%renderer-frame-state-snapshots state))
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
           (creature (make-creature :world world :kind :marker :frames (list "Z") :x 5 :y 1)))
      (world-add-creature world creature)
      (render-frame renderer world)
      (setf (world-creatures world) nil)
      (render-frame renderer world)
      (expect (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 5 1)) :to-be #\Space))))

(describe
  "render-frame large-world snapshots"
  (it
    "keeps snapshots when only one creature changes in a large world"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (renderer (make-renderer 20 10))
           (creatures
             (loop for character across "ABCDEFG"
                   for x from 1 by 2
                   collect (make-creature :world world :kind :marker
                                          :frames (list (string character)) :x x :y 1))))
      (setf (world-creatures world) creatures)
      (render-frame renderer world)
      (let* ((state (gethash renderer cl-asciiquarium::*renderer-frame-states*))
             (snapshots (cl-asciiquarium::%renderer-frame-state-snapshots state))
             (moving (first creatures)))
        (setf (entity-dx (creature-entity moving)) 1)
        (world-advance world)
        (render-frame renderer world)
        (expect (cl-asciiquarium::%renderer-frame-state-snapshots state) :to-be snapshots)
        (expect (gethash moving snapshots) :to-be-truthy)
        (expect (entity-x (creature-entity moving)) :to-be 2)
        (expect (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 1 1)) :to-be #\Space)
        (expect (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 2 1)) :to-be #\A))))
  (it
    "reconciles stale snapshots after a dense update becomes sparse"
    (let* ((world (tiny-world :width 30 :height 10 :fish-count 0))
           (renderer (make-renderer 30 10))
           (creatures
             (loop for character across "ABCDEFG"
                   for x from 1 by 3
                   collect (make-creature :world world :kind :marker
                                          :frames (list (string character)) :x x :y 1))))
      (setf (world-creatures world) creatures)
      (render-frame renderer world)
      (dolist (creature creatures)
        (setf (entity-dx (creature-entity creature)) 1))
      (world-advance world)
      (render-frame renderer world)
      (dolist (creature (rest creatures))
        (setf (entity-dx (creature-entity creature)) 0))
      (world-advance world)
      (render-frame renderer world)
      (loop for character across "ABCDEFG"
      for expected-x in '(3 5 8 11 14 17 20)
      do (expect (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer)
                                         expected-x 1))
                 :to-be character)))))

(progn
  (describe
    "render-order cache ownership"
    (it
      "returns a list copy without invalidating the internal cache"
      (let* ((world (cl-asciiquarium::%make-world :width 20 :height 10))
             (creature (make-creature :world world :kind :marker :frames (list "M")
                                      :x 1 :y 1 :z 1)))
        (cl-asciiquarium::%add-world-creature world creature)
        (let ((order (cl-asciiquarium::%world-render-order world))
              (public (world-creatures world)))
          (setf (car public) nil)
          (expect (cl-asciiquarium::world-render-order-valid-p world) :to-be-truthy)
          (expect (cl-asciiquarium::%world-render-order world) :to-be order)
          (expect (world-creatures world) :to-equal (list creature)))))
    (it
      "updates the owned cache incrementally through the explicit add API"
      (let* ((world (cl-asciiquarium::%make-world :width 20 :height 10))
             (front (make-creature :world world :kind :marker :frames (list "F") :x 0 :y 0 :z 5))
             (back (make-creature :world world :kind :marker :frames (list "B") :x 0 :y 0 :z 4)))
        (world-add-creature world front)
        (cl-asciiquarium::%world-render-order world)
        (world-add-creature world back)
        (expect (cl-asciiquarium::world-render-order-valid-p world) :to-be-truthy)
        (expect (cl-asciiquarium::world-render-order-cache world)
                :to-equal (list back front))))))

(describe
  "render-frame cache ownership"
  (it
    "retains the world-owned render-order cache across unchanged frames"
    (let* ((world (cl-asciiquarium::%make-world :width 20 :height 10))
           (renderer (make-renderer 20 10))
           (creature (make-creature :world world :kind :marker :frames (list "M")
                                    :x 1 :y 1 :z 1)))
      (cl-asciiquarium::%add-world-creature world creature)
      (render-frame renderer world)
      (let* ((state (gethash renderer cl-asciiquarium::*renderer-frame-states*))
             (render-order (cl-asciiquarium::%world-render-order world)))
        (expect (cl-asciiquarium::%renderer-frame-state-render-order state)
                :to-be render-order)
        (render-frame renderer world)
        (expect (cl-asciiquarium::%renderer-frame-state-render-order state)
                :to-be render-order)))))
(describe
  "render-frame snapshot boundaries"
  (it
    "updates a mirrored snapshot when the creature faces right"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (renderer (make-renderer 20 10))
           (creature (make-creature :world world :kind :marker
                                    :frames (list "A<") :facing :left :x 5 :y 1)))
      ;; Keep the world cache owned internally so the second frame uses the
      ;; incremental snapshot path rather than the public-list fallback.
      (cl-asciiquarium::%add-world-creature world creature)
      (render-frame renderer world)
      (render-frame renderer world)
      (setf (creature-facing creature) :right)
      (render-frame renderer world)
      (expect (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 5 1))
              :to-be #\A)
      (expect (cell-char (screen-cell (cl-asciiquarium::renderer-screen renderer) 6 1))
              :to-be #\<)))
  (it "distinguishes same-size render orders with different identities" (let ((first (make-creature :kind :marker :frames (list "A") :x 0 :y 0)) (second (make-creature :kind :marker :frames (list "B") :x 0 :y 0))) (expect (cl-asciiquarium::%render-orders-equal-p (list first second) (list second first)) :to-be nil))))
