;;;; src/render.lisp -- painting a WORLD onto a cl-tty-kit SCREEN.
(in-package #:cl-asciiquarium)

(defun %world-draw-order (world)
  (let ((creatures (world-creatures world)))
    (if (eq creatures (world-draw-order-source world))
        (world-draw-order world)
        (setf (world-draw-order-source world) creatures
              (world-draw-order world)
              (sort (copy-list creatures) #'< :key #'creature-z)))))

(defun draw-world (screen world)
  "Clear SCREEN and paint every creature in WORLD onto it back-to-front by
CREATURE-Z, returning SCREEN. Painting order, not a z-buffer, is what
establishes layering here -- see cl-tty-kit's entity.lisp file header, which
calls this out as the intended use of SPRITE-BLIT paint order."
  (screen-clear screen)
  (dolist (creature (%world-draw-order world))
    (sprite-blit screen (creature-art creature)
                 (round (creature-x creature)) (round (creature-y creature))
                 :style (creature-style creature)))
  screen)

(defun render-frame (renderer world)
  "Draw WORLD onto RENDERER's back buffer and return RENDERER-RENDER's diff
output for it."
  (draw-world (renderer-screen renderer) world)
  (renderer-render renderer))
