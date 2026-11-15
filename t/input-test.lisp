(in-package #:cl-asciiquarium/test)

(describe
 "world-apply-key-event"
 (it-each
  (("q" t) ("Q" t) ("x" nil) (#.(string (code-char 3)) t))
  "sets quitp to ~S on key input ~S"
  (key expected-quitp)
  (let ((world (tiny-world)))
    (dolist (event (decode-input key))
      (world-apply-key-event world event))
    (expect (and (world-quitp world) t) :to-be expected-quitp)))
 (it
  "calls world-redraw on an r key event, repopulating fish"
  (with-seeded-random-state
   (4)
   (let* ((world (make-world :width 40 :height 20 :fish-count 3))
          (original-fish
           (remove
            :fish
            (cl-asciiquarium::world-%creatures world)
            :key
            #'cl-asciiquarium::creature-kind
            :test-not
            #'eq)))
     (dolist (event (decode-input "r"))
       (world-apply-key-event world event))
     (let ((new-fish
            (remove
             :fish
             (cl-asciiquarium::world-%creatures world)
             :key
             #'cl-asciiquarium::creature-kind
             :test-not
             #'eq)))
       (expect (= (length new-fish) 3) :to-be-truthy)
       (expect (intersection original-fish new-fish) :to-be-falsy)))))
 (it
  "ignores an unbound special key without changing world state"
  (let ((world (tiny-world)))
    (world-apply-key-events world (decode-input (format nil "~C[A" #\Escape)))
    (with-soft-assertions
     (expect (world-quitp world) :to-be-null)
     (expect (world-paused-p world) :to-be-null)))))

(describe
 "world-apply-key-events"
 (it
  "applies a sequence of decoded events in order"
  (let ((world (tiny-world)))
    (world-apply-key-events world (decode-input "xq"))
    (expect (world-quitp world) :to-be-truthy))))

(describe
 "space toggles pause"
 (it
  "pauses on the first press and resumes on the second"
 ;; 40 columns: a 20-column status bar has no room for the swimming state.
 (let ((world (tiny-world :width 40)))
    (world-apply-key-events world (decode-input " "))
    (expect (world-paused-p world) :to-be-truthy)
    (expect (search "paused"
                    (creature-art
                     (find :hud (cl-asciiquarium::world-%creatures world)
                           :key #'cl-asciiquarium::creature-kind)))
            :to-be-truthy)
    (world-apply-key-events world (decode-input " "))
    (expect (world-paused-p world) :to-be-falsy)
    (expect (search "swimming"
                    (creature-art
                     (find :hud (cl-asciiquarium::world-%creatures world)
                           :key #'cl-asciiquarium::creature-kind)))
            :to-be-truthy))))

(describe
 "t/u visual controls"
 (it
  "cycles the visual theme"
  (let ((world (make-world :width 40 :height 20 :fish-count 0)))
    (world-apply-key-events world (decode-input "t"))
    (expect (world-theme world) :to-be :coral)))
 (it
  "toggles the HUD visibility"
  (let ((world (make-world :width 40 :height 20 :fish-count 0)))
    (world-apply-key-events world (decode-input "u"))
    (expect (cl-asciiquarium::world-hud-visible-p world) :to-be-falsy)
    (expect (find :hud (cl-asciiquarium::world-%creatures world)
                  :key #'cl-asciiquarium::creature-kind)
            :to-be-null))))

(describe
 "+/- adjust the live fish count"
 (it-each
  (("+" 3) ("=" 3) ("-" 1) ("_" 1))
  "~S changes world-fish-count from 2 to ~D"
  (key expected)
  (with-seeded-random-state
   (10)
   (let ((world (make-world :width 40 :height 20 :fish-count 2)))
     (world-apply-key-events world (decode-input key))
     (expect (world-fish-count world) :to-be expected)))))

(describe
 "s force-spawns a shark"
 (it
  "adds a shark immediately, without waiting for the cooldown"
  (let ((world (tiny-world :width 40 :height 20)))
    (setf (cl-asciiquarium::world-shark-cooldown world) 999)
    (world-apply-key-events world (decode-input "s"))
    (expect
     (find
      :shark
      (cl-asciiquarium::world-%creatures world)
      :key
      #'cl-asciiquarium::creature-kind)
     :to-be-truthy)))
 (it
  "is a no-op when sharks are disabled"
  (let ((world (tiny-world :width 40 :height 20)))
    (setf (world-shark-enabled-p world) nil)
    (world-apply-key-events world (decode-input "s"))
    (expect
     (find
      :shark
      (cl-asciiquarium::world-%creatures world)
      :key
      #'cl-asciiquarium::creature-kind)
     :to-be-null))))

(describe
 "g force-spawns a guest"
 (it
  "adds one of the known guest kinds immediately"
  (with-seeded-random-state
   (12)
   (let ((world (tiny-world :width 40 :height 20)))
     (world-apply-key-events world (decode-input "g"))
     (expect
      (find-if
       (lambda (creature)
         (member
          (cl-asciiquarium::creature-kind creature)
          '(:ship :duck-line :dolphin :sea-monster)))
       (cl-asciiquarium::world-%creatures world))
      :to-be-truthy)))))

(describe
 "h toggles the help overlay"
 (it
  "adds and removes the overlay through cache-aware internal state"
  (let ((world (tiny-world)))
    (world-apply-key-events world (decode-input "h"))
    (expect
     (find
      :help-overlay
      (cl-asciiquarium::world-%creatures world)
      :key
      (function cl-asciiquarium::creature-kind))
     :to-be-truthy)
    (world-apply-key-events world (decode-input "h"))
    (expect
     (find
      :help-overlay
      (cl-asciiquarium::world-%creatures world)
      :key
      (function cl-asciiquarium::creature-kind))
     :to-be-null))))

(describe
 "w and n advance the weather and the time of day"
 (it-each
  (("w" :rain) ("W" :rain) ("ww" :storm) ("www" :clear))
  "keys ~S leave the weather at ~S"
  (keys weather)
  (let ((world (tiny-world)))
    (world-apply-key-events world (decode-input keys))
    (expect (cl-asciiquarium::world-weather world) :to-be weather)))
 (it-each
  (("n" :abyss) ("N" :abyss) ("nn" :moonlight) ("nnn" :coral))
  "keys ~S move a :coral world to ~S and restart the cycle"
  (keys theme)
  (let ((world (make-world :width 20 :height 10 :fish-count 0 :theme :coral)))
    (dotimes (i 10) (world-advance world))
    (world-apply-key-events world (decode-input keys))
    (expect (world-theme world) :to-be theme)
    (expect (cl-asciiquarium::world-daypart-at world) :to-be (+ 10 cl-asciiquarium::+daypart-ticks+)))))

(describe
 "e sprinkles food"
 (it-each
  (("e") ("E"))
  "key ~S adds six grains"
  (key)
  (let ((world (tiny-world :width 80 :height 24)))
    (world-apply-key-events world (decode-input key))
    (expect (count :food (cl-asciiquarium::world-%creatures world)
                   :key #'cl-asciiquarium::creature-kind)
            :to-be 6)))
 (it
  "leaves no grain after r redraws the tank"
  (let ((world (tiny-world :width 80 :height 24)))
    (world-apply-key-events world (decode-input "er"))
    (expect (count :food (cl-asciiquarium::world-%creatures world)
                   :key #'cl-asciiquarium::creature-kind)
            :to-be 0))))

(defun %open-overlays (world)
  "The kinds of the panels open in WORLD."
  (loop for creature in (cl-asciiquarium::world-%creatures world)
        for kind = (cl-asciiquarium::creature-kind creature)
        when (member kind '(:help-overlay :zukan-overlay))
          collect kind))

(describe
 "z toggles the dex panel, one panel open at a time"
 (it-each
  (("z" (:zukan-overlay)) ("Z" (:zukan-overlay)) ("zz" nil)
   ("hz" (:zukan-overlay)) ("zh" (:help-overlay)) ("hh" nil) ("hzh" (:help-overlay)))
  "keys ~S leave the panels ~S open"
  (keys open)
  (let ((world (tiny-world :width 80 :height 24)))
    (world-apply-key-events world (decode-input keys))
    (expect (%open-overlays world) :to-equal open)))
 (it
  "opens and closes while paused"
  (let ((world (tiny-world :width 80 :height 24)))
    (world-apply-key-events world (decode-input " z"))
    (expect (%open-overlays world) :to-equal '(:zukan-overlay))
    (world-advance world)
    (world-apply-key-events world (decode-input "z"))
    (expect (%open-overlays world) :to-be nil))))

(describe
 "p asks for a snapshot"
 (it-each
  (("p") ("P"))
  "key ~S sets the request the poller saves"
  (key)
  (let ((world (tiny-world)))
    (expect (cl-asciiquarium::world-snapshot-requested-p world) :to-be nil)
    (world-apply-key-events world (decode-input key))
    (expect (cl-asciiquarium::world-snapshot-requested-p world) :to-be t))))

(defun %help-characters ()
  "The characters the help panel names: each key of +HELP-ENTRIES+, split at
\" / \", with \"space\" read as the space character."
  (loop for (key) in cl-asciiquarium::+help-entries+
        append (loop for start = 0 then (+ end 3)
                     for end = (or (search " / " key :start2 start) (length key))
                     for name = (subseq key start end)
                     collect (if (string= name "space") #\Space (char name 0))
                     while (< end (length key)))))

(describe
 "the help panel"
 (it
  "fits within the water on an 80x24 screen"
  (let* ((world (make-world :width 80 :height 24 :fish-count 0))
         (overlay (cl-asciiquarium::make-help-overlay world))
         (height (nth-value 1 (creature-dimensions overlay)))
         (water-rows (- (world-sand-top world) (creature-y overlay))))
    (expect (<= height water-rows) :to-be-truthy)))
 (it
  "names a key of every binding, and the quit and shark keys handled outside the table"
  (let ((named (%help-characters)))
    (expect (remove-if (lambda (characters) (intersection characters named))
                       (mapcar #'car cl-asciiquarium::+key-bindings+))
            :to-be nil)
    (expect (subsetp '(#\q #\s) named) :to-be-truthy))))
