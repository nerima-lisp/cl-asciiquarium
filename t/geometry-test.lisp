(in-package #:cl-asciiquarium/test)

(describe "clamp"
  (it "leaves an in-range value unchanged"
    (expect (clamp 5 0 10) :to-be 5))
  (it "clamps below the low bound"
    (expect (clamp -3 0 10) :to-be 0))
  (it "clamps above the high bound"
    (expect (clamp 99 0 10) :to-be 10))

  (it-property "always returns a value inside [low, high], for any low <= high"
      ((low (gen-integer :min -1000 :max 1000))
       (span (gen-integer :min 0 :max 500))
       (value (gen-integer :min -2000 :max 2000)))
    (let ((high (+ low span)))
      (expect (<= low (clamp value low high) high) :to-be-truthy)))

  (it-property "is the identity for a value already inside [low, high]"
      ((low (gen-integer :min -1000 :max 1000))
       (span (gen-integer :min 0 :max 500))
       (offset (gen-integer :min 0 :max 500)))
    (let* ((high (+ low span))
           (value (+ low (mod offset (1+ span)))))
      (expect (clamp value low high) :to-be value))))

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
      (expect (mirror-sprite-text (mirror-sprite-text text)) :to-equal text)))

  (it-property "is its own inverse for any single-line text, not only hand-picked examples"
      ((text (gen-string :min-length 0 :max-length 30
                          :alphabet "abcXYZ()<>[]{}/\\ ")))
    (expect (mirror-sprite-text (mirror-sprite-text text)) :to-equal text)))

(describe "rects-overlap-p"
  (it "detects overlap"
    (expect (rects-overlap-p 0 0 5 5 3 3 5 5) :to-be-truthy))
  (it "detects no overlap when boxes are disjoint"
    (expect (rects-overlap-p 0 0 5 5 10 10 5 5) :to-be-falsy))
  (it "treats merely touching edges as not overlapping"
    (expect (rects-overlap-p 0 0 5 5 5 0 5 5) :to-be-falsy))

  (it-property "is symmetric in its two rectangles"
      ((ax (gen-integer :min -50 :max 50)) (ay (gen-integer :min -50 :max 50))
       (aw (gen-integer :min 0 :max 30)) (ah (gen-integer :min 0 :max 30))
       (bx (gen-integer :min -50 :max 50)) (by (gen-integer :min -50 :max 50))
       (bw (gen-integer :min 0 :max 30)) (bh (gen-integer :min 0 :max 30)))
    (expect (rects-overlap-p ax ay aw ah bx by bw bh)
            :to-be (rects-overlap-p bx by bw bh ax ay aw ah)))

  ;; Pin all four edge-touching boundaries, plus a clear overlap and a clear
  ;; disjoint pair, so mutations of the boundary comparisons are detected.
  (it-sequential "kills every mutation of its four boundary comparisons"
    (let ((original-form '(defun rects-overlap-p (ax ay aw ah bx by bw bh)
                            (and (< ax (+ bx bw)) (< bx (+ ax aw))
                                 (< ay (+ by bh)) (< by (+ ay ah)))))
          (cases '(((1 1 3 3 0 0 3 3) . t)     ; clearly overlapping
                   ((0 0 3 3 10 10 3 3) . nil) ; clearly disjoint
                   ((3 0 3 3 0 0 3 3) . nil)   ; A's left touches B's right
                   ((0 0 3 3 3 0 3 3) . nil)   ; A's right touches B's left
                   ((0 3 3 3 0 0 3 3) . nil)   ; A's top touches B's bottom
                   ((0 0 3 3 0 3 3 3) . nil)))) ; A's bottom touches B's top
      (unwind-protect
           (let ((results (run-mutations
                            original-form
                            (lambda (mutant-form mutation)
                              (declare (ignore mutation))
                              (eval mutant-form)
                              (handler-case
                                  (every (lambda (case)
                                           (eq (apply #'rects-overlap-p (first case)) (rest case)))
                                         cases)
                                (error () nil))))))
             (expect (plusp (length results)) :to-be-truthy)
             (assert-mutation-score results 1.0))
        (eval original-form)))))
