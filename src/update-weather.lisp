;;;; src/update-weather.lisp -- the per-tick progression of the weather and
;;;; the time of day: weather changes, lightning, the storm's boat sway, and
;;;; the automatic daypart change. ADVANCE-SKY-EVENTS is the one call
;;;; ADVANCE-WORLD-EVENTS (spawn.lisp) makes into this file.
(in-package #:cl-asciiquarium)

(defparameter +weather-order+ '(:clear :rain :storm)
  "The weather cycle; after the last entry it starts again from the first.")

(defparameter +weather-interval-range+ '(500 900)
  "The range each weather's random duration in ticks is drawn from.")

(defparameter +lightning-odds+ 90
  "A storm tick strikes lightning with probability one in this many.")

(defparameter +storm-sway-offsets+ #(0 1 1 0 -1 -1)
  "The rows a boat sits above or below its base row during a storm, one entry
per +STORM-SWAY-STEP-TICKS+ ticks.")

(defparameter +storm-sway-step-ticks+ 6)

(defun world-change-weather (world weather)
  "Switch WORLD to WEATHER now: replace the previous weather's sheet with
WEATHER's (MAKE-WEATHER-SHEET), schedule the next change, and refresh the
status bar, which names the weather."
  (setf (world-weather world) weather
        (world-weather-at world) (+ (world-tick world)
                                    (apply #'random-between +weather-interval-range+)))
  (dolist (creature (world-%creatures world))
    (when (member (creature-kind creature) +weather-sheet-kinds+ :test #'eq)
      (setf (creature-removep creature) t)))
  (let ((sheet (make-weather-sheet world)))
    (when sheet
      (%add-world-creature world sheet)))
  (world-refresh-hud world))

(defun world-advance-weather (world)
  "Move WORLD to the next weather now. Bound to the `w' key."
  (world-change-weather world (next-in-cycle (world-weather world) +weather-order+))
  world)

(defun spawn-flash-now (world x)
  "Add a lightning flash with its bolt at column X, unless WORLD-CALM-P
(--calm). The one place a full-screen flash is created and the one place it
checks --calm; the caller draws X before calling, so --calm never changes
which random numbers are drawn."
  (unless (world-calm-p world)
    (let ((flash (make-flash world x)))
      (when flash
        (%add-world-creature world flash)))))

(defun maybe-strike-lightning (world)
  (when (zerop (random +lightning-odds+))
    (spawn-flash-now world (random (world-width world)))))

(defun storm-sway-offset (world)
  "The rows a boat sits from its base row on WORLD's current tick: 0 outside
a storm. Draws no random number and conses nothing."
  (if (eq (world-weather world) :storm)
      (svref +storm-sway-offsets+
             (mod (floor (world-tick world) +storm-sway-step-ticks+)
                  (length +storm-sway-offsets+)))
      0))

(defun boat-sway-row (world rise)
  "The row a boat floating RISE rows above WORLD's waterline sits on this
tick: its base row, (MAX 0 (- waterline RISE)), plus STORM-SWAY-OFFSET, never
above row 0. The base comes from the current waterline, so it follows a
resize. A creature placed from a boat (a fishing line, its hook) computes the
boat's row with this in its own :TICK, so it does not depend on running after
SWAY-BOATS."
  (max 0 (+ (max 0 (- (world-waterline-row world) rise))
            (storm-sway-offset world))))

(defun sway-boats (world)
  "Put every creature with a :BOAT-RISE data entry (rows above the
waterline) on its BOAT-SWAY-ROW: swaying in a storm, on its base row
otherwise."
  (dolist (creature (world-%creatures world))
    (let ((rise (getf (creature-data creature) :boat-rise)))
      (when rise
        (setf (entity-y (creature-entity creature)) (boat-sway-row world rise))))))

(defun advance-sky-events (world)
  "Run one tick of WORLD's weather and time of day: change the weather when
WORLD-WEATHER-AT is due, strike lightning by chance in a storm, sway the
boats, and move to the next time of day when WORLD-DAYPART-AT (0 under
--no-daycycle) is due."
  (let ((tick (world-tick world)))
    (when (>= tick (world-weather-at world))
      (world-change-weather world (next-in-cycle (world-weather world) +weather-order+)))
    (when (eq (world-weather world) :storm)
      (maybe-strike-lightning world))
    (sway-boats world)
    (let ((due (world-daypart-at world)))
      (when (and (plusp due) (>= tick due))
        (world-advance-daypart world))))
  world)
