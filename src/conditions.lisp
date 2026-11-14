;;;; src/conditions.lisp -- the package's condition hierarchy.
;;;;
;;;; Every condition this package signals derives from ASCIIQUARIUM-ERROR, so
;;;; a caller can catch all of them with one HANDLER-CASE clause.
(in-package #:cl-asciiquarium)

(define-condition asciiquarium-error (error) ()
  (:report (lambda (condition stream)
             (declare (ignore condition))
             (format stream "An unspecified cl-asciiquarium error occurred.")))
  (:documentation "Base condition for every error this package signals. Every
concrete subtype below overrides this :REPORT with its own; this one exists
only so a caller who signals ASCIIQUARIUM-ERROR directly (rather than one of
its subtypes) still gets a specific message instead of the debugger's fully
generic fallback."))

(define-condition asciiquarium-invalid-dimensions (asciiquarium-error)
  ((width :initarg :width :reader invalid-dimensions-width)
   (height :initarg :height :reader invalid-dimensions-height))
  (:report (lambda (condition stream)
             (format stream "Invalid world dimensions ~Dx~D: both must be positive integers."
                     (invalid-dimensions-width condition)
                     (invalid-dimensions-height condition))))
  (:documentation "Signaled when MAKE-WORLD or WORLD-RESIZE is given a
non-positive width or height."))

(define-condition asciiquarium-unknown-species (asciiquarium-error)
  ((name :initarg :name :reader unknown-species-name))
  (:report (lambda (condition stream)
             (format stream "Unknown fish species ~S." (unknown-species-name condition))))
  (:documentation "Signaled when MAKE-FISH is asked for a species name not
present in +FISH-SPECIES+."))

(define-condition asciiquarium-invalid-policy (asciiquarium-error)
  ((policy :initarg :policy :reader invalid-policy-policy))
  (:report (lambda (condition stream)
             (format stream "Invalid creature policy ~S: must be :WRAP, :DESPAWN, or :NONE."
                     (invalid-policy-policy condition))))
  (:documentation "Signaled when MAKE-CREATURE is given a :POLICY other than
:WRAP, :DESPAWN, or :NONE."))

(define-condition asciiquarium-invalid-mask (asciiquarium-error)
  ((frame-index :initarg :frame-index :reader invalid-mask-frame-index)
   (line :initarg :line :reader invalid-mask-line)
   (detail :initarg :detail :reader invalid-mask-detail))
  (:report (lambda (condition stream)
             (format stream "Invalid sprite mask for frame ~D, line ~D: ~A."
                     (invalid-mask-frame-index condition)
                     (invalid-mask-line condition)
                     (invalid-mask-detail condition))))
  (:documentation "Signaled when MAKE-CREATURE is given :MASKS whose count or
line shape differs from its :FRAMES, or whose mask character has no entry in
:ROLE-STYLES. LINE is NIL when the mismatch is in the number of masks or
lines rather than inside one line."))

(define-condition asciiquarium-invalid-argument (asciiquarium-error)
  ((value :initarg :value :reader invalid-argument-value)
   (expected :initarg :expected :reader invalid-argument-expected))
  (:report (lambda (condition stream)
             (format stream "Invalid value ~S: expected ~A."
                     (invalid-argument-value condition)
                     (invalid-argument-expected condition))))
  (:documentation "Signaled when a function is given an argument value outside
the set it accepts: an unknown visual theme (PARSE-VISUAL-THEME), --color
value (RESOLVE-COLOR-MODE), or color designator (RGB-COLOR). EXPECTED describes
the accepted values."))
