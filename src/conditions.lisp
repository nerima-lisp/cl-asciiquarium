;;;; src/conditions.lisp -- the package's condition hierarchy.
;;;;
;;;; Every condition this package signals derives from ASCIIQUARIUM-ERROR, so
;;;; a caller can catch all of them with one HANDLER-CASE clause. See
;;;; CODING_STANDARD.md "コンディションの設計".
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
