;;;; t/sky-test.lisp -- the sky body and the plankton across the time of day.
(in-package #:cl-asciiquarium/test)

(defun %glyph-count (creature)
  (count-if-not (lambda (character) (member character '(#\Space #\Newline)))
                (creature-art creature)))

(describe "sky across the time of day"
  (it "keeps the same :sky creature and redraws its body when the time of day changes"
    (let* ((world (make-world :width 80 :height 24 :fish-count 0 :theme :coral))
           (sky (first (%creatures-of-kind world :sky)))
           (day-art (creature-art sky)))
      (expect (search "- O -" day-art) :to-be-truthy)
      (dotimes (i cl-asciiquarium::+daypart-ticks+) (world-advance world))
      (expect (world-theme world) :to-be :abyss)
      (expect (first (%creatures-of-kind world :sky)) :to-be sky)
      (expect (search ".-''-." (creature-art sky)) :to-be-truthy)
      (cl-asciiquarium::world-advance-daypart world)
      (expect (first (%creatures-of-kind world :sky)) :to-be sky)
      (expect (search "(  (" (creature-art sky)) :to-be-truthy))))

(describe "plankton"
  (it "glows in the water more at night than by day, in the same creature"
    (let* ((world (make-world :width 80 :height 24 :fish-count 0 :theme :coral))
           (plankton (first (%creatures-of-kind world :plankton)))
           (day (%glyph-count plankton)))
      (expect (plusp day) :to-be-truthy)
      (expect (creature-y plankton) :to-be 7)
      (world-set-theme world :moonlight)
      (expect (first (%creatures-of-kind world :plankton)) :to-be plankton)
      (expect (> (%glyph-count plankton) day) :to-be-truthy)))
  (it "stays inside the water band"
    (let* ((world (make-world :width 80 :height 24 :fish-count 0 :theme :moonlight))
           (plankton (first (%creatures-of-kind world :plankton))))
      (multiple-value-bind (width height) (creature-dimensions plankton)
        (expect width :to-be 80)
        (expect (+ (creature-y plankton) height)
                :to-be (cl-asciiquarium::world-sand-top world)))))
  (it "is left out when the screen has no water rows"
    (expect (%creatures-of-kind (make-world :width 40 :height 3 :fish-count 0) :plankton)
            :to-be-null)))
