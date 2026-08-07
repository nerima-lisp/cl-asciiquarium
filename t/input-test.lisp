(in-package #:cl-asciiquarium/test)

(describe "world-apply-key-event"
  (it-each (("q" t) ("Q" t) ("x" nil) (#.(string (code-char 3)) t))
      "sets quitp to ~S on key input ~S"
      (key expected-quitp)
    (let ((world (tiny-world)))
      (dolist (event (decode-input key))
        (world-apply-key-event world event))
      (expect (and (world-quitp world) t) :to-be expected-quitp)))
  (it "calls world-redraw on an r key event, repopulating fish"
    (with-seeded-random-state (4)
      (let* ((world (make-world :width 40 :height 20 :fish-count 3))
             (original-fish (remove :fish (world-creatures world) :key #'creature-kind :test-not #'eq)))
        (dolist (event (decode-input "r"))
          (world-apply-key-event world event))
        (let ((new-fish (remove :fish (world-creatures world) :key #'creature-kind :test-not #'eq)))
          (expect (= (length new-fish) 3) :to-be-truthy)
          (expect (intersection original-fish new-fish) :to-be-falsy)))))
  (it "ignores an unbound special key without changing world state"
    (let ((world (tiny-world)))
      (world-apply-key-events world (decode-input (format nil "~C[A" #\Escape)))
      (with-soft-assertions
        (expect (world-quitp world) :to-be-null)
        (expect (world-paused-p world) :to-be-null)))))

(describe "world-apply-key-events"
  (it "applies a sequence of decoded events in order"
    (let ((world (tiny-world)))
      (world-apply-key-events world (decode-input "xq"))
      (expect (world-quitp world) :to-be-truthy))))

(describe "space toggles pause"
  (it "pauses on the first press and resumes on the second"
    (let ((world (tiny-world)))
      (world-apply-key-events world (decode-input " "))
      (expect (world-paused-p world) :to-be-truthy)
      (world-apply-key-events world (decode-input " "))
      (expect (world-paused-p world) :to-be-falsy))))

(describe "+/- adjust the live fish count"
  (it-each (("+" 3) ("=" 3) ("-" 1) ("_" 1))
      "~S changes world-fish-count from 2 to ~D"
      (key expected)
    (with-seeded-random-state (10)
      (let ((world (make-world :width 40 :height 20 :fish-count 2)))
        (world-apply-key-events world (decode-input key))
        (expect (world-fish-count world) :to-be expected)))))

(describe "s force-spawns a shark"
  (it "adds a shark immediately, without waiting for the cooldown"
    (let ((world (tiny-world :width 40 :height 20)))
      (setf (world-shark-cooldown world) 999)
      (world-apply-key-events world (decode-input "s"))
      (expect (find :shark (world-creatures world) :key #'creature-kind) :to-be-truthy)))
  (it "is a no-op when sharks are disabled"
    (let ((world (tiny-world :width 40 :height 20)))
      (setf (world-shark-enabled-p world) nil)
      (world-apply-key-events world (decode-input "s"))
      (expect (find :shark (world-creatures world) :key #'creature-kind) :to-be-null))))

(describe "g force-spawns a guest"
  (it "adds one of the known guest kinds immediately"
    (with-seeded-random-state (12)
      (let ((world (tiny-world :width 40 :height 20)))
        (world-apply-key-events world (decode-input "g"))
        (expect (find-if (lambda (creature)
                            (member (creature-kind creature)
                                    '(:ship :duck-line :dolphin :sea-monster)))
                          (world-creatures world))
                :to-be-truthy)))))

(describe "h toggles the help overlay"
  (it "adds the overlay on the first press and removes it on the second"
    (let ((world (tiny-world)))
      (world-apply-key-events world (decode-input "h"))
      (expect (find :help-overlay (world-creatures world) :key #'creature-kind) :to-be-truthy)
      (world-apply-key-events world (decode-input "h"))
      (expect (find :help-overlay (world-creatures world) :key #'creature-kind) :to-be-null))))
