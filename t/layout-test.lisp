;;;; t/layout-test.lisp -- the P1 screen layout, status bar, help panel,
;;;; color modes, and in-place theme changes.
(in-package #:cl-asciiquarium/test)

(defun %kind-creature (world kind)
  (find kind (cl-asciiquarium::world-%creatures world) :key #'cl-asciiquarium::creature-kind))

(defun %drawn-rows (world)
  (let ((screen (make-screen (world-width world) (world-height world))))
    (draw-world screen world)
    (loop for row below (world-height world)
          collect (cl-tty-kit:screen-row-string screen row))))

(describe "screen layout"
  (it-each ((1) (3) (10) (24) (34))
      "builds and draws without error, the status bar on the bottom row, at height ~A"
      (height)
    (let ((world (make-world :width 60 :height height :fish-count 3)))
      (expect (length (%drawn-rows world)) :to-be height)
      (expect (creature-y (%kind-creature world :hud)) :to-be (1- height))))
  (it "puts the waterline on row 5 from 24 rows up and scales it down below that"
    (expect (cl-asciiquarium::layout-waterline-row 34) :to-be 5)
    (expect (cl-asciiquarium::layout-waterline-row 24) :to-be 5)
    (expect (cl-asciiquarium::layout-waterline-row 10) :to-be 2))
  (it "lays a 24-row screen out as sky, waterline, ripple, water, seabed, three sand rows, status bar"
    (let ((world (make-world :width 80 :height 24 :fish-count 0)))
      (expect (creature-y (%kind-creature world :waterline)) :to-be 5)
      (expect (creature-y (%kind-creature world :ripple)) :to-be 6)
      (expect (creature-y (%kind-creature world :sand)) :to-be 20)
      (expect (nth-value 1 (creature-dimensions (%kind-creature world :sand))) :to-be 3)
      (expect (multiple-value-list (world-swim-band world)) :to-equal '(7 19))
      (expect (%kind-creature world :sky) :to-be-truthy)))
  (it "keeps the chest, rock, and vent as separate kinds standing on the sand"
    (let ((world (make-world :width 100 :height 30 :fish-count 0)))
      (dolist (kind '(:chest :rock :vent))
        (let ((creature (%kind-creature world kind)))
          (expect creature :to-be-truthy)
          (expect (+ (creature-y creature) (nth-value 1 (creature-dimensions creature)))
                  :to-be (world-sand-top world))))))
  (it "keeps every seabed ornament off the seaweed columns"
    (let* ((world (make-world :width 100 :height 30 :fish-count 0))
           (columns (cl-asciiquarium::seaweed-columns world)))
      (dolist (kind '(:coral :rock :starfish :vent :chest))
        (let ((creature (%kind-creature world kind)))
          (multiple-value-bind (x y width) (creature-bounds creature)
            (declare (ignore y))
            (expect (notany (lambda (column) (<= x column (+ x width -1))) columns)
                    :to-be-truthy)))))))

(describe "status bar"
  (it "shows the theme, time of day, fish count, discoveries, and the swimming state"
    (let* ((world (make-world :width 120 :height 24 :fish-count 0 :theme :abyss))
           (art (creature-art (%kind-creature world :hud))))
      (expect (length art) :to-be 120)
      (dolist (text '("ABYSS" "dusk" "fish 0" "dex 0/" "swimming" "q quit"))
        (expect (search text art) :to-be-truthy))))
  (it "drops the key hints, then the least important summary groups, on a narrow screen"
    (let* ((world (make-world :width 30 :height 24 :fish-count 0))
           (art (creature-art (%kind-creature world :hud))))
      (expect (length art) :to-be 30)
      (expect (search "ABYSS" art) :to-be-truthy)
      (expect (search "swimming" art) :to-be-truthy)
      (expect (search "dusk" art) :to-be-falsy)
      (expect (search "quit" art) :to-be-falsy)))
  (it "replaces the key hints with a notification for four seconds of ticks"
    (let ((world (make-world :width 100 :height 24 :fish-count 0 :ticks-per-second 5)))
      (world-notify world "the shark left full")
      (expect (search "the shark left full" (creature-art (%kind-creature world :hud))) :to-be-truthy)
      (expect (search "quit" (creature-art (%kind-creature world :hud))) :to-be-falsy)
      (dotimes (tick 19) (world-advance world))
      (expect (search "the shark left full" (creature-art (%kind-creature world :hud))) :to-be-truthy)
      (world-advance world)
      (expect (search "the shark left full" (creature-art (%kind-creature world :hud))) :to-be-falsy)
      (expect (search "quit" (creature-art (%kind-creature world :hud))) :to-be-truthy)))
  (it "counts a notification down while paused too"
    (let ((world (make-world :width 100 :height 24 :fish-count 0 :ticks-per-second 1)))
      (setf (world-paused-p world) t)
      (world-notify world "saved")
      (dotimes (tick 4) (world-advance world))
      (expect (cl-asciiquarium::world-notification world) :to-be-null)))
  (it "records each species as it is seen"
    (with-seeded-random-state (3)
      (let ((world (make-world :width 80 :height 24 :fish-count 0)))
        (cl-asciiquarium::%add-world-creature world (make-fish world :species :dart))
        (cl-asciiquarium::%add-world-creature world (make-fish world :species :dart))
        (cl-asciiquarium::%add-world-creature world (make-fish world :species :guppy))
        (expect (length (cl-asciiquarium::world-discovered-species world)) :to-be 2)))))

(describe "help panel"
  (it "draws a rounded box that lists every bound key"
    (let* ((world (make-world :width 80 :height 30 :fish-count 0))
           (help (progn (world-toggle-help-overlay world) (%kind-creature world :help-overlay)))
           (lines (cl-asciiquarium::split-sprite-lines (creature-art help))))
      (expect (char (first lines) 0) :to-equal #\╭)
      (expect (search "controls" (first lines)) :to-be-truthy)
      (expect (char (car (last lines)) 0) :to-equal #\╰)
      (dolist (label '("quit" "redraw" "pause" "fish count" "spawn shark" "spawn guest"
                       "cycle theme" "status bar" "this help"))
        (expect (some (lambda (line) (search label line)) lines) :to-be-truthy))
      (expect (length (remove-duplicates (mapcar #'length lines))) :to-be 1)))
  (it "is opaque: a creature behind its interior does not show through"
    (let* ((world (make-world :width 80 :height 30 :fish-count 0 :hud-visible-p nil))
           (marker (make-creature :world world :kind :marker :frames "M" :x 4 :y 8 :z 50)))
      (cl-asciiquarium::%add-world-creature world marker)
      (world-toggle-help-overlay world)
      (expect (search "M" (nth 8 (%drawn-rows world))) :to-be-falsy))))

(describe "color modes"
  (it-each ((:mono (:no-color "1" :colorterm "truecolor"))
            (:truecolor (:colorterm "truecolor" :term "xterm"))
            (:truecolor (:colorterm "24BIT"))
            (:ansi256 (:term "xterm-256color"))
            (:ansi16 (:term "xterm"))
            (:ansi16 (:no-color "" :term "vt100"))
            (:ansi16 ()))
      "detects ~A from the environment"
      (expected environment)
    (expect (apply #'detect-color-mode environment) :to-be expected))
  (it "resolves explicit --color choices, letting them win over NO_COLOR, and --monochrome forces mono"
    (expect (resolve-color-mode "256" :no-color "1") :to-be :ansi256)
    (expect (resolve-color-mode "truecolor") :to-be :truecolor)
    (expect (resolve-color-mode "16" :colorterm "truecolor") :to-be :ansi16)
    (expect (resolve-color-mode "mono") :to-be :mono)
    (expect (resolve-color-mode nil :term "xterm-256color") :to-be :ansi256)
    (expect (resolve-color-mode "auto" :colorterm "truecolor" :monochrome-p t) :to-be :mono)
    (expect (lambda () (resolve-color-mode "bogus")) :to-throw 'asciiquarium-invalid-argument))
  (it "paints the water background only in the RGB modes"
    (let ((*color-mode* :truecolor))
      (expect (cl-tty-kit:cell-style (background-cell :coral))
              :to-equal (make-style (cl-tty-kit:style-bg 14 38 41))))
    (let ((*color-mode* :ansi16))
      (expect (background-cell :coral) :to-be-null)))
  (it "fills a masked space with its role color when the role paints a background"
    (let* ((role (cons #\b (make-style (style-fg 1 2 3) (cl-tty-kit:style-bg 9 9 9))))
           (creature (make-creature :kind :test-thing :frames "a a" :masks "bbb"
                                    :role-styles (list role) :x 0 :y 0))
           (screen (make-screen 3 1)))
      (cl-asciiquarium::creature-blit screen creature)
      (expect (cl-tty-kit:cell-style (screen-cell screen 1 0))
              :to-equal (make-style (cl-tty-kit:style-bg 1 2 3)))
      (expect (cl-tty-kit:cell-style (screen-cell screen 0 0)) :to-equal (cdr role))))
  (it "draws no character outside ASCII under --ascii"
    (let* ((cl-asciiquarium::*ascii* t)
           (world (make-world :width 80 :height 30 :fish-count 0 :theme :moonlight)))
      (world-toggle-help-overlay world)
      (dolist (row (%drawn-rows world))
        (expect (every (lambda (character) (< (char-code character) 128)) row) :to-be-truthy)))))

(describe "theme changes"
  (it "recolors in place: every creature survives, unmoved, and no random number is drawn"
    (with-seeded-random-state (11)
      (let* ((world (make-world :width 80 :height 24 :fish-count 5))
             (before (copy-list (cl-asciiquarium::world-%creatures world)))
             (positions (mapcar (lambda (creature) (list (creature-x creature) (creature-y creature)))
                                before))
             (state (make-random-state *random-state*)))
        (world-cycle-theme world)
        (expect (world-theme world) :to-be :coral)
        (expect (cl-asciiquarium::world-%creatures world) :to-equal before)
        (expect (mapcar (lambda (creature) (list (creature-x creature) (creature-y creature)))
                        (cl-asciiquarium::world-%creatures world))
                :to-equal positions)
        (expect (random 1000000) :to-be (random 1000000 state)))))
  (it "recolors the background decorations for the new theme"
    (let* ((*color-mode* :truecolor)
           (world (make-world :width 80 :height 24 :fish-count 0 :theme :abyss))
           (castle (%kind-creature world :castle))
           (before (cl-asciiquarium::creature-%role-styles castle)))
      (world-set-theme world :coral)
      (expect (cl-asciiquarium::creature-%role-styles castle) :not :to-equal before)
      (expect (cdr (assoc #\c (cl-asciiquarium::creature-%role-styles castle)))
              :to-equal (color-style :castle :theme :coral))))
  (it "repaints the whole screen once when the background changes"
    (let* ((*color-mode* :truecolor)
           (world (make-world :width 40 :height 12 :fish-count 0 :theme :abyss))
           (renderer (make-renderer 40 12 :initial-cell (world-background-cell world))))
      (unwind-protect
           (progn
             (render-frame renderer world)
             (world-set-theme world :coral)
             (render-frame renderer world)
             ;; No cell may keep the abyss water color (8 21 33) once the
             ;; theme is coral: the open water is repainted, not only the
             ;; creatures whose runs changed.
             (let ((screen (cl-tty-kit:renderer-screen renderer))
                   (abyss-water (cl-tty-kit:style-bg 8 21 33)))
               (expect (loop for y below 12
                             never (loop for x below 40
                                         thereis (member abyss-water
                                                         (cl-tty-kit:cell-style
                                                          (cl-tty-kit:screen-cell screen x y))
                                                         :test #'equal)))
                       :to-be-truthy)
               (expect (member (cl-tty-kit:style-bg 14 38 41)
                               (cl-tty-kit:cell-style (cl-tty-kit:screen-cell screen 0 4))
                               :test (function equal))
                       :to-be-truthy)))
        (shutdown-renderer renderer)))))

(defun %old-theme-only-colors (old new)
  "RGB triples that OLD's palette uses and neither NEW's palette nor the fixed
colors do, so finding one in a creature after a switch to NEW proves the
creature kept OLD's colors."
  (let ((palette (lambda (theme)
                   (loop for (nil rgb) on (cdr (assoc theme cl-asciiquarium::+theme-rgb-palettes+))
                           by #'cddr
                         collect rgb)))
        (fixed (loop for (nil rgb) on cl-asciiquarium::+fixed-rgb-colors+ by #'cddr collect rgb)))
    (set-difference (funcall palette old)
                    (append (funcall palette new) fixed)
                    :test #'equal)))

(defun %creature-run-colors (creature)
  "Every (R G B) color in the cells of CREATURE's prepared runs, both facings."
  (let ((colors '()))
    (dolist (frames (list (cl-asciiquarium::creature-%frame-runs creature)
                          (cl-asciiquarium::creature-%mirrored-frame-runs creature)))
      (loop for runs across frames
            do (loop for offset from 2 below (length runs) by 3
                     for source = (svref runs offset)
                     do (dotimes (x (cl-tty-kit:screen-width source))
                          (dolist (item (cl-tty-kit:cell-style (screen-cell source x 0)))
                            (when (and (consp item) (= (length item) 4))
                              (pushnew (rest item) colors :test #'equal)))))))
    colors))

(describe "theme changes recolor every creature but the fish"
  (it "leaves no creature but a fish with a color only the previous theme uses"
    (with-seeded-random-state (5)
      (let* ((*color-mode* :truecolor)
             (world (make-world :width 120 :height 30 :fish-count 1 :theme :abyss))
             (fish (%kind-creature world :fish)))
        (spawn-shark-now world)
        (dolist (kind '(:ship :duck-line :dolphin :sea-monster))
          (spawn-guest-now world kind))
        (cl-asciiquarium::%add-world-creature
         world (cl-asciiquarium::make-anchor world (%kind-creature world :ship)))
        (cl-asciiquarium::%add-world-creature world (make-bubble world fish))
        (world-toggle-help-overlay world)
        (let* ((old-colors (%old-theme-only-colors :abyss :coral))
               (checked (remove :fish (cl-asciiquarium::world-%creatures world)
                                :key #'cl-asciiquarium::creature-kind))
               (kinds (remove-duplicates (mapcar #'cl-asciiquarium::creature-kind checked))))
          ;; The kinds this test must reach, so a kind that stops being built
          ;; (or a new one nobody listed) fails here instead of going unchecked.
          (expect (sort (copy-list kinds) #'string<)
                  :to-equal (sort (list :ambient-current :waterline :ripple :sky :sand :castle
                                        :seaweed :coral :rock :starfish :vent :chest :hud
                                        :help-overlay :shark :bubble :ship :anchor :duck-line
                                        :dolphin :sea-monster :monster-segment)
                                  #'string<))
          ;; Precondition: before the switch every kind shows an abyss-only
          ;; color, so the assertion below cannot pass vacuously.
          (dolist (creature checked)
            (expect (intersection (%creature-run-colors creature) old-colors :test #'equal)
                    :to-be-truthy))
          (world-set-theme world :coral)
          (dolist (creature checked)
            (expect (list (cl-asciiquarium::creature-kind creature)
                          (intersection (%creature-run-colors creature) old-colors :test #'equal))
                    :to-equal (list (cl-asciiquarium::creature-kind creature) nil))))))))
