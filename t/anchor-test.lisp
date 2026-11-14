;;;; t/anchor-test.lisp -- the ship's anchor: stop, fall, rest, rise, chain.
(in-package #:cl-asciiquarium/test)

(defun %anchor-kind (world kind)
  (find kind (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind))

(defun %anchor-data (creature key)
  (getf (cl-asciiquarium::creature-data creature) key))

(defun %anchor-add-fish (world fish)
  "Add the ONE-CELL-FISH FISH to WORLD; %ADD-WORLD-CREATURE would look up its
fixture species."
  (cl-asciiquarium::%set-world-creatures world (cons fish (cl-asciiquarium::world-%creatures world))))

(defun %anchor-ship-world (&key (width 60) (height 24))
  "A WIDTHxHEIGHT world (by default 60x24: waterline 5, sand from row 20) with
no fish, shark, or guest spawns and a right-facing ship at column 20 that drops
its anchor on the next tick. Returns (VALUES WORLD SHIP)."
  (let* ((world (make-world :width width :height height :fish-count 0 :shark-enabled-p nil))
         (ship (make-ship world :facing :right)))
    (setf (cl-asciiquarium::world-guest-cooldown world) 100000
          (entity-x (cl-asciiquarium::creature-entity ship)) 20.0f0
          (getf (cl-asciiquarium::creature-data ship) :drop-tick) (1+ (world-tick world)))
    (cl-asciiquarium::%add-world-creature world ship)
    (values world ship)))

(defun %advance-until (world predicate)
  "Advance WORLD until PREDICATE returns true, at most 500 ticks."
  (loop repeat 500
        until (funcall predicate)
        do (world-advance world)))

(defun %advance-until-landed (world)
  "Advance WORLD until its anchor rests on the seabed; return the anchor."
  (world-advance world)
  (let ((anchor (%anchor-kind world :anchor)))
    (%advance-until world (lambda () (eq (%anchor-data anchor :phase) :rest)))
    anchor))

(describe "anchor: the ship stops and drops it"
  (it "stops the ship at :drop-tick, saving its dx, and adds the anchor and its chain"
    (with-seeded-random-state (1)
      (multiple-value-bind (world ship) (%anchor-ship-world)
        (let ((entity (cl-asciiquarium::creature-entity ship)))
          (expect (%anchor-data ship :saved-dx) :to-be (entity-dx entity))
          (expect (entity-dx entity) :to-be 0.5f0)
          (world-advance world)
          (let ((anchor (%anchor-kind world :anchor))
                (chain (%anchor-kind world :chain))
                (stopped-x (creature-x ship)))
            (with-soft-assertions
              (expect (entity-dx entity) :to-be 0)
              (expect (%anchor-data ship :saved-dx) :to-be 0.5f0)
              (expect (%anchor-data anchor :phase) :to-be :fall)
              (expect (%anchor-data anchor :chain) :to-be chain)
              (expect (%anchor-data chain :anchor) :to-be anchor)
              (expect (< (position anchor (cl-asciiquarium::world-%creatures world))
                         (position chain (cl-asciiquarium::world-%creatures world)))
                      :to-be-truthy))
            (dotimes (i 10) (world-advance world))
            (expect (creature-x ship) :to-be stopped-x)))))))

(describe "anchor: seabed rest"
  (it "lands with its bottom row on the row above the sand and arms its threat"
    (with-seeded-random-state (1)
      (let* ((world (%anchor-ship-world))
             (anchor (%advance-until-landed world)))
        (with-soft-assertions
          (expect (+ (creature-y anchor) 2) :to-be (1- (cl-asciiquarium::world-sand-top world)))
          (expect (entity-dy (cl-asciiquarium::creature-entity anchor)) :to-be 0)
          (expect (%anchor-data anchor :threat) :to-be cl-asciiquarium::+anchor-threat+)))))
  (it "lands above the new sand when the screen shrinks while it falls"
    (with-seeded-random-state (1)
      (let ((world (%anchor-ship-world :width 80 :height 40)))
        (world-advance world)
        (let ((anchor (%anchor-kind world :anchor)))
          (expect (%anchor-data anchor :phase) :to-be :fall)
          (world-resize world 80 24)
          (%advance-until world (lambda () (eq (%anchor-data anchor :phase) :rest)))
          (with-soft-assertions
            (expect (%anchor-data anchor :phase) :to-be :rest)
            (expect (+ (creature-y anchor) 2) :to-be (1- (cl-asciiquarium::world-sand-top world))))))))
  (it "kills a fish placed under it during the rest"
    (with-seeded-random-state (1)
      (let* ((world (%anchor-ship-world))
             (anchor (%advance-until-landed world)))
        (dotimes (i 30) (world-advance world))
        (let ((fish (one-cell-fish world (+ (round (creature-x anchor)) 2) (1+ (creature-y anchor)))))
          (%anchor-add-fish world fish)
          (world-advance world)
          (expect (%anchor-data anchor :phase) :to-be :rest)
          (expect (dying-p fish) :to-be t)))))
  (it "does not kill a fish its falling anchor passes through"
    (with-seeded-random-state (1)
      (let ((world (%anchor-ship-world)))
        (world-advance world)
        (let* ((anchor (%anchor-kind world :anchor))
               (fish (one-cell-fish world (+ (round (creature-x anchor)) 2) 12))
               (overlapped nil))
          (%anchor-add-fish world fish)
          (%advance-until world
                          (lambda ()
                            (when (<= (creature-y anchor) 12 (+ (creature-y anchor) 2))
                              (setf overlapped t))
                            (eq (%anchor-data anchor :phase) :rest)))
          (expect overlapped :to-be t)
          (expect (dying-p fish) :to-be nil))))))

(describe "anchor: hauling up"
  (it "rises from the 71st tick after landing at its falling speed, then leaves with its chain as the ship sails on"
    (with-seeded-random-state (1)
      (let* ((world (%anchor-ship-world))
             (ship (%anchor-kind world :ship))
             (anchor (%advance-until-landed world))
             (chain (%anchor-data anchor :chain))
             (landed-y (creature-y anchor))
             (stopped-x (creature-x ship))
             (resting-ys nil))
        (dotimes (i 70)
          (world-advance world)
          (push (creature-y anchor) resting-ys))
        (with-soft-assertions
          (expect (every (lambda (y) (= y landed-y)) resting-ys) :to-be t)
          (expect (%anchor-data anchor :phase) :to-be :rise)
          (expect (%anchor-data anchor :threat) :to-be nil))
        (world-advance world)
        (expect (creature-y anchor) :to-be (1- landed-y))
        (let ((rise-ticks 1)
              (steady t))
          (loop repeat 100
                until (cl-asciiquarium::creature-removep anchor)
                do (let ((y (creature-y anchor)))
                     (world-advance world)
                     (incf rise-ticks)
                     (unless (= (creature-y anchor) (1- y))
                       (setf steady nil))))
          (with-soft-assertions
            (expect steady :to-be t)
            (expect rise-ticks :to-be (- landed-y (cl-asciiquarium::world-waterline-row world)))
            (expect (creature-y anchor) :to-be (cl-asciiquarium::world-waterline-row world))
            (expect (cl-asciiquarium::creature-removep chain) :to-be t)
            (expect (%anchor-kind world :anchor) :to-be-null)
            (expect (%anchor-kind world :chain) :to-be-null)
            (expect (entity-dx (cl-asciiquarium::creature-entity ship)) :to-be 0.5f0)))
        (let ((x (creature-x ship)))
          (expect (> x stopped-x) :to-be t)
          (world-advance world)
          (expect (creature-x ship) :to-be (+ x 0.5f0)))))))

(describe "anchor chain"
  (it "holds one frame per length, frame N being N links"
    (with-seeded-random-state (1)
      (let ((world (%anchor-ship-world)))
        (world-advance world)
        (let ((frames (cl-asciiquarium::creature-frames (%anchor-kind world :chain))))
          ;; Row under the ship (4 + 5) down to the resting anchor's top (17).
          (expect (length frames) :to-be 9)
          (expect (aref frames 0) :to-equal " ")
          (expect (aref frames 3) :to-equal (format nil "¦~%¦~%¦"))))))
  (it "spans the rows between the ship and the anchor while falling and rising"
    (with-seeded-random-state (1)
      (let ((world (%anchor-ship-world)))
        (world-advance world)
        (let* ((anchor (%anchor-kind world :anchor))
               (chain (%anchor-data anchor :chain))
               (top (creature-y chain))
               (mismatches nil)
               (lengths nil))
          (%advance-until world
                          (lambda ()
                            (let ((length (cl-asciiquarium::creature-frame-index chain)))
                              (push (cons (%anchor-data anchor :phase) length) lengths)
                              (unless (and (= length (max 0 (- (creature-y anchor) top)))
                                           (or (zerop length)
                                               (= (+ top (nth-value 1 (cl-asciiquarium::creature-dimensions chain)))
                                                  (creature-y anchor)))
                                           (= (creature-x chain) (+ (creature-x anchor) 2)))
                                (push (list (world-tick world) length (creature-y anchor)) mismatches)))
                            (cl-asciiquarium::creature-removep anchor)))
          (with-soft-assertions
            (expect mismatches :to-be-null)
            (expect (reduce #'max lengths :key #'cdr) :to-be 8)
            (expect (find-if (lambda (entry) (and (eq (car entry) :fall) (< 0 (cdr entry) 8))) lengths)
                    :to-be-truthy)
            (expect (find-if (lambda (entry) (and (eq (car entry) :rise) (< 0 (cdr entry) 8))) lengths)
                    :to-be-truthy)))))))

(defun %anchor-rig-in-line-p (ship anchor chain)
  "True when ANCHOR hangs under SHIP at MAKE-ANCHOR's offset and CHAIN runs in
its shaft column from the row under SHIP down to the row above ANCHOR, within
its precomputed frames."
  (and (= (creature-x anchor) (+ (creature-x ship) 4))
       (= (creature-x chain) (+ (creature-x anchor) 2))
       (= (creature-y chain) (+ (creature-y ship) 5))
       (< (cl-asciiquarium::creature-frame-index chain)
          (length (cl-asciiquarium::creature-frames chain)))
       (= (+ (creature-y chain) (cl-asciiquarium::creature-frame-index chain) -1)
          (1- (creature-y anchor)))))

(describe "anchor: shrinking resize"
  (flet ((rig-world ()
           (multiple-value-bind (world ship) (%anchor-ship-world :width 100 :height 40)
             (setf (entity-x (cl-asciiquarium::creature-entity ship)) 60.0f0)
             (world-advance world)
             (values world ship (%anchor-kind world :anchor) (%anchor-kind world :chain)))))
    (it "lands on the new sand with the chain in its shaft when the screen shrinks while it falls"
      (with-seeded-random-state (1)
        (multiple-value-bind (world ship anchor chain) (rig-world)
          (%advance-until world (lambda () (>= (creature-y anchor) 25)))
          (expect (%anchor-data anchor :phase) :to-be :fall)
          (world-resize world 40 24)
          (world-advance world)
          (with-soft-assertions
            (expect (%anchor-data anchor :phase) :to-be :rest)
            (expect (creature-y anchor) :to-be (- (cl-asciiquarium::world-sand-top world) 3))
            (expect (creature-x anchor) :to-be (+ (creature-x ship) 4))
            (expect (creature-x chain) :to-be (+ (creature-x anchor) 2))
            (expect (+ (creature-y chain) (cl-asciiquarium::creature-frame-index chain) -1)
                    :to-be (1- (creature-y anchor)))
            (expect (%anchor-rig-in-line-p ship anchor chain) :to-be-truthy)))))
    (it "moves a resting anchor up onto the new sand, chain and all"
      (with-seeded-random-state (1)
        (multiple-value-bind (world ship anchor chain) (rig-world)
          (%advance-until world (lambda () (eq (%anchor-data anchor :phase) :rest)))
          (expect (creature-y anchor) :to-be 33)
          (world-resize world 40 24)
          (world-advance world)
          (with-soft-assertions
            (expect (%anchor-data anchor :phase) :to-be :rest)
            (expect (creature-y anchor) :to-be (- (cl-asciiquarium::world-sand-top world) 3))
            (expect (%anchor-rig-in-line-p ship anchor chain) :to-be-truthy))
          (%advance-until world (lambda () (cl-asciiquarium::creature-removep anchor)))
          (expect (cl-asciiquarium::creature-removep chain) :to-be-truthy))))))

(describe "anchor: allocation"
  (flet ((bytes-consed-by-ticks (world anchor chain)
           (dotimes (i 100)
             (cl-asciiquarium::anchor-tick world anchor)
             (cl-asciiquarium::chain-tick world chain))
           (let ((before (sb-ext:get-bytes-consed)))
             (dotimes (i 10000)
               (cl-asciiquarium::anchor-tick world anchor)
               (cl-asciiquarium::chain-tick world chain))
             (- (sb-ext:get-bytes-consed) before))))
    (it "conses nothing on a falling or a resting tick"
      (with-seeded-random-state (1)
        (let ((world (%anchor-ship-world)))
          (world-advance world)
          (let* ((anchor (%anchor-kind world :anchor))
                 (chain (%anchor-data anchor :chain)))
            (expect (%anchor-data anchor :phase) :to-be :fall)
            (expect (bytes-consed-by-ticks world anchor chain) :to-be 0)
            (%advance-until world (lambda () (eq (%anchor-data anchor :phase) :rest)))
            (expect (bytes-consed-by-ticks world anchor chain) :to-be 0)
            (expect (%anchor-data anchor :phase) :to-be :rest)))))))

(describe "anchor: redraw"
  (it "clears the ship, the anchor, and the chain while the anchor is down"
    (with-seeded-random-state (1)
      (let ((world (%anchor-ship-world)))
        (%advance-until-landed world)
        (world-redraw world)
        (with-soft-assertions
          (expect (%anchor-kind world :ship) :to-be-null)
          (expect (%anchor-kind world :anchor) :to-be-null)
          (expect (%anchor-kind world :chain) :to-be-null))))))
