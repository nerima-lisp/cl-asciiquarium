;;;; t/helpers-world.lisp -- shared test fixtures, not a test file itself.
(in-package #:cl-asciiquarium/test)

(defmacro with-seeded-random-state ((seed) &body body)
  "Evaluate BODY with CL:*RANDOM-STATE* bound to the deterministic state
SB-EXT:SEED-RANDOM-STATE derives from SEED, so every RANDOM call inside
BODY -- including everything cl-asciiquarium's spawn/species/lane selection
does -- is reproducible across runs. A binding macro rather than a
higher-order function taking a THUNK, so a call site reads as scoping a
dynamic binding (like WITH-OPEN-FILE) instead of manually wrapping its body
in `(lambda () ...)'."
  `(let ((*random-state* (sb-ext:seed-random-state ,seed)))
     ,@body))

(defun tiny-world (&key (width 20) (height 10) (fish-count 0))
  "A small, mostly-empty WORLD for tests that want to control exactly which
creatures are present. FISH-COUNT defaults to 0 so a test can add its own
fixture creatures without a random population interfering."
  (make-world :width width :height height :fish-count fish-count))
