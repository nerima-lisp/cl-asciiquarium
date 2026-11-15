;;;; t/p4-integration-test.lisp -- the P4 seabed events as the player reaches
;;;; them: the a/m/d keys, the :sub and :diver rows of *AUTO-EVENTS*, the
;;;; big-event cap they share with the ship, and a long seeded run of the real
;;;; WORLD-ADVANCE with every seabed event in play.
(in-package #:cl-asciiquarium/test)

(defun p4-kind-count (world kind)
  (count kind (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind))

(defun p4-quiet-guests (world)
  (setf (cl-asciiquarium::world-guest-cooldown world) most-positive-fixnum)
  world)

(defun p4-press (world keys)
  (dolist (event (decode-input keys))
    (world-apply-key-event world event)))

(defun p4-auto-event-index (id)
  (position id cl-asciiquarium::*auto-events* :key (lambda (row) (getf row :id))))

(describe "P4 keys"
  (it-each (("a" :ship) ("A" :ship) ("m" :sub) ("M" :sub) ("d" :dinghy) ("D" :dinghy))
      "~S spawns a ~S"
      (key kind)
    (with-seeded-random-state (5)
      (let ((world (make-world :width 80 :height 24 :fish-count 0)))
        (p4-press world key)
        (expect (p4-kind-count world kind) :to-be 1))))
  (it "spawns past the cap of two big events"
    (with-seeded-random-state (5)
      (let ((world (make-world :width 80 :height 24 :fish-count 0)))
        (p4-press world "ama")
        (expect (cl-asciiquarium::big-event-count world) :to-be 3)
        (p4-press world "d")
        (expect (cl-asciiquarium::big-event-count world) :to-be 4))))
  (it "sends no second diver while one is out, and says so"
    (with-seeded-random-state (5)
      (let ((world (make-world :width 80 :height 24 :fish-count 0)))
        (p4-press world "dd")
        (with-soft-assertions
          (expect (p4-kind-count world :dinghy) :to-be 1)
          (expect (p4-kind-count world :diver) :to-be 1)
          (expect (cl-asciiquarium::world-notification world)
                  :to-equal cl-asciiquarium::+diver-busy-message+)))))
  (it "says why no diver comes when the screen holds no chest"
    (let ((world (tiny-world :width 20 :height 10)))
      (expect (cl-asciiquarium::find-creature-of-kind world :chest) :to-be-null)
      (p4-press world "d")
      (expect (p4-kind-count world :dinghy) :to-be 0)
      (expect (cl-asciiquarium::world-notification world)
              :to-equal cl-asciiquarium::+diver-no-chest-message+)))
  (it "lists the new keys in the help panel"
    (let ((keys (mapcar #'car cl-asciiquarium::+help-entries+)))
      (dolist (key '("a" "m" "d"))
        (expect (member key keys :test #'string=) :to-be-truthy)))))

(describe "P4 automatic events"
  (it-each ((:sub :sub 900) (:diver :dinghy 1200))
      "the ~S row brings a ~S at its :first tick ~D"
      (id kind first)
    (with-seeded-random-state (8)
      (let* ((world (p4-quiet-guests (make-world :width 80 :height 24 :fish-count 0)))
             (index (p4-auto-event-index id)))
        (setf (cl-asciiquarium::world-shark-enabled-p world) nil)
        (expect (svref (cl-asciiquarium::world-event-due world) index) :to-be first)
        ;; WORLD-ADVANCE counts the tick before it runs the table.
        (setf (svref (cl-asciiquarium::world-event-due world) index) (+ 2 (world-tick world)))
        (world-advance world)
        (expect (p4-kind-count world kind) :to-be 0)
        (world-advance world)
        (expect (p4-kind-count world kind) :to-be 1))))
  (it-each ((:sub) (:diver))
      "holds the ~S row back while two big events are on screen"
      (id)
    (with-seeded-random-state (8)
      (let* ((world (p4-quiet-guests (make-world :width 80 :height 24 :fish-count 0)))
             (index (p4-auto-event-index id)))
        (cl-asciiquarium::spawn-submarine-now world)
        (spawn-guest-now world :ship)
        (setf (svref (cl-asciiquarium::world-event-due world) index) (world-tick world))
        (world-advance world)
        (expect (cl-asciiquarium::big-event-count world) :to-be 2)
        (expect (> (svref (cl-asciiquarium::world-event-due world) index) (world-tick world))
                :to-be-truthy))))
  (it "lets a due :diver row pass without a chest"
    (let* ((world (tiny-world :width 20 :height 10))
           (index (p4-auto-event-index :diver)))
      (setf (svref (cl-asciiquarium::world-event-due world) index) (world-tick world))
      (world-advance world)
      (expect (p4-kind-count world :dinghy) :to-be 0)
      (expect (> (svref (cl-asciiquarium::world-event-due world) index) (world-tick world))
              :to-be-truthy))))

(describe "P4 integration"
  (it "runs 3000 ticks with every seabed event, never more than two automatic big events"
    (with-seeded-random-state (12)
      (let ((world (make-world :width 100 :height 30 :fish-count 18))
            (seen '())
            (most 0))
        (dotimes (i 3000)
          (world-advance world)
          (setf most (max most (cl-asciiquarium::big-event-count world)))
          (dolist (creature (cl-asciiquarium::world-%creatures world))
            (pushnew (cl-asciiquarium::creature-kind creature) seen)))
        (expect (<= most 2) :to-be-truthy)
        (dolist (kind '(:chest :plume :octopus :sub :sonar :dinghy :diver :coin))
          (expect (member kind seen) :to-be-truthy)))))
  (it "keeps exactly one of each resident seabed creature through a resize and a redraw"
    (with-seeded-random-state (11)
      (let ((world (make-world :width 100 :height 30 :fish-count 4)))
        (world-resize world 90 28)
        (world-redraw world)
        (dolist (kind '(:chest :vent :rock :plume :octopus :crab))
          (expect (p4-kind-count world kind) :to-be 1))))))
