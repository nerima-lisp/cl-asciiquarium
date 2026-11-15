;;;; src/art-sky.lisp -- the glowing plankton in the water, sparse by day and
;;;; dense at night. The sun, the sunset, and the moon are the :SKY creature's
;;;; art (art-decor.lisp). The plankton is one static creature over the swim
;;;; band, redrawn for the new time of day by its restyler (RESTYLE-DECOR), so
;;;; it costs nothing per tick and draws no random number.
(in-package #:cl-asciiquarium)

(defparameter +plankton-glyph+ #\·)

(defparameter +plankton-roles+ '((#\p "#8EF0D8")))

(defparameter +plankton-hash-modulus+ 97)

(defparameter +plankton-density+ '((:coral . 1) (:abyss . 2) (:moonlight . 7))
  "How many of every +PLANKTON-HASH-MODULUS+ water cells hold a plankton
under each theme: day, dusk, night.")

(defun plankton-sprite (world)
  "Return (VALUES ART MASK) for the plankton over WORLD's swim band under its
theme, or NIL when the screen leaves no water rows."
  (let* ((top (+ (world-waterline-row world) 2))
         (rows (- (world-sand-top world) top))
         (width (world-width world))
         (density (cdr (assoc (world-theme world) +plankton-density+))))
    (when (plusp rows)
      (let ((art (make-array (list rows width) :initial-element #\Space))
            (mask (make-array (list rows width) :initial-element #\Space)))
        (dotimes (row rows)
          (dotimes (column width)
            (when (< (mod (+ (* 37 column column) (* 101 row) (* 13 column row))
                          +plankton-hash-modulus+)
                     density)
              (setf (aref art row column) +plankton-glyph+
                    (aref mask row column) #\p))))
        (values (%grid-text art) (%grid-text mask))))))

(defun make-plankton (world)
  "Create the plankton CREATURE for WORLD's theme, or NIL when there is no
water to put it in. Its density is drawn for the theme, so a restyle redraws
it for the time of day."
  (%make-cached-decor world :plankton
                      (list :plankton (world-width world) (world-waterline-row world)
                            (world-sand-top world))
                      (lambda ()
                        (multiple-value-bind (art mask) (plankton-sprite world)
                          (when art (values (list art) (list mask)))))
                      +plankton-roles+
                      :y (+ (world-waterline-row world) 2) :z -1))

(register-creature-restyler :plankton #'restyle-decor)
