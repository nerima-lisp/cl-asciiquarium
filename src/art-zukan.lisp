;;;; src/art-zukan.lisp -- the `z' key's dex panel listing every species.
(in-package #:cl-asciiquarium)

(defparameter +zukan-roles+
  '((#\o :muted :frame) (#\k :accent :frame) (#\n :fg :frame) (#\u :muted :frame)
    (#\p :frame :frame))
  "o the box outline, k the rare-species marker, n discovered names and the
title, u the ??? of an undiscovered species, p padding.")

(defun %zukan-cell (entry discovered cell-width)
  "Return (VALUES ART MASK) for ENTRY's cell, padded to CELL-WIDTH: its
lowercase name, followed by a marker when it is a rare species, or ???
while undiscovered."
  (let ((name (fish-species-entry-name entry)))
    (if (member name discovered)
        (let* ((rare-p (fish-species-entry-spawn-probability entry))
               (label (format nil "~(~A~)~:[~;✦~]" name rare-p))
               (label-mask (format nil "~A~:[~;k~]"
                                   (make-string (length (symbol-name name)) :initial-element #\n)
                                   rare-p)))
          (values (format nil "~vA" cell-width label)
                  (format nil "~A~A" label-mask
                          (make-string (- cell-width (length label)) :initial-element #\p))))
        (let ((text (format nil "~vA" cell-width "???")))
          (values text (%glyph-mask-with-padding text #\u))))))

(defun zukan-sprite (world)
  "Return (VALUES ART MASK ROLE-STYLES): the rounded-corner dex box, titled with
how many of +FISH-SPECIES+ WORLD has discovered. Species run down the left
column, then the right, in +FISH-SPECIES+ order; the two columns assume an
even species count."
  (let* ((discovered (world-discovered-species world))
         ;; One column past the longest name holds the rare marker.
         (cell-width (1+ (reduce #'max +fish-species+
                                 :key (lambda (entry)
                                        (length (symbol-name (fish-species-entry-name entry)))))))
         (rows (ceiling (length +fish-species+) 2))
         (inner (+ 1 cell-width 3 cell-width 1))
         (title (format nil " dex ~D/~D "
                        (count-if (lambda (entry) (member (fish-species-entry-name entry) discovered))
                                  +fish-species+)
                        (length +fish-species+)))
         (art-lines '())
         (mask-lines '()))
    (flet ((add (art mask) (push art art-lines) (push mask mask-lines)))
      (add (format nil "╭─~A~A╮" title
                   (make-string (- inner 1 (length title)) :initial-element #\─))
           (format nil "oo~A~Ao" (%glyph-mask-with-padding title #\n)
                   (make-string (- inner 1 (length title)) :initial-element #\o)))
      (loop for row below rows
            do (multiple-value-bind (left-art left-mask)
                   (%zukan-cell (nth row +fish-species+) discovered cell-width)
                 (multiple-value-bind (right-art right-mask)
                     (%zukan-cell (nth (+ row rows) +fish-species+) discovered cell-width)
                   (add (format nil "│ ~A   ~A │" left-art right-art)
                        (format nil "op~Appp~Apo" left-mask right-mask)))))
      (add (format nil "╰~A╯" (make-string inner :initial-element #\─))
           (format nil "o~Ao" (make-string inner :initial-element #\o))))
    (values (format nil "~{~A~^~%~}" (nreverse art-lines))
            (format nil "~{~A~^~%~}" (nreverse mask-lines))
            (%resolve-roles (world-theme world) +zukan-roles+))))

(defun make-zukan-overlay (world)
  "Create the :ZUKAN-OVERLAY CREATURE toggled by the `z' key: an opaque panel
placed like the help panel (MAKE-HELP-OVERLAY). It is drawn once when opened,
so a species discovered while it is open shows after it is reopened."
  (multiple-value-bind (art mask role-styles) (zukan-sprite world)
    (make-creature :world world :kind :zukan-overlay :frames (list art) :masks (list mask)
                   :role-styles role-styles :z 99 :policy :none
                   :x 1 :y (1+ (world-waterline-row world)) :dx 0 :dy 0)))

(register-creature-restyler :zukan-overlay (restyle-panel #'zukan-sprite))
