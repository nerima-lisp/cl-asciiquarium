(in-package #:cl-asciiquarium/test)

(describe "draw-world"
  (it "returns the screen it was given"
    (let* ((world (tiny-world :width 20 :height 10))
           (screen (make-screen 20 10)))
      (expect (draw-world screen world) :to-be screen)))
  (it "paints a creature's non-space characters onto the screen"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (creature (make-creature :world world :kind :marker :frames (list "Z") :x 5 :y 4)))
      (push creature (world-creatures world))
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 4)) :to-be #\Z)))
  (it "clears the screen before repainting, so a creature that has moved leaves no trail"
    (let* ((world (tiny-world :width 20 :height 10 :fish-count 0))
           (screen (make-screen 20 10))
           (creature (make-creature :world world :kind :marker :frames (list "Z") :x 5 :y 4)))
      (push creature (world-creatures world))
      (draw-world screen world)
      (setf (entity-x (creature-entity creature)) 10)
      (draw-world screen world)
      (expect (cell-char (screen-cell screen 5 4)) :to-be #\Space))))

(describe "render-frame"
  (it "produces non-empty output for the first frame of a populated world"
    (seeded 6
      (lambda ()
        (let ((world (make-world :width 20 :height 10 :fish-count 2))
              (renderer (make-renderer 20 10)))
          (expect (plusp (length (render-frame renderer world))) :to-be-truthy))))))
