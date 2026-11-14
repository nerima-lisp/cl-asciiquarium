;;;; src/art-octopus.lisp -- the octopus living under the :ROCK decoration,
;;;; the tentacle it reaches out, and the ink it spits. All three are
;;;; background kinds: WORLD-RESIZE discards them with the rock and
;;;; SEABED-LIFE builds a fresh octopus. Their behaviour is in
;;;; update-octopus.lisp.
(in-package #:cl-asciiquarium)

(defparameter +octopus-sense+ '(14 6 octopus-ink)
  "How close (empty columns, empty rows) a threat comes before the octopus
inks and hides.")

(defparameter +ink-ticks+ 50
  "How long the ink cloud lasts and the octopus stays hidden.")

(defparameter +tentacle-tuck-columns+ 2
  "How many columns at a tentacle's base start under the rock, so it grows out
of the rock's side rather than from a gap beside it.")

(defun %make-octopus-part (world kind frames masks roles &key x y z facing ttl
                                                          frame-period data)
  "Create a background CREATURE of KIND for the octopus, colored by ROLES like
%MAKE-DECOR (so RESTYLE-DECOR recolors it), with :ROLES followed by DATA."
  (let ((theme (world-theme world)))
    (make-creature :world world :kind kind :frames frames :masks masks
                   :role-styles (%resolve-roles theme roles)
                   :style (color-style :fg :theme theme)
                   :%trusted-frames-p t
                   :frame-period frame-period :facing facing :ttl ttl
                   :z z :policy :none :x x :y y
                   :data (list* :roles roles data))))

(defun octopus-peek-y (rock)
  "The row the octopus's head sits on, just above ROCK's top line."
  (- (creature-y rock) (nth-value 1 (sprite-dimensions +octopus-art+))))

(defun octopus-hide-y (rock)
  "The row that puts the octopus wholly behind ROCK's two solid lower lines."
  (1+ (creature-y rock)))

(defun make-octopus (world rock)
  "Create the octopus peeking over ROCK, drawn behind it. Draws no random
number: it is built with the background."
  (let ((width (sprite-width +octopus-art+)))
    (%make-octopus-part world :octopus (list +octopus-art+) (list +octopus-mask+)
                        +octopus-roles+
                        :x (+ (creature-x rock) (floor (- (creature-dimensions rock) width) 2))
                        :y (octopus-peek-y rock) :z 0
                        :data (list :phase :peek :ink-until 0 :tentacle nil :rock rock
                                    :reach-next 0 :sense +octopus-sense+
                                    :tick 'octopus-tick))))

(defun make-tentacle (world octopus facing row)
  "Create OCTOPUS's tentacle, one column long, on ROW at the side of its rock
that FACING points away from. A :RIGHT tentacle keeps its x and grows to the
right; a :LEFT one keeps its :BASE column (its right end) and moves its x."
  (let* ((rock (getf (creature-data octopus) :rock))
         (rock-x (creature-x rock))
         (base (if (eq facing :right)
                   (- (+ rock-x (creature-dimensions rock)) +tentacle-tuck-columns+)
                   (+ rock-x +tentacle-tuck-columns+ -1))))
    (%make-octopus-part world :tentacle +tentacle-frames+ +tentacle-masks+ +tentacle-roles+
                        :x base :y row :z 0 :facing facing
                        :data (list :octopus octopus :base base :length 1 :holding nil
                                    :retracting nil :threat +tentacle-threat+
                                    :tick 'tentacle-tick))))

(defun make-ink (world rock)
  "Create the ink cloud over the spot where the octopus peeks from ROCK. It
thins through +INK-FRAMES+ and leaves after +INK-TICKS+."
  (%make-octopus-part world :ink +ink-frames+ +ink-masks+ +ink-roles+
                      :x (1+ (creature-x rock))
                      :y (- (creature-y rock) (nth-value 1 (sprite-dimensions
                                                             (first +ink-frames+))))
                      :z 4 :ttl +ink-ticks+
                      :frame-period (ceiling +ink-ticks+ (length +ink-frames+))))

(dolist (kind '(:octopus :tentacle :ink))
  (register-creature-restyler kind #'restyle-decor))
