;;;; src/conditions.lisp -- the package's condition hierarchy.
;;;;
;;;; Every condition this package signals derives from ASCIIQUARIUM-ERROR, so
;;;; a caller can catch all of them with one HANDLER-CASE clause. See
;;;; CODING_STANDARD.md "コンディションの設計".
(in-package #:cl-asciiquarium)

(define-condition asciiquarium-error (error) ()
  (:documentation "Base condition for every error this package signals."))

(define-condition invalid-dimensions (asciiquarium-error)
  ((width :initarg :width :reader invalid-dimensions-width)
   (height :initarg :height :reader invalid-dimensions-height))
  (:report (lambda (condition stream)
             (format stream "Invalid world dimensions ~Dx~D: both must be positive integers."
                     (invalid-dimensions-width condition)
                     (invalid-dimensions-height condition))))
  (:documentation "Signaled when MAKE-WORLD or WORLD-RESIZE is given a
non-positive width or height."))

(define-condition unknown-species (asciiquarium-error)
  ((name :initarg :name :reader unknown-species-name))
  (:report (lambda (condition stream)
             (format stream "Unknown fish species ~S." (unknown-species-name condition))))
  (:documentation "Signaled when MAKE-FISH is asked for a species name not
present in +FISH-SPECIES+."))
