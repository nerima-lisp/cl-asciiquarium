(in-package #:cl-asciiquarium/test)

(describe "clamp"
  (it "leaves an in-range value unchanged"
    (expect (clamp 5 0 10) :to-be 5))
  (it "clamps below the low bound"
    (expect (clamp -3 0 10) :to-be 0))
  (it "clamps above the high bound"
    (expect (clamp 99 0 10) :to-be 10)))

(describe "sprite-dimensions"
  (it "measures a single-line sprite"
    (expect (multiple-value-list (sprite-dimensions "abc")) :to-equal '(3 1)))
  (it "measures the longest line of a ragged multi-line sprite"
    (expect (multiple-value-list (sprite-dimensions (format nil "ab~%abcde~%a")))
            :to-equal '(5 3))))

(describe "sprite-width"
  (it "returns only the width"
    (expect (sprite-width (format nil "abcd~%ab")) :to-be 4)))

(describe "mirror-sprite-text"
  (it "reverses each line"
    (expect (mirror-sprite-text "abc") :to-equal "cba"))
  (it "swaps directional glyphs while reversing"
    (expect (mirror-sprite-text "<((>") :to-equal "<))>"))
  (it "mirrors every line of a multi-line sprite independently"
    (expect (mirror-sprite-text (format nil "ab~%<>")) :to-equal (format nil "ba~%<>")))
  (it "is its own inverse for a symmetric glyph set"
    (let ((text "a(b)c"))
      (expect (mirror-sprite-text (mirror-sprite-text text)) :to-equal text))))

(describe "rects-overlap-p"
  (it "detects overlap"
    (expect (rects-overlap-p 0 0 5 5 3 3 5 5) :to-be-truthy))
  (it "detects no overlap when boxes are disjoint"
    (expect (rects-overlap-p 0 0 5 5 10 10 5 5) :to-be-falsy))
  (it "treats merely touching edges as not overlapping"
    (expect (rects-overlap-p 0 0 5 5 5 0 5 5) :to-be-falsy)))
