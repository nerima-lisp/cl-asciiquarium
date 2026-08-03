;;;; t/conditions-test.lisp
(in-package #:cl-asciiquarium/test)

(describe "asciiquarium-error"
  (it "reports a generic message when signaled directly, rather than through a subtype"
    (let ((report (princ-to-string (make-condition 'asciiquarium-error))))
      (expect (plusp (length report)) :to-be-truthy))))

(describe "asciiquarium-invalid-dimensions"
  (it "is a asciiquarium-error, so one handler-case clause catches every condition this package signals"
    (expect (typep (make-condition 'asciiquarium-invalid-dimensions :width 0 :height 10)
                    'asciiquarium-error)
            :to-be-truthy))
  (it "reports both the width and the height it was given"
    (let* ((condition (make-condition 'asciiquarium-invalid-dimensions :width 0 :height -3))
           (report (princ-to-string condition)))
      (expect (search "0" report) :to-be-truthy)
      (expect (search "-3" report) :to-be-truthy)))
  (it "exposes width and height through its reader accessors"
    (let ((condition (make-condition 'asciiquarium-invalid-dimensions :width 5 :height 9)))
      (expect (invalid-dimensions-width condition) :to-be 5)
      (expect (invalid-dimensions-height condition) :to-be 9))))

(describe "asciiquarium-unknown-species"
  (it "is a asciiquarium-error"
    (expect (typep (make-condition 'asciiquarium-unknown-species :name :nonexistent)
                    'asciiquarium-error)
            :to-be-truthy))
  (it "reports the unrecognized species name"
    (let* ((condition (make-condition 'asciiquarium-unknown-species :name :nonexistent))
           (report (princ-to-string condition)))
      (expect (search "NONEXISTENT" report) :to-be-truthy)))
  (it "exposes the species name through its reader accessor"
    (let ((condition (make-condition 'asciiquarium-unknown-species :name :dart)))
      (expect (unknown-species-name condition) :to-be :dart))))

(describe "asciiquarium-invalid-policy"
  (it "is a asciiquarium-error"
    (expect (typep (make-condition 'asciiquarium-invalid-policy :policy :bogus)
                    'asciiquarium-error)
            :to-be-truthy))
  (it "reports the invalid policy value"
    (let* ((condition (make-condition 'asciiquarium-invalid-policy :policy :bogus))
           (report (princ-to-string condition)))
      (expect (search "BOGUS" report) :to-be-truthy)))
  (it "exposes the policy through its reader accessor"
    (let ((condition (make-condition 'asciiquarium-invalid-policy :policy :bogus)))
      (expect (invalid-policy-policy condition) :to-be :bogus))))
