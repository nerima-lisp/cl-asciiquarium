;;;; src/update-octopus.lisp -- the octopus's hunt and its ink.
;;;;
;;;; The octopus's :PHASE is :PEEK (looking for a fish), :REACH (a tentacle
;;;; out, growing toward it or retracting with or without a fish), or :INKED
;;;; (hidden behind the rock while its ink cloud lasts). The tentacle
;;;; is its own creature: its tip is a threat (+TENTACLE-THREAT+) that the
;;;; collision pass applies, and its tick grows or retracts it one column.
;;;; The tentacle and the ink are attached to the octopus (ATTACH-CREATURE),
;;;; so they leave with it; they are transient, so `r' clears them while the
;;;; octopus stays, and the octopus then peeks again.
(in-package #:cl-asciiquarium)

(defparameter +octopus-reach-columns+ 12
  "How many empty columns from the rock a fish may be for the octopus to reach
for it.")

(defparameter +octopus-reach-rows+ 6
  "How many empty rows above the rock a fish may be for the octopus to reach
for it.")

(defparameter +octopus-look-interval+ 10
  "How many ticks apart a peeking octopus looks for a fish.")

(defun octopus-prey (world rock)
  "The first live fish in WORLD beside ROCK, 1 to +OCTOPUS-REACH-COLUMNS+ empty
columns from it, and within +OCTOPUS-REACH-ROWS+ empty rows of it, or NIL. A
fish right above the rock is out of reach: a tentacle grows out of a side."
  (multiple-value-bind (rock-left rock-top rock-width rock-height) (creature-bounds rock)
    (dolist (creature (world-%creatures world))
      (when (alive-fish-p creature)
        (multiple-value-bind (left top width height) (creature-bounds creature)
          (when (and (<= 1 (%axis-gap left width rock-left rock-width) +octopus-reach-columns+)
                     (<= (%axis-gap top height rock-top rock-height) +octopus-reach-rows+))
            (return creature)))))))

(defun %launch-tentacle (world octopus fish)
  "Send OCTOPUS's tentacle toward FISH, on FISH's middle row, from the side of
the rock FISH is on."
  (let* ((data (creature-data octopus))
         (rock (getf data :rock)))
    (multiple-value-bind (left top width height) (creature-bounds fish)
      (let ((tentacle (make-tentacle world octopus
                                     (if (< (+ (* 2 left) width)
                                            (+ (* 2 (creature-x rock)) (creature-dimensions rock)))
                                         :left
                                         :right)
                                     (+ top (floor height 2)))))
        (setf (getf data :tentacle) tentacle
              (getf data :phase) :reach)
        (attach-creature world octopus tentacle)))))

(defun %octopus-peek (octopus)
  "Put OCTOPUS back to peeking over its rock, its tentacle and ink forgotten."
  (let ((data (creature-data octopus)))
    (setf (getf data :phase) :peek
          (getf data :tentacle) nil
          (getf data :ink) nil
          (entity-y (creature-entity octopus)) (octopus-peek-y (getf data :rock)))))

(defun octopus-tick (world octopus)
  "The octopus's :TICK: come out of hiding once its ink is gone, look
for a fish every +OCTOPUS-LOOK-INTERVAL+ ticks while peeking, and peek again
once its tentacle is gone."
  (let ((data (creature-data octopus))
        (tick (world-tick world)))
    (case (getf data :phase)
      (:inked
       (when (creature-removep (getf data :ink))
         (%octopus-peek octopus)))
      (:peek
       (when (>= tick (getf data :reach-next))
         (setf (getf data :reach-next) (+ tick +octopus-look-interval+))
         (let ((fish (octopus-prey world (getf data :rock))))
           (when fish
             (%launch-tentacle world octopus fish)))))
      (t
       (when (creature-removep (getf data :tentacle))
         (%octopus-peek octopus))))))

(defun %set-tentacle-length (tentacle length)
  "Show TENTACLE LENGTH columns long. A :LEFT tentacle keeps its right end on
its :BASE column; a :RIGHT one keeps its x, so a fish it holds is moved along
with the tip by its caught-fish offset."
  (let* ((data (creature-data tentacle))
         (change (- length (getf data :length)))
         (fish (getf data :holding)))
    (setf (getf data :length) length
          (creature-frame-index tentacle) (1- length))
    (if (eq (creature-facing tentacle) :left)
        (setf (entity-x (creature-entity tentacle)) (- (getf data :base) length -1))
        (when fish
          (incf (getf (creature-data fish) :offset-x) change)))))

(defun tentacle-tick (world tentacle)
  "The tentacle's :TICK: grow one column a tick until it holds a fish or is
+TENTACLE-MAX-LENGTH+ long, then retract one column a tick, and leave once
fully back under the rock. Leaving marks it REMOVEP, which makes the fish it
holds (CAUGHT-FISH-TICK) leave too, and drops its :THREAT, since this tick's
collision pass still runs the threats of REMOVEP creatures."
  (declare (ignore world))
  (let* ((data (creature-data tentacle))
         (length (getf data :length)))
    (cond ((getf data :retracting)
           (if (= length 1)
               (setf (creature-removep tentacle) t
                     (getf data :threat) nil)
               (%set-tentacle-length tentacle (1- length))))
          ((or (getf data :holding) (= length +tentacle-max-length+))
           (setf (getf data :retracting) t))
          (t
           (%set-tentacle-length tentacle (1+ length))))))

(defun tentacle-catch-effect (world tentacle fish)
  "The tentacle tip's effect: CATCH-EFFECT, then remember FISH so the tentacle
drags it in, and stop gripping so it holds one fish at a time."
  (catch-effect world tentacle fish)
  (let ((data (creature-data tentacle)))
    (setf (getf data :holding) fish
          (getf data :threat) nil)))

(defun octopus-ink (world octopus threat)
  "The octopus's sense reaction: unless THREAT is a tentacle or the octopus is
already inked, spit an ink cloud, hide behind the rock for +INK-TICKS+, and
pull back any tentacle that is out."
  (let ((data (creature-data octopus)))
    (unless (or (eq (creature-kind threat) :tentacle)
                (eq (getf data :phase) :inked))
      (let* ((rock (getf data :rock))
             (tentacle (getf data :tentacle))
             (ink (make-ink world rock)))
        (attach-creature world octopus ink)
        (setf (getf data :phase) :inked
              (getf data :ink) ink
              (entity-y (creature-entity octopus)) (octopus-hide-y rock))
        (when tentacle
          (setf (getf (creature-data tentacle) :retracting) t))))))
