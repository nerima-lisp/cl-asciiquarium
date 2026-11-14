;;;; src/art-treasure.lisp -- the treasure chest's schedule, the gold coins it
;;;; throws, and the diver event: a dinghy, its rope, and the diver. The
;;;; chest's motion and the dive itself are in update-treasure.lisp.
(in-package #:cl-asciiquarium)

(defparameter +chest-first-open-delay+ 450
  "Ticks from the background build to the chest's first opening, inside the
380..520 range so the first opening needs no random number.")

(defun arm-chest (world chest)
  "Give the seabed CHEST its opening schedule (see CHEST-TICK). Called while
the background is built, so it draws no random number."
  (setf (creature-data chest)
        (list :roles (getf (creature-data chest) :roles)
              :state :closed
              :next-at (+ (world-tick world) +chest-first-open-delay+)
              :close-at 0
              :empty-until 0
              :tick 'chest-tick)))

;;; -- Coins ---------------------------------------------------------------

(defparameter +coin-gravity+ 0.1f0
  "Rows per tick a coin's upward speed loses every tick.")

(defparameter +coin-ttl+ 60
  "Ticks after which a coin is removed even if it has not landed.")

(defvar *coin-sprite-prototypes* (make-hash-table :test #'equal)
  "Prepared coin sprites keyed by (THEME COLOR-MODE), shared by every coin.")

(defun %coin-sprite-prototype (theme)
  (let ((key (list theme (effective-color-mode))))
    (or (gethash key *coin-sprite-prototypes*)
        (setf (gethash key *coin-sprite-prototypes*)
              (make-creature :kind :coin-sprite-prototype :frames (list "$")
                             :style (color-style :gold :theme theme)
                             :%trusted-frames-p t :%trusted-style-p t
                             :x 0 :y 0 :policy :none)))))

(defun make-coin (world chest index)
  "Create the INDEXth (0..5) gold coin thrown up from the open CHEST's top
row. Its side and spread come from INDEX; COIN-TICK pulls it back down."
  (let ((y (creature-y chest)))
    (make-creature :world world :kind :coin
                   :%sprite-prototype (%coin-sprite-prototype (world-theme world))
                   :z 5 :policy :none :ttl +coin-ttl+
                   :x (+ (creature-x chest) 2 index) :y y
                   :dx (* (- index 2.5f0) 0.15f0)
                   :dy (- (+ 0.7f0 (* 0.1f0 (mod index 3))))
                   :data (list :floor y :tick 'coin-tick))))

(register-creature-restyler
 :coin
 (lambda (world coin)
   (%set-creature-colors coin
                         :style (creature-%style (%coin-sprite-prototype (world-theme world))))))

;;; -- Diver ---------------------------------------------------------------

(defparameter +dinghy-speed+ 0.5f0
  "Columns per tick the dinghy crosses at.")

(defparameter +diver-rope-column+ 3
  "The dinghy column the rope hangs from, under the boatman.")

(defun %dinghy-creature (world facing x dx chest diver)
  (let ((theme (world-theme world)))
    (make-creature :world world :kind :dinghy
                   :frames (list +dinghy-art+) :masks (list +dinghy-mask+)
                   :role-styles (%resolve-roles theme +dinghy-roles+)
                   :style (color-style :fg :theme theme)
                   :%trusted-frames-p t :facing facing :z 7 :policy :despawn
                   :x x :y (max 0 (1- (world-waterline-row world))) :dx dx
                   :data (list :roles +dinghy-roles+
                               :phase :arrive
                               ;; The diver hangs left of the chest, its coin
                               ;; hand one column short of the chest's side.
                               :stop-x (- (creature-x chest) 1
                                          (sprite-width +diver-art+)
                                          (- +diver-rope-column+ 1))
                               :dx dx :chest chest :diver diver
                               :depth 0.0f0 :max-depth 0 :grab-until 0
                               :carrying nil
                               :tick 'dinghy-tick))))

(defun spawn-diver-now (world &key facing)
  "Add the diver event to WORLD and return its dinghy: the dinghy (kind
:DINGHY, the lead creature) enters from the edge opposite FACING (random by
default) and stops so its diver can climb down the rope to the left of the
chest. Spawns nothing and returns NIL when WORLD has no chest, which small
screens leave out."
  (let ((chest (find-creature-of-kind world :chest)))
    (when chest
      (let* ((facing (or facing (random-facing)))
             (theme (world-theme world))
             (diver (make-creature :world world :kind :diver
                                   :frames +diver-frames+ :masks +diver-masks+
                                   :role-styles (%resolve-roles theme +diver-roles+)
                                   :style (color-style :fg :theme theme)
                                   :%trusted-frames-p t :z 6 :policy :none
                                   :x 0 :y 0
                                   :data (list :roles +diver-roles+ :leader nil
                                               :tick 'diver-tick)))
             (dinghy (multiple-value-bind (x dx)
                         (off-screen-entry facing (sprite-width +dinghy-art+)
                                           (world-width world) +dinghy-speed+)
                       (%dinghy-creature world facing x dx chest diver)))
             (top (+ (creature-y dinghy) 2))
             (chest-bottom (+ (creature-y chest)
                              (nth-value 1 (creature-dimensions chest)) -1))
             (max-depth (- chest-bottom (1- (nth-value 1 (sprite-dimensions +diver-art+))) top))
             (rope (make-creature :world world :kind :rope
                                  :frames (cons " " (loop for length from 1 to max-depth
                                                          collect (format nil "~{~A~^~%~}"
                                                                          (make-list length :initial-element "|"))))
                                  :style (world-style world :white)
                                  :%trusted-frames-p t :%trusted-style-p t
                                  :z 6 :policy :none :x 0 :y 0
                                  :data (list :leader dinghy :tick 'rope-tick))))
        (setf (getf (creature-data diver) :leader) dinghy
              (getf (creature-data dinghy) :max-depth) max-depth)
        ;; The dinghy goes in last so it is first in the creature list and
        ;; ticks before the rope and the diver that read its position.
        (%add-world-creature world rope)
        (%add-world-creature world diver)
        (%add-world-creature world dinghy)))))

(register-creature-restyler :dinghy #'restyle-decor)
(register-creature-restyler :diver #'restyle-decor)
(register-named-color-restyler :rope :white)
