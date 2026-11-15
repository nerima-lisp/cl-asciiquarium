;;;; src/update-fish.lisp -- puffer alarm and lantern lure.
(in-package #:cl-asciiquarium)

(defparameter +puffer-sense+ '(18 7 puffer-inflate))

(defparameter +lantern-lure-columns+ 30)
(defparameter +lantern-lure-rows+ 8)
(defparameter +lantern-threat+
  '(:grip (:front 1) :effect lantern-eat-effect :prey nil :alarm nil))

(defun initialize-puffer (fish)
  (setf (creature-data fish)
        (list* :sense +puffer-sense+ :inflated nil :inflate-until 0
               (creature-data fish))
        (getf (creature-data fish) :tick) 'puffer-tick)
  fish)

(defun initialize-lantern (world fish)
  (setf (creature-data fish)
        (list* :threat +lantern-threat+ :lure-next (+ (world-tick world) 240)
               :lure-target nil :glow nil
               (creature-data fish))
        (getf (creature-data fish) :tick) 'lantern-tick)
  fish)

(defun set-puffer-art (puffer inflated)
  (let ((width (creature-dimensions puffer)))
    (setf (creature-frame-index puffer) (if inflated 1 0))
    (decf (entity-x (creature-entity puffer))
          (* 0.5f0 (- (creature-dimensions puffer) width)))
    (setf (getf (creature-data puffer) :inflated) inflated)))

(defun puffer-inflate (world puffer threat)
  (declare (ignore threat))
  (unless (getf (creature-data puffer) :inflated)
    (set-puffer-art puffer t)
    (setf (getf (creature-data puffer) :inflate-until)
          (+ (world-tick world) 45))))

(defun puffer-tick (world puffer)
  (let ((data (creature-data puffer)))
    (when (and (getf data :inflated)
               (>= (world-tick world) (getf data :inflate-until)))
      (set-puffer-art puffer nil)))
  (maybe-emit-bubble world puffer))

(defun lantern-light-position (lantern)
  (values (+ (creature-x lantern)
             (if (eq (creature-facing lantern) :right) 6 1))
          (creature-y lantern)))

(defun lantern-target (world lantern)
  (multiple-value-bind (left top width height) (creature-bounds lantern)
    (let ((best nil) (best-gap (1+ +lantern-lure-columns+)))
      (dolist (fish (world-%creatures world) best)
        (when (and (alive-fish-p fish)
                   (not (eq (getf (creature-data fish) :leader) fish))
                   (fish-species-entry-small-p (fish-species (getf (creature-data fish) :species))))
          (multiple-value-bind (fish-left fish-top fish-width fish-height) (creature-bounds fish)
            (let ((gap (%axis-gap left width fish-left fish-width)))
              (when (and (< gap best-gap)
                         (<= (%axis-gap top height fish-top fish-height) +lantern-lure-rows+))
                (setf best fish best-gap gap)))))))))

(defun lantern-pull (lantern fish)
  (multiple-value-bind (light-x light-y) (lantern-light-position lantern)
    (multiple-value-bind (width height) (creature-dimensions fish)
      (let* ((entity (creature-entity fish))
             (gap-x (- light-x (+ (creature-x fish) (* 0.5f0 width))))
             (gap-y (- light-y (+ (creature-y fish) (* 0.5f0 height)))))
        (setf (creature-facing fish) (if (minusp gap-x) :left :right))
        ;; Three columns exceed swimming plus +SCHOOL-REJOIN-COLUMNS+ (1).
        ;; Keep the fish's tick and velocity so release resumes normal motion.
        (incf (entity-x entity) (clamp gap-x -3.0f0 3.0f0))
        (incf (entity-y entity) (clamp gap-y -1.0f0 1.0f0))))))

(defun release-lantern-target (lantern)
  (let* ((data (creature-data lantern))
         (target (getf data :lure-target)))
    (when target
      (let ((dx (entity-dx (creature-entity target))))
        (cond ((plusp dx) (setf (creature-facing target) :right))
              ((minusp dx) (setf (creature-facing target) :left))))
      (setf (getf data :lure-target) nil))))

(defun lantern-eat-effect (world lantern fish)
  (when (eq fish (getf (creature-data lantern) :lure-target))
    (multiple-value-bind (x y) (lantern-light-position lantern)
      (multiple-value-bind (left top width height) (creature-bounds fish)
        (when (and (<= left x) (< x (+ left width))
                   (<= top y) (< y (+ top height)))
          (release-lantern-target lantern)
          (eat-effect world lantern fish))))))

(defun lantern-glow-tick (world glow)
  "Leave when the theme turns away from moonlight; the glow leaves with its
lantern through ATTACH-CREATURE."
  (unless (eq (world-theme world) :moonlight)
    (setf (creature-removep glow) t
          (getf (creature-data (getf (creature-data glow) :lantern)) :glow) nil)))

(defun update-lantern-glow (world lantern)
  (when (eq (world-theme world) :moonlight)
    (let* ((data (creature-data lantern))
           (glow (getf data :glow)))
      (unless glow
        (setf glow (make-creature :world world :kind :lantern-glow
                                 :frames +lantern-glow-art+
                                 :style (color-style :rare-glow :theme (world-theme world))
                                 :z 4 :policy :none :x 0 :y 0
                                 :data (list :lantern lantern :tick 'lantern-glow-tick))
              (getf data :glow) glow)
        (attach-creature world lantern glow))
      ;; The parent has already moved, including any wrap, in this tick.
      (setf (entity-x (creature-entity glow))
            (+ (creature-x lantern) (if (eq (creature-facing lantern) :right) 4 -1))
            (entity-y (creature-entity glow)) (1- (creature-y lantern))))))

(defun lantern-tick (world lantern)
  (let* ((data (creature-data lantern))
         (tick (world-tick world)))
    (when (>= tick (getf data :lure-next))
      (release-lantern-target lantern)
      (setf (getf data :lure-next) (+ tick 240)
            (getf data :lure-target) (lantern-target world lantern)))
    (let ((target (getf data :lure-target)))
      (when target
        (if (alive-fish-p target)
            (lantern-pull lantern target)
            (release-lantern-target lantern))))
    (update-lantern-glow world lantern))
  (maybe-emit-bubble world lantern))

(register-creature-restyler
 :lantern-glow
 (lambda (world glow)
   (%set-creature-colors glow :style (color-style :rare-glow :theme (world-theme world)))))
