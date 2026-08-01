;;;; t/helpers-world.lisp -- shared test fixtures. Not a test file itself
;;;; (hence the `helpers-' prefix rather than `-test'); see
;;;; CODING_STANDARD.md "テスト補助ファイルは helpers- で始める".
(in-package #:cl-asciiquarium/test)

(defun seeded (seed thunk)
  "Call THUNK with CL:*RANDOM-STATE* bound to the deterministic state
SB-EXT:SEED-RANDOM-STATE derives from SEED, so every RANDOM call inside
THUNK -- including everything cl-asciiquarium's spawn/species/lane selection
does -- is reproducible across runs."
  (let ((*random-state* (sb-ext:seed-random-state seed)))
    (funcall thunk)))

(defun tiny-world (&key (width 20) (height 10) (fish-count 0))
  "A small, mostly-empty WORLD for tests that want to control exactly which
creatures are present. FISH-COUNT defaults to 0 so a test can add its own
fixture creatures without a random population interfering."
  (make-world :width width :height height :fish-count fish-count))
