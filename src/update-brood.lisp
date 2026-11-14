(in-package #:cl-asciiquarium)

(defun brood-count (world)
  (loop for creature in (world-%creatures world)
        count (and (not (creature-removep creature))
                   (member (creature-kind creature) '(:egg :fry)))))

(defun mate-ready-p (world fish)
  (and (alive-fish-p fish)
       (null (getf (creature-data fish) :threat))
       (<= (getf (creature-data fish) :mate-ready-at) (world-tick world))))

(defun select-courting-fish (world)
  (let ((selected nil)
        (eligible 0))
    ;; Lantern fish are permanent threats and predators, so cannot breed.
    (dolist (creature (world-%creatures world))
      (when (eq (getf (creature-data creature) :threat) +courting-threat+)
        (setf (getf (creature-data creature) :threat) nil)))
    (when (< (brood-count world) 3)
      ;; Reservoir sampling avoids allocating a candidate list.
      (dolist (creature (world-%creatures world))
        (when (mate-ready-p world creature)
          (when (zerop (random (incf eligible)))
            (setf selected creature))))
      (when selected
        (arm-threat world selected +courting-threat+)))
    selected))

(defun brood-effect (world parent mate)
  ;; Selection arms one ready parent only while fewer than three broods exist.
  ;; Death/capture clears its row; collision stops after breeding clears it.
  ;; Only this effect adds broods, so the count stays below three until it
  ;; succeeds; the selected parent's cooldown is unchanged until then.
  (let ((data (creature-data parent))
        (mate-data (creature-data mate)))
    (when (and (mate-ready-p world mate)
               (eq (getf data :species) (getf mate-data :species)))
      (let ((x (* 0.5f0 (+ (creature-x parent) (creature-x mate))))
            (y (* 0.5f0 (+ (creature-y parent) (creature-y mate)))))
        (setf (getf data :threat) nil
              (getf data :mate-ready-at) (+ (world-tick world) 700)
              (getf mate-data :mate-ready-at) (+ (world-tick world) 700))
        (%add-world-creature world (make-egg world (getf data :species) x y))
        (%add-world-creature world (make-heart world x y))))))

(defun brood-tick (world brood)
  (let ((data (creature-data brood)))
    (case (creature-kind brood)
      (:egg
       (when (>= (world-tick world) (getf data :hatch-at))
         (%set-creature-frames brood +fry-frames+)
         (setf (creature-kind brood) :fry)))
      (:fry
       (when (and (>= (world-tick world) (getf data :grow-at))
                  (< (count-if #'alive-fish-p (world-%creatures world))
                     (world-max-fish world)))
         (%add-world-creature
          world (make-fish world :species (getf data :species)
                                :x (creature-x brood) :y (creature-y brood)))
         (setf (creature-removep brood) t))))))
