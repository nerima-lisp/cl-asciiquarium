;;;; src/art-decor-data.lisp -- the static ocean background's art and the one
;;;; numeric constant other files key off of (+WATERLINE-ROW+). Pure data;
;;;; art-decor.lisp holds the WATERLINE-ART generator and the three
;;;; MAKE-WATERLINE/MAKE-CASTLE/MAKE-SEAWEED/MAKE-HELP-OVERLAY factories that
;;;; read it.
(in-package #:cl-asciiquarium)

(defparameter +waterline-row+ 5
  "The screen row the four-row waterline sits on. Bubbles are removed once they rise
 to this row or above; see update.lisp.")

(defparameter +castle-art+
  (format nil (concatenate 'string
                            "   /\\      /\\~% _||_ /--\\ _||_~%|    |    |    |~%"
                            "|  o | [] |  o |~%|____|____|____|"))
  "Original castle decoration: two crenellated towers flanking a gatehouse.")

(defparameter +seaweed-frames+
  (list (format nil "\\~%|~%/~%|~%\\")
        (format nil "/~%|~%\\~%|~%/"))
  "The two-frame sway a seaweed strand loops between.")

(defparameter +help-overlay-art+
  (format nil "~
 controls~%~
 --------~%~
 q       quit~%~
 r/R     redraw~%~
 p/P     pause~%~
 space   pause~%~
 + / -   fish count~%~
 s       spawn shark~%~
 g       spawn guest~%~
 h       toggle this help")
  "The text WORLD-TOGGLE-HELP-OVERLAY's CREATURE displays, listing every key
this application binds (input.lisp).")
