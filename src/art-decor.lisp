;;;; src/art-decor.lisp -- the static-ish ocean background: waterline,
;;;; castle, and swaying seaweed. All three are CREATURE instances like every
;;;; other sprite (policy :NONE: none of them ever leaves the world bounds).
(in-package #:cl-asciiquarium)

(defparameter +waterline-row+ 2
  "The screen row the waterline sits on. Bubbles are removed once they rise
to this row or above; see update.lisp.")

(defun %waterline-art (width)
  "Return a WIDTH-wide wavy waterline pattern, repeating a 4-character motif."
  (let ((motif "^^~~"))
    (with-output-to-string (out)
      (loop for column below width
            do (write-char (char motif (mod column (length motif))) out)))))

(defun make-waterline (world)
  "Create the waterline decoration spanning the full width of WORLD."
  (make-creature :world world
                  :kind :waterline
                  :frames (list (%waterline-art (world-width world)))
                  :style (make-style (style-fg (named-color :bright-blue)))
                  :z 0
                  :policy :none
                  :x 0
                  :y +waterline-row+
                  :dx 0 :dy 0))

(defparameter +castle-art+
  (format nil (concatenate 'string
                            "   /\\      /\\~% _||_ /--\\ _||_~%|    |    |    |~%"
                            "|  o | [] |  o |~%|____|____|____|"))
  "Original castle decoration: two crenellated towers flanking a gatehouse.")

(defun make-castle (world)
  "Create the castle decoration near the bottom-left of WORLD."
  (multiple-value-bind (width height) (sprite-dimensions +castle-art+)
    (declare (ignore width))
    (make-creature :world world
                    :kind :castle
                    :frames (list +castle-art+)
                    :style (make-style (style-fg (named-color :yellow)))
                    :z 1
                    :policy :none
                    :x 2
                    :y (max (1+ +waterline-row+) (- (world-height world) height 1))
                    :dx 0 :dy 0)))

(defparameter +seaweed-frames+
  (list (format nil "\\~%|~%/~%|~%\\")
        (format nil "/~%|~%\\~%|~%/"))
  "The two-frame sway a seaweed strand loops between.")

(defun make-seaweed (world x)
  "Create one swaying seaweed strand rooted at column X near the bottom of
WORLD."
  (multiple-value-bind (width height) (sprite-dimensions (first +seaweed-frames+))
    (declare (ignore width))
    (make-creature :world world
                    :kind :seaweed
                    :frames +seaweed-frames+
                    :frame-period (random-between 8 16)
                    :style (make-style (style-fg (named-color :green)))
                    :z 1
                    :policy :none
                    :x x
                    :y (- (world-height world) height)
                    :dx 0 :dy 0)))
