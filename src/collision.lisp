;;;; src/collision.lisp -- the single collision pass and the effects that
;;;; remove a fish from play.
;;;;
;;;; A creature is a threat while its :DATA plist carries a :THREAT row:
;;;;
;;;;   (:grip (:front 2) :effect eat-effect :prey nil :alarm t)
;;;;
;;;; :GRIP is :BODY (the whole bounding box) or (:FRONT N) (the leading N
;;;; columns in the facing direction, full height). :EFFECT names the
;;;; (WORLD THREAT FISH) function applied to a gripped live fish, or NIL.
;;;; :PREY is NIL for every species, or a list of species keywords. :ALARM,
;;;; when true, calls the reaction of every creature carrying a :SENSE entry
;;;; (COLUMNS ROWS REACTION) whose range reaches the threat.
;;;;
;;;; The pass is threats x creatures, once per tick. Fish never test each
;;;; other, and this file does not grow into an NxN interaction matrix
;;;; between creature kinds: what a threat does lives in its row's functions,
;;;; in the file that defines the threat.
(in-package #:cl-asciiquarium)

(declaim (inline %cache-collision-bounds %cached-collision-overlap-p %axis-gap))

(defun %cache-collision-bounds (creature)
  (multiple-value-bind (left top width height) (%creature-bounds-current creature)
    (setf (creature-collision-left creature) left
          (creature-collision-top creature) top
          (creature-collision-width creature) width
          (creature-collision-height creature) height))
  creature)

(defun %cached-collision-overlap-p (left top width height candidate)
  "True when the rectangle LEFT TOP WIDTH HEIGHT overlaps CANDIDATE's cached
collision bounds. Touching edges do not count."
  (let ((candidate-left (creature-collision-left candidate))
        (candidate-top (creature-collision-top candidate)))
    (and (< left (+ candidate-left (creature-collision-width candidate)))
         (< candidate-left (+ left width))
         (< top (+ candidate-top (creature-collision-height candidate)))
         (< candidate-top (+ top height)))))

(defun %threat-grip-bounds (threat grip)
  "Return (VALUES LEFT TOP WIDTH HEIGHT), the part of THREAT's cached bounds
that GRIP (:BODY or (:FRONT N)) takes fish with."
  (let ((left (creature-collision-left threat))
        (top (creature-collision-top threat))
        (width (creature-collision-width threat))
        (height (creature-collision-height threat)))
    (if (eq grip :body)
        (values left top width height)
        (let ((columns (second grip)))
          (values (if (eq (creature-facing threat) :left)
                      left
                      (+ left (- width columns)))
                  top columns height)))))

(defun %axis-gap (start length other-start other-length)
  "The number of empty cells between two spans on one axis, 0 when they touch
or overlap."
  (max 0
       (- other-start (+ start length))
       (- start (+ other-start other-length))))

(defun %within-sense-range-p (threat sensor sense)
  "True when THREAT's cached bounds are at most SENSE's COLUMNS empty columns
and, unless its ROWS is NIL, at most ROWS empty rows away from SENSOR's."
  (let ((rows (second sense)))
    (and (<= (%axis-gap (creature-collision-left threat) (creature-collision-width threat)
                        (creature-collision-left sensor) (creature-collision-width sensor))
             (first sense))
         (or (null rows)
             (<= (%axis-gap (creature-collision-top threat) (creature-collision-height threat)
                            (creature-collision-top sensor) (creature-collision-height sensor))
                 rows)))))

(defun %apply-threat (world threat row creatures)
  "Run THREAT's ROW against every other creature in CREATURES once: sensor
reactions first, then ROW's effect on a gripped live fish of an allowed
species. A threat whose effect clears its own :THREAT stops gripping for the
rest of the pass."
  (let ((effect (getf row :effect))
        (prey (getf row :prey))
        (alarm (getf row :alarm)))
    (multiple-value-bind (left top width height) (%threat-grip-bounds threat (getf row :grip))
      (dolist (other creatures)
        (unless (eq other threat)
          (when alarm
            (let ((sense (getf (creature-data other) :sense)))
              (when (and sense (%within-sense-range-p threat other sense))
                (funcall (third sense) world other threat))))
          (when (and effect
                     (alive-fish-p other)
                     (or (null prey)
                         (member (getf (creature-data other) :species) prey :test #'eq))
                     (%cached-collision-overlap-p left top width height other))
            (funcall effect world threat other)
            (unless (getf (creature-data threat) :threat)
              (return))))))))

(defun apply-collisions (world)
  "Apply every threat's row in WORLD (see this file's header). Returns at once,
touching nothing, while WORLD has never held a threat since its creature list
was last recounted. Otherwise caches the bounds of every threat, sensor, and
live fish once, then runs each threat over the creature list once. Allocates
nothing itself; effects and reactions may."
  (unless (%world-has-active-predator-p world)
    (return-from apply-collisions world))
  (let ((creatures (world-%creatures world)))
    (dolist (creature creatures)
      (let ((data (creature-data creature)))
        (when (or (getf data :threat) (getf data :sense) (alive-fish-p creature))
          (%ensure-creature-caches-current creature)
          (%cache-collision-bounds creature))))
    (dolist (threat creatures)
      (let ((row (getf (creature-data threat) :threat)))
        (when row
          (%apply-threat world threat row creatures))))
    world))

(defun arm-threat (world creature row)
  "Make CREATURE a threat with ROW from now on, opening WORLD's collision gate.
For creatures that become threats after they were added to WORLD (a landed
anchor); a factory that puts :THREAT in the initial :DATA needs no call."
  (setf (getf (creature-data creature) :threat) row)
  (%note-world-predator-activation world)
  creature)

(defun eat-effect (world threat fish)
  "Kill FISH (its brief death animation, see KILL-FISH) and schedule a refill."
  (declare (ignore threat))
  (kill-fish fish)
  (schedule-fish-refill world))

(defun catch-effect (world threat fish)
  "Turn FISH into a :CAUGHT-FISH carried by THREAT at its current offset, and
schedule a refill. The kind change takes FISH out of ALIVE-FISH-P, so no other
threat takes it and it no longer counts toward the fish population."
  (fish-stop-behaviour fish)
  (setf (getf (creature-data fish) :tick) 'caught-fish-tick)
  (setf (creature-data fish)
        (list* :captor threat
               :offset-x (- (creature-x fish) (creature-x threat))
               :offset-y (- (creature-y fish) (creature-y threat))
               (creature-data fish)))
  (setf (creature-kind fish) :caught-fish)
  ;; Its captor carries it now; a leftover :WRAP callback would teleport it
  ;; to the far edge whenever the captor leaves the screen.
  (let ((entity (creature-entity fish)))
    (setf (entity-dx entity) 0
          (entity-dy entity) 0
          (entity-on-exit entity) nil))
  (schedule-fish-refill world))

(defun caught-fish-tick (world fish)
  "Keep FISH at its offset from its :CAPTOR, or mark it REMOVEP once the
captor is. Like MONSTER-SEGMENT-TICK, this is the same tick when the captor
ticked earlier in the creature list and the next tick otherwise."
  (declare (ignore world))
  (let* ((data (creature-data fish))
         (captor (getf data :captor)))
    (if (creature-removep captor)
        (setf (creature-removep fish) t)
        (let ((entity (creature-entity fish)))
          (setf (entity-x entity) (+ (creature-x captor) (getf data :offset-x))
                (entity-y entity) (+ (creature-y captor) (getf data :offset-y)))))))

(register-creature-restyler :caught-fish #'restyle-fish)
