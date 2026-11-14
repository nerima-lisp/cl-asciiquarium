;;;; t/art-fish-test.lisp
(in-package #:cl-asciiquarium/test)

(describe "make-fish"
  (it "signals unknown-species for an unrecognized species keyword"
    (let ((world (tiny-world)))
      (expect (lambda () (make-fish world :species :nonexistent-species))
              :to-throw 'asciiquarium-unknown-species)))

  (it "builds the requested species, ignoring any random default"
    (let* ((world (tiny-world))
           (fish (make-fish world :species :puffer :x 3 :y 4 :dx 0)))
      (expect (cl-asciiquarium::creature-kind fish) :to-be :fish)
      (expect (getf (cl-asciiquarium::creature-data fish) :species) :to-be :puffer)))

  (it "positions the fish at the given x and y"
    (let* ((world (tiny-world))
           (fish (make-fish world :species :puffer :x 3 :y 4 :dx 0)))
      (expect (creature-x fish) :to-be 3)
      (expect (creature-y fish) :to-be 4)))

  (it "defaults to one of the known species and a lane inside the world, given a seed"
    (with-seeded-random-state (13)
      (let* ((world (tiny-world :width 40 :height 20))
             (fish (make-fish world)))
        (expect (find (getf (cl-asciiquarium::creature-data fish) :species)
                      cl-asciiquarium::+fish-species+
                      :key (function cl-asciiquarium::fish-species-entry-name))
                :to-be-truthy)
        (expect (<= 0 (creature-y fish) (world-height world)) :to-be-truthy))))

  (it-each ((:right) (:left))
      "an explicit :facing ~A is honored regardless of the random default"
      (facing)
    (let* ((world (tiny-world))
           (fish (make-fish world :species :dart :facing facing)))
      (expect (creature-facing fish) :to-be facing)))

  (it "lets an explicit :dx win for velocity even when :facing differs"
    (let* ((world (tiny-world))
           (fish (make-fish world :species :dart :facing :left :dx 1)))
      (expect (creature-facing fish) :to-be :left)
      (expect (entity-dx (cl-asciiquarium::creature-entity fish)) :to-be 1)))

  (it "uses a single-float velocity for generated movement"
    (let* ((world (tiny-world))
           (fish (make-fish world :species :dart)))
      (expect (typep (entity-dx (cl-asciiquarium::creature-entity fish)) 'single-float)
              :to-be-truthy))))
(describe "kill-fish"
  (it "does not restart an active death animation"
    (let* ((world (tiny-world))
           (fish (make-fish world :species :puffer :x 3 :y 4 :dx 1)))
      (cl-asciiquarium::kill-fish fish)
      (let ((data (copy-list (cl-asciiquarium::creature-data fish)))
            (ttl (cl-asciiquarium::creature-ttl fish))
            (frame-index (cl-asciiquarium::creature-frame-index fish))
            (dx (entity-dx (cl-asciiquarium::creature-entity fish)))
            (dy (entity-dy (cl-asciiquarium::creature-entity fish))))
        (cl-asciiquarium::kill-fish fish)
        (expect (cl-asciiquarium::creature-data fish) :to-equal data)
        (expect (cl-asciiquarium::creature-ttl fish) :to-be ttl)
        (expect (cl-asciiquarium::creature-frame-index fish) :to-be frame-index)
        (expect (entity-dx (cl-asciiquarium::creature-entity fish)) :to-be dx)
        (expect (entity-dy (cl-asciiquarium::creature-entity fish)) :to-be dy)))))

(describe "fish species color variation"
  (it "paints every individual with a style, none of them monochrome by default"
    (with-seeded-random-state (21)
      (let* ((world (tiny-world))
             (fish (make-fish world :species :guppy)))
        (expect (creature-style fish) :to-be-truthy))))
  (it "draws at least two different colors across many individuals of one species, given a seed"
    ;; Both specified guppy palettes must remain reachable.
    (with-seeded-random-state (17)
      (let* ((world (tiny-world))
             (styles (loop repeat 30 collect (creature-style (make-fish world :species :guppy)))))
        (expect (> (length (remove-duplicates styles :test #'equalp)) 1) :to-be-truthy)))))
(describe "make-fish prepared sprite sharing"
  (it "shares a monochrome species prototype until public frame mutation"
    (let ((cl-asciiquarium::*monochrome* t)
          (cl-asciiquarium::*fish-sprite-prototypes*
            (make-hash-table :test #'eq)))
      (with-seeded-random-state (31)
        (let* ((world (tiny-world))
               (first
                 (make-fish world :species :dart :x 3 :y 4 :dx 0 :facing :right))
               (sibling
                 (make-fish world :species :dart :x 5 :y 4 :dx 0 :facing :right))
               (sibling-art
                 (copy-seq
                  (aref (cl-asciiquarium::creature-%frames sibling) 0))))
          (expect
            (cl-asciiquarium::creature-%prepared-frames first)
            :to-be
            (cl-asciiquarium::creature-%prepared-frames sibling))
          (expect
            (cl-asciiquarium::creature-%frames first)
            :to-be
            (cl-asciiquarium::creature-%frames sibling))
          (setf (char (aref (creature-frames first) 0) 0) #\X)
          (expect (creature-art first) :not :to-equal sibling-art)
          (expect
            (aref (cl-asciiquarium::creature-%frames sibling) 0)
            :to-equal
            sibling-art)
          (let ((future
                  (make-fish world :species :dart :x 7 :y 4 :dx 0 :facing :right)))
            (expect
              (cl-asciiquarium::creature-%prepared-frames future)
              :to-be
              (cl-asciiquarium::creature-%prepared-frames sibling))
            (expect
              (aref (cl-asciiquarium::creature-%frames future) 0)
              :to-equal
              sibling-art)))))))

(describe "fish species data"
  (it "contains exactly the sixteen specified species without duplicates"
    (expect (mapcar #'cl-asciiquarium::fish-species-entry-name
                    cl-asciiquarium::+fish-species+)
            :to-equal
            '(:dart :puffer :ribbon :angel :guppy :clown :tang :eel
              :lantern :jelly :seahorse :turtle :squid :butterfly :golden :oarfish)))

  (it-each ((:dart 0.5 0.7) (:puffer 0.15 0.25) (:ribbon 0.3 0.4)
            (:angel 0.25 0.35) (:guppy 0.4 0.6) (:clown 0.3 0.45)
            (:tang 0.35 0.5) (:eel 0.2 0.3) (:lantern 0.12 0.18)
            (:jelly 0.04 0.07) (:seahorse 0.03 0.05) (:turtle 0.12 0.16)
            (:squid 0.45 0.6) (:butterfly 0.25 0.35) (:golden 0.5 0.7)
            (:oarfish 0.15 0.2))
      "stores ~A speed bounds ~A to ~A and four-color hexadecimal palettes"
      (name low high)
    (let* ((entry (cl-asciiquarium::fish-species name))
           (palettes (cl-asciiquarium::fish-species-entry-color-sets entry)))
      (expect (cl-asciiquarium::fish-species-entry-speed-range entry)
              :to-equal (list low high))
      (expect palettes :to-be-truthy)
      (dolist (palette palettes)
        (expect (length palette) :to-be 4)
        (dolist (color palette)
          (expect (length color) :to-be 7)
          (expect (char color 0) :to-be #\#)
          (expect (every (lambda (char) (find char "0123456789ABCDEF"))
                         (subseq color 1))
                  :to-be-truthy)))))

  (it "marks only the specified small, drifting, and rare species"
    (flet ((names-with (predicate)
             (mapcar #'cl-asciiquarium::fish-species-entry-name
                     (remove-if-not predicate cl-asciiquarium::+fish-species+))))
      (expect (names-with #'cl-asciiquarium::fish-species-entry-small-p)
              :to-equal '(:dart :guppy :clown))
      (expect (names-with #'cl-asciiquarium::fish-species-entry-drifts-p)
              :to-equal '(:jelly :seahorse))
      (expect (names-with #'cl-asciiquarium::fish-species-entry-spawn-probability)
              :to-equal '(:golden :oarfish))))

  (it-each ((:dart) (:puffer) (:ribbon) (:angel) (:guppy) (:clown) (:tang)
            (:eel) (:lantern) (:jelly) (:seahorse) (:turtle) (:squid)
            (:butterfly) (:golden) (:oarfish))
      "keeps ~A art and mask aligned in both orientations and builds either facing"
      (name)
    (let* ((entry (cl-asciiquarium::fish-species name))
           (art (cl-asciiquarium::fish-species-entry-art entry))
           (mask (cl-asciiquarium::fish-species-entry-mask entry))
           (world (tiny-world)))
      (dolist (facing '(:right :left))
        (let* ((facing-art (if (eq facing :left) (mirror-sprite-text art) art))
               (facing-mask (if (eq facing :left)
                                (cl-asciiquarium::mirror-sprite-mask mask)
                                mask))
               (art-lines (cl-asciiquarium::split-sprite-lines facing-art))
               (mask-lines (cl-asciiquarium::split-sprite-lines facing-mask))
               (fish (make-fish world :species name :facing facing :dx 0)))
          (if (cl-asciiquarium::fish-species-entry-spawn-probability entry)
              (expect (find #\✦ (creature-art fish)) :to-be-truthy)
              (expect (creature-art fish) :to-equal facing-art))
          (expect (creature-style fish) :to-be-truthy)
          (expect (length art-lines) :to-be (length mask-lines))
          (expect (> (length art) 0) :to-be-truthy)
          (loop for art-line in art-lines
                for mask-line in mask-lines
                do (expect (length art-line) :to-be (length mask-line))
                   (loop for glyph across art-line
                         for role across mask-line
                         do (expect (<= 32 (char-code glyph) 126) :to-be-truthy)
                            (expect (find role " bftesl") :to-be-truthy)
                            ;; A painted space may fill a body; a visible glyph
                            ;; must never lie in a transparent mask cell.
                            (expect (or (char= glyph #\Space)
                                        (char/= role #\Space))
                                    :to-be-truthy)))))))

  (it "preserves the puffer's opaque interior space and transparent margin"
    (let* ((entry (cl-asciiquarium::fish-species :puffer))
           (art (cl-asciiquarium::split-sprite-lines
                 (cl-asciiquarium::fish-species-entry-art entry)))
           (mask (cl-asciiquarium::split-sprite-lines
                  (cl-asciiquarium::fish-species-entry-mask entry))))
      (expect (char (second art) 3) :to-be #\Space)
      (expect (char (second mask) 3) :to-be #\b)
      (expect (char (first art) 0) :to-be #\Space)
      (expect (char (first mask) 0) :to-be #\Space)))

  (it "reverses mask rows without swapping parentheses or row order"
    (expect (cl-asciiquarium::mirror-sprite-mask (format nil "b(f~% te"))
            :to-equal (format nil "f(b~%et ")))

  (it "normalizes turtle art and the corrected ten-cell shell mask to face right"
    (let ((entry (cl-asciiquarium::fish-species :turtle)))
      (expect (cl-asciiquarium::fish-species-entry-art entry)
              :to-equal
              (format nil "    .---.   ~%  _/_\\_/_\\_ ~%=(        o)~%  '-\"  '-\"  "))
      (expect (cl-asciiquarium::fish-species-entry-mask entry)
              :to-equal (format nil "    fffff   ~%  fffffffff ~%tb        eb~%  bbb  bbb  "))))

  (it "normalizes squid art and mask to face right at load time"
    (let ((entry (cl-asciiquarium::fish-species :squid)))
      (expect (cl-asciiquarium::fish-species-entry-art entry)
              :to-equal (format nil "    .--,  ~%=~~~~(   o)>~%    '--`  "))
      (expect (cl-asciiquarium::fish-species-entry-mask entry)
              :to-equal (format nil "    ffff  ~%tttb   ebb~%    ffff  ")))))

(describe "fish species runtime"
  (it "uses each species speed interval and keeps facing and movement consistent"
    (with-seeded-random-state (77)
      (let ((world (tiny-world :height 24)))
        (dolist (entry cl-asciiquarium::+fish-species+)
          (destructuring-bind (low high) (cl-asciiquarium::fish-species-entry-speed-range entry)
            (dolist (facing '(:left :right))
              (dotimes (sample 8)
                (let* ((fish (make-fish world :species (cl-asciiquarium::fish-species-entry-name entry)
                                             :facing facing))
                       (dx (entity-dx (cl-asciiquarium::creature-entity fish))))
                  (expect (typep dx 'single-float) :to-be-truthy)
                  (expect (<= low (abs dx) high) :to-be-truthy)
                  (expect (plusp dx) :to-be (eq facing :right))))))))))

  (it "uses the swim band for full sprites and builds without error at tiny heights"
    (with-seeded-random-state (78)
      (dolist (height '(1 2 5 10 24 40))
        (let ((world (tiny-world :height height)))
          (dolist (entry cl-asciiquarium::+fish-species+)
            (let* ((fish (make-fish world :species (cl-asciiquarium::fish-species-entry-name entry)))
                   (fish-height (nth-value 1 (creature-dimensions fish)))
                   (y (creature-y fish)))
              (expect fish :to-be-truthy)
              (when (>= height 24)
                (multiple-value-bind (top bottom) (cl-asciiquarium::world-swim-band world)
                  (expect (<= top y) :to-be-truthy)
                  (expect (<= (+ y fish-height -1) bottom) :to-be-truthy)))))))))

  (it "passes masks for every fish and the exact selected dart colors in either orientation"
    (let ((cl-asciiquarium::*color-mode* :truecolor))
      (with-seeded-random-state (79)
        (let ((world (tiny-world :height 24))
              (seen nil))
          (dolist (entry cl-asciiquarium::+fish-species+)
            (dolist (facing '(:right :left))
              (expect (cl-asciiquarium::creature-%masks
                       (make-fish world :species (cl-asciiquarium::fish-species-entry-name entry)
                                        :facing facing)) :to-be-truthy)))
          (dotimes (birth 40)
            (let* ((fish (make-fish world :species :dart :facing (if (evenp birth) :left :right)))
                   (index (getf (cl-asciiquarium::creature-data fish) :palette-index))
                   (colors (nth index '(((95 215 230) (47 159 179) (31 111 128) (244 251 255))
                                        ((126 224 161) (75 179 119) (47 125 82) (240 255 245))))))
              (pushnew index seen)
              (loop for role across "bfte" for rgb in colors
                    do (expect (cdr (assoc role (cl-asciiquarium::creature-%role-styles fish)))
                               :to-equal (make-style (cl-tty-kit:style-bg 8 21 33) (apply #'style-fg rgb))))
              (expect (creature-style fish)
                      :to-equal (make-style (cl-tty-kit:style-bg 8 21 33) (apply #'style-fg (first colors))))))
          (expect (sort seen #'<) :to-equal '(0 1))))))

  (it "keys prototypes by selected palette, theme, effective color mode, and ASCII"
    (let* ((cl-asciiquarium::*fish-sprite-prototypes* (make-hash-table :test #'eq))
           (cl-asciiquarium::*color-mode* :truecolor)
           (cl-asciiquarium::*ascii* nil)
           (entry (cl-asciiquarium::fish-species :dart))
           (first (cl-asciiquarium::%fish-sprite-prototype entry 0 :abyss)))
      (expect first :to-be (cl-asciiquarium::%fish-sprite-prototype entry 0 :abyss))
      (expect first :not :to-be (cl-asciiquarium::%fish-sprite-prototype entry 1 :abyss))
      (expect (creature-style first) :not :to-equal
              (creature-style (cl-asciiquarium::%fish-sprite-prototype entry 1 :abyss)))
      (expect first :not :to-be (cl-asciiquarium::%fish-sprite-prototype entry 0 :coral))
      (let ((cl-asciiquarium::*color-mode* :ansi256))
        (expect first :not :to-be (cl-asciiquarium::%fish-sprite-prototype entry 0 :abyss)))
      (let ((cl-asciiquarium::*ascii* t))
        (expect first :not :to-be (cl-asciiquarium::%fish-sprite-prototype entry 0 :abyss)))
      (let* ((cl-asciiquarium::*monochrome* t)
             (mono (cl-asciiquarium::%fish-sprite-prototype entry 0 :abyss)))
        (expect (creature-style mono) :to-be-falsy)
        (let ((cl-asciiquarium::*color-mode* :ansi16))
          (expect mono :to-be (cl-asciiquarium::%fish-sprite-prototype entry 1 :abyss)))
        (let ((cl-asciiquarium::*monochrome* nil)
              (cl-asciiquarium::*color-mode* :mono))
          (expect mono :to-be (cl-asciiquarium::%fish-sprite-prototype entry 1 :abyss))))))

  (it-each ((:golden) (:oarfish))
      "renders the exact ~A glow art and mask in either facing and ASCII mode"
      (name)
    (let* ((entry (cl-asciiquarium::fish-species name))
           (original (copy-seq (cl-asciiquarium::fish-species-entry-art entry)))
           (world (tiny-world :height 24))
           (expected-art (ecase name
                           (:golden (format nil "  __ ✦~%>=(('>~%  ``"))
                           (:oarfish (format nil "  ,,,,,,,,,,,,, ✦~%=~~~~~~~~~~~~~~~~~~~~~~~~~~(o>~%             `"))))
           (expected-mask (ecase name
                            (:golden (format nil "  ff l~%ttbbeb~%  ff"))
                            (:oarfish (format nil "  fffffffffffff l~%tbbbbbbbbbbbbbbeb~%             f")))))
      (dolist (ascii '(nil t))
        (let ((cl-asciiquarium::*ascii* ascii)
              (cl-asciiquarium::*color-mode* :truecolor))
          (dolist (facing '(:right :left))
            (let* ((fish (make-fish world :species name :x 0 :y 0 :facing facing))
                   (art (if ascii (substitute #\* #\✦ expected-art) expected-art))
                   (mask expected-mask)
                   (screen (make-screen 30 8)))
              (when (eq facing :left)
                (setf art (mirror-sprite-text art)
                      mask (cl-asciiquarium::mirror-sprite-mask mask)))
              (expect (creature-art fish) :to-equal art)
              (expect (aref (if (eq facing :left)
                                (cl-asciiquarium::creature-%mirrored-masks fish)
                                (cl-asciiquarium::creature-%masks fish)) 0)
                      :to-equal mask)
              (cl-asciiquarium::creature-blit screen fish)
              (expect (loop for y below 8 thereis
                            (loop for x below 30 thereis
                                  (eql (cell-char (screen-cell screen x y))
                                       (if ascii #\* #\✦))))
                      :to-be-truthy)
              (expect (cdr (assoc #\l (cl-asciiquarium::creature-%role-styles fish)))
                      :to-equal (make-style (cl-tty-kit:style-bg 8 21 33) (style-fg 255 224 138)))))))
      (expect (cl-asciiquarium::fish-species-entry-art entry) :to-equal original)))

  (it "spawns about three percent golden and two percent oarfish in 10000 seeded births"
    (with-seeded-random-state (2026)
      (let ((world (make-world :width 80 :height 24 :fish-count 0 :hud-visible-p nil))
            (counts (make-hash-table :test #'eq)))
        (dotimes (birth 10000)
          (let ((name (getf (cl-asciiquarium::creature-data (make-fish world)) :species)))
            (incf (gethash name counts 0))))
        (expect (loop for n being the hash-values of counts sum n) :to-be 10000)
        (expect (hash-table-count counts) :to-be 16)
        ;; The tolerance is 0.5 percentage points for either specified rate.
        (expect (<= 250 (gethash :golden counts) 350) :to-be-truthy)
        (expect (<= 150 (gethash :oarfish counts) 250) :to-be-truthy))))

  (it "reproduces birth choices, positions, speeds, and drift phases with the same seed"
    (flet ((births ()
             (with-seeded-random-state (80)
               (let ((world (tiny-world :height 24)))
                 (loop repeat 100
                       for fish = (make-fish world)
                       collect (list (copy-list (cl-asciiquarium::creature-data fish))
                                     (creature-x fish) (creature-y fish)
                                     (entity-dx (cl-asciiquarium::creature-entity fish))))))))
      (expect (births) :to-equal (births))))

  (it-each ((:jelly) (:seahorse))
      "moves ~A up and down through the real fish tick without leaving the water"
      (name)
    (with-seeded-random-state (81)
      (let* ((world (make-world :width 80 :height 24 :fish-count 0 :shark-enabled-p nil))
             (fish (make-fish world :species name :x 10 :y 12 :dx 0))
             (data (cl-asciiquarium::creature-data fish))
             (positions nil))
        (setf (getf data :bubble-timer) 1000)
        (dotimes (tick 120)
          (setf (cl-asciiquarium::world-tick world) tick)
          (cl-asciiquarium::tick-creature world fish 80 24)
          (pushnew (creature-y fish) positions)
          (expect (<= 7 (creature-y fish) 15) :to-be-truthy))
        (expect (sort positions #'<) :to-equal '(11 12 13))
        (expect (cl-asciiquarium::creature-data fish) :to-be data)
        (cl-asciiquarium::kill-fish fish)
        (let ((y (creature-y fish)))
          (incf (cl-asciiquarium::world-tick world) 30)
          (cl-asciiquarium::tick-creature world fish 80 24)
          (expect (creature-y fish) :to-be y)))))

  (it "leaves ordinary fish unchanged and bounds drift by the resized swim band"
    (let* ((world (tiny-world :height 24))
           (dart (make-fish world :species :dart :y 12 :dx 0))
           (jelly (make-fish world :species :jelly :y 12 :dx 0)))
      (cl-asciiquarium::fish-drift-tick world dart)
      (expect (creature-y dart) :to-be 12)
      (world-resize world 10 5)
      (dotimes (tick 120)
        (setf (cl-asciiquarium::world-tick world) tick)
        (cl-asciiquarium::fish-drift-tick world jelly)
        (expect (creature-y jelly) :to-be (cl-asciiquarium::world-swim-band world)))))

  (it "restyles live and dead fish without changing frames, motion, data, or random state"
    (let ((cl-asciiquarium::*color-mode* :truecolor))
      (with-seeded-random-state (82)
        (let* ((world (tiny-world :height 24))
               (live (make-fish world :species :jelly :x 3 :y 12 :facing :left))
               (dead (make-fish world :species :puffer :x 20 :y 12)))
          (cl-asciiquarium::kill-fish dead)
          (dolist (fish (list live dead)) (cl-asciiquarium::%add-world-creature world fish))
          (let ((snapshots (loop for fish in (list live dead)
                                 collect (list (cl-asciiquarium::creature-%frames fish)
                                               (cl-asciiquarium::creature-data fish)
                                               (creature-x fish) (creature-y fish)
                                               (entity-dx (cl-asciiquarium::creature-entity fish))
                                               (cl-asciiquarium::creature-ttl fish)
                                               (copy-tree (creature-style fish)))))
                (rng (make-random-state *random-state*)))
            (world-set-theme world :coral)
            (expect (random 1000000) :to-be (random 1000000 rng))
            (loop for fish in (list live dead) for snapshot in snapshots
                  do (destructuring-bind (frames data x y dx ttl style) snapshot
                       (expect (cl-asciiquarium::creature-%frames fish) :to-be frames)
                       (expect (cl-asciiquarium::creature-data fish) :to-be data)
                       (expect (list (creature-x fish) (creature-y fish)
                                     (entity-dx (cl-asciiquarium::creature-entity fish))
                                     (cl-asciiquarium::creature-ttl fish))
                               :to-equal (list x y dx ttl))
                       (expect (creature-style fish) :not :to-equal style)))
            (expect (cl-asciiquarium::creature-%masks dead) :to-be-falsy)
            (expect (cl-asciiquarium::alive-fish-p dead) :to-be-falsy)
            (expect (creature-facing live) :to-be :left))))))

  (it "notifies at first rare insertion and updates discoveries before the HUD"
    (let* ((world (make-world :width 160 :height 24 :fish-count 0))
           (first (make-fish world :species :golden))
           (second (make-fish world :species :golden)))
      (expect (cl-asciiquarium::world-notification world) :to-be-falsy)
      (expect (cl-asciiquarium::world-discovered-species world) :to-be-falsy)
      (cl-asciiquarium::%add-world-creature world first)
      (expect (cl-asciiquarium::world-discovered-species world) :to-equal '(:golden))
      (expect (cl-asciiquarium::world-notification world) :to-equal "Discovered: golden")
      (let ((hud (find :hud (cl-asciiquarium::world-%creatures world)
                       :key #'cl-asciiquarium::creature-kind)))
        (expect (search "dex 1/16" (creature-art hud)) :to-be-truthy)
        (expect (search "Discovered: golden" (creature-art hud)) :to-be-truthy))
      (world-notify world "keep")
      (cl-asciiquarium::%add-world-creature world second)
      (expect (cl-asciiquarium::world-notification world) :to-equal "keep")
      (expect (cl-asciiquarium::world-discovered-species world) :to-equal '(:golden))
      (dolist (entry cl-asciiquarium::+fish-species+)
        (cl-asciiquarium::%add-world-creature
         world (make-fish world :species (cl-asciiquarium::fish-species-entry-name entry))))
      (cl-asciiquarium::world-refresh-hud world)
      (expect (length (cl-asciiquarium::world-discovered-species world)) :to-be 16)
      (let ((hud (find :hud (cl-asciiquarium::world-%creatures world)
                       :key #'cl-asciiquarium::creature-kind)))
        (expect (search "dex 16/16" (creature-art hud)) :to-be-truthy)))))

(describe "fish source data regressions"
  (it-each ((:turtle) (:squid))
      "keeps original ~A rows aligned before mirror padding"
      (name)
    (let* ((art (ecase name
                  (:turtle cl-asciiquarium::+turtle-source-art+)
                  (:squid cl-asciiquarium::+squid-source-art+)))
           (mask (ecase name
                   (:turtle cl-asciiquarium::+turtle-source-mask+)
                   (:squid cl-asciiquarium::+squid-source-mask+)))
           (art-lines (cl-asciiquarium::split-sprite-lines art))
           (mask-lines (cl-asciiquarium::split-sprite-lines mask)))
      (expect (length art-lines) :to-be (length mask-lines))
      (loop for art-row in art-lines for mask-row in mask-lines
            do (expect (length mask-row) :to-be (length art-row)))
      (when (eq name :turtle)
        (expect (second mask-lines) :to-equal " fffffffff"))))
  (it "stores rare probabilities in species data and samples that data"
    (expect (cl-asciiquarium::fish-species-entry-spawn-probability
             (cl-asciiquarium::fish-species :golden)) :to-be 3/100)
    (expect (cl-asciiquarium::fish-species-entry-spawn-probability
             (cl-asciiquarium::fish-species :oarfish)) :to-be 2/100)
    (let* ((entry (cl-asciiquarium::copy-fish-species-entry
                   (cl-asciiquarium::fish-species :dart)))
           (cl-asciiquarium::+fish-species+ (list entry)))
      (setf (cl-asciiquarium::fish-species-entry-name entry) :probe
            (cl-asciiquarium::fish-species-entry-spawn-probability entry) 1)
      (with-seeded-random-state (97)
        (dotimes (birth 100)
          (expect (cl-asciiquarium::random-fish-species) :to-be entry))))))
