;;;; src/art-guests.lisp -- special guests: a ship that drops an anchor, a
;;;; line of ducks, a leaping dolphin, and a segmented sea monster (see
;;;; docs/src/project/roadmap.md, which tracks these as v1's follow-up work,
;;;; now implemented). Per the interaction rule in the project brief, only the
;;;; ship's anchor is interactive (it can remove a fish directly beneath it);
;;;; every other guest, including the dolphin and sea monster, is purely
;;;; decorative.
(in-package #:cl-asciiquarium)

;;; MAKE-SHIP, MAKE-DUCK-LINE, MAKE-DOLPHIN, and MAKE-SEA-MONSTER (below) are
;;; all an "enter WORLD fully off-screen on one edge, cross it, despawn past
;;; the other" CREATURE, differing only in their art, color, paint order,
;;; speed, and how their Y position and kind-specific :DATA are derived.
;;; DEFINE-OFF-SCREEN-GUEST factors that shared shape into one place instead
;;; of four near-identical bodies; see its own docstring for the anaphora
;;; (WORLD, WIDTH, HEIGHT, ART-WIDTH, FACING, SPEED, X, DX) each guest's
;;; :LET*/:Y/:DATA clauses are written against.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct (off-screen-guest-spec (:constructor %make-off-screen-guest-spec))
    kind art color z speed let-bindings y data)

  (defparameter +off-screen-guest-clauses+ '(:kind :art :color :z :speed :let* :y :data)
    "Every clause keyword DEFINE-OFF-SCREEN-GUEST accepts, in the order its
generated DEFUN evaluates their forms. Data, not logic: the sole reason
%PARSE-OFF-SCREEN-GUEST-CLAUSES and its required-clause check below can be
one short loop over a list instead of one COND arm per clause.")

  (defun %parse-off-screen-guest-clauses (name clauses)
    "Validate and destructure CLAUSES -- the keyword arguments after NAME and
DOCSTRING in a DEFINE-OFF-SCREEN-GUEST form -- into an OFF-SCREEN-GUEST-SPEC,
signalling a macro-expansion-time error naming NAME (rather than a runtime
error somewhere inside the generated DEFUN) when an unrecognized clause
keyword appears or a required one is missing."
    (loop for key in clauses by #'cddr
          unless (member key +off-screen-guest-clauses+)
            do (error "DEFINE-OFF-SCREEN-GUEST ~S: unknown clause ~S; expected one of ~S"
                      name key +off-screen-guest-clauses+))
    (destructuring-bind (&key kind art color z speed let* y (data nil)) clauses
      (dolist (required (list (cons :kind kind) (cons :art art) (cons :color color)
                               (cons :z z) (cons :speed speed) (cons :y y)))
        (unless (cdr required)
          (error "DEFINE-OFF-SCREEN-GUEST ~S: missing required clause ~S"
                 name (car required))))
      (%make-off-screen-guest-spec :kind kind :art art :color color :z z
                                    :speed speed :let-bindings let* :y y :data data)))

  (defun %emit-off-screen-guest (name docstring spec)
    "Build the DEFUN S-expression DEFINE-OFF-SCREEN-GUEST expands to, for NAME
and DOCSTRING and an OFF-SCREEN-GUEST-SPEC already validated by
%PARSE-OFF-SCREEN-GUEST-CLAUSES."
    `(defun ,name (world &key facing)
       ,docstring
       (let* ((width (world-width world))
              (height (world-height world))
              (art-width (sprite-width ,(off-screen-guest-spec-art spec)))
              (facing (or facing (random-facing)))
              (speed ,(off-screen-guest-spec-speed spec)))
         (declare (ignorable height))
         (multiple-value-bind (x dx) (off-screen-entry facing art-width width speed)
           (let* (,@(off-screen-guest-spec-let-bindings spec))
             (make-creature :world world
                             :kind ,(off-screen-guest-spec-kind spec)
                             :%sprite-prototype
                             (%static-sprite-prototype
                              ,(off-screen-guest-spec-kind spec)
                              ,(off-screen-guest-spec-art spec)
                              ,(off-screen-guest-spec-color spec))
                             :facing facing
                             :z ,(off-screen-guest-spec-z spec)
                             :policy :despawn
                             :x x
                             :y ,(off-screen-guest-spec-y spec)
                             :dx dx
                             :data ,(off-screen-guest-spec-data spec))))))))

(defmacro define-off-screen-guest (name docstring &rest clauses)
  "Define MAKE-<NAME>, factory for a CREATURE that enters WORLD fully
off-screen on one edge (per OFF-SCREEN-ENTRY, geometry.lisp), crosses it, and
despawns once it exits fully past the opposite edge -- the shape MAKE-SHIP,
MAKE-DUCK-LINE, MAKE-DOLPHIN, and MAKE-SEA-MONSTER all share. The generated
function always has lambda-list (WORLD &KEY FACING), matching every existing
off-screen guest factory; FACING defaults to a random :LEFT or :RIGHT exactly
as it does when hand-written.

CLAUSES is a keyword plist: :KIND, :ART, :COLOR, and :Z are the creature's
fixed identity (a kind keyword, a sprite-art form, a SOLID-STYLE color
keyword, and paint order); :SPEED is the crossing speed passed to
OFF-SCREEN-ENTRY. :LET*, :Y, and :DATA are forms evaluated, in that order,
in an environment where WORLD, WIDTH, HEIGHT, ART-WIDTH, FACING, SPEED, X,
and DX are all already bound -- these names are this macro's intentional
anaphora, deliberately exposed so a guest's :LET*/:Y/:DATA clauses can
compute a lane, a mid-screen ETA, or kind-specific :DATA state from them
without restating OFF-SCREEN-ENTRY's own call. :LET*, when supplied, is an
ordinary LET* binding list evaluated after X/DX are bound, so its bindings
may reference X or DX (as MAKE-SHIP's ETA-to-midpoint calculation does) and
are themselves visible to the :Y and :DATA forms that follow."
  (%emit-off-screen-guest name docstring (%parse-off-screen-guest-clauses name clauses)))

(define-off-screen-guest make-ship
    "Create a ship CREATURE crossing WORLD at waterline level. Its :DROP-TICK
data entry is the absolute WORLD-TICK at which MAYBE-DROP-ANCHOR (update.lisp)
creates its anchor, computed here so the drop lands near mid-screen regardless
of which edge the ship started from. FACING defaults to a random :LEFT or
:RIGHT; an explicit override is what lets a test exercise one crossing
direction deterministically."
  :kind :ship
  :art +ship-art+
  :color :white
  :z 7
  :speed 0.5f0
  :let* ((distance-to-midpoint (abs (- (/ width 2) x)))
         (travel-to-midpoint (round (/ distance-to-midpoint speed))))
  :y (max 0 (1- +waterline-row+))
  :data (list :drop-tick (+ (world-tick world) travel-to-midpoint)
              :anchor-dropped nil))

(defun make-anchor (world ship)
  "Create an anchor CREATURE falling from SHIP's current position. It falls
(policy :NONE; its descent is stopped explicitly, see ANCHOR-TICK in update.lisp) to a
random :TARGET-DEPTH row, then stops and becomes :DROPPED (active for
COLLISION.LISP) for +ANCHOR-DROPPED-TICKS+ before despawning."
  (let* ((height (world-height world))
         (target-depth (random-between (+ +waterline-row+ 3)
                                        (max (+ +waterline-row+ 4) (- height 3)))))
    (make-creature :world world
                    :kind :anchor
                    :%sprite-prototype
                    (%static-sprite-prototype :anchor +anchor-art+ :bright-black)
                    :z 3
                    :policy :none
                    :x (+ (creature-x ship) (round (/ (sprite-width +ship-art+) 2)))
                    :y +waterline-row+
                    :dx 0 :dy 1
                    :data (list :target-depth target-depth :dropped nil))))

(define-off-screen-guest make-duck-line
    "Create a decorative line-of-ducks CREATURE crossing WORLD near the
waterline. Purely decorative: it never participates in COLLISION.LISP. FACING
defaults to a random :LEFT or :RIGHT; an explicit override is what lets a test
exercise one crossing direction deterministically."
  :kind :duck-line
  :art +duck-line-art+
  :color :yellow
  :z 7
  :speed 0.5f0
  :y (max 0 (1- +waterline-row+))
  :data nil)

(define-off-screen-guest make-dolphin
    "Create a leaping dolphin CREATURE crossing WORLD near the waterline. Unlike
every other crossing guest, its vertical position is not a constant DY: each
tick DOLPHIN-TICK (update.lisp) recomputes Y from a sine wave around its
:BASELINE-Y, driven by WORLD-TICK -- the roadmap's suggested 'parametric Y
offset' motion, the first creature in this codebase whose path is not simple
linear travel. FACING defaults to a random :LEFT or :RIGHT, as with every
other off-screen crossing factory."
  :kind :dolphin
  :art +dolphin-art+
  :color :bright-blue
  :z 7
  :speed 1.0f0
  :let* ((baseline (random-between (+ +waterline-row+ 1 +dolphin-arc-amplitude+)
                                    (max (+ +waterline-row+ 2 +dolphin-arc-amplitude+)
                                         (- height 4)))))
  :y baseline
  :data (list :start-tick (world-tick world)
              :baseline-y baseline
              :amplitude +dolphin-arc-amplitude+
              :period +dolphin-arc-period+))

(define-off-screen-guest make-sea-monster
    "Create the head CREATURE (kind :SEA-MONSTER) of a segmented sea monster
crossing WORLD near the waterline -- the roadmap's suggested 'longer,
segmented body (multiple CREATUREs moving in a synchronized trail)'. Returns
only the head; SEA-MONSTER-SEGMENTS below builds the trailing body from it,
since a single CREATURE return value cannot carry a whole trail the way every
other guest factory's single return value is enough on its own. FACING
defaults to a random :LEFT or :RIGHT."
  :kind :sea-monster
  :art +sea-monster-head-art+
  :color :bright-green
  :z 7
  :speed 0.5f0
  :let* ((lane (random-between (1+ +waterline-row+) (max (+ 2 +waterline-row+) (- height 4)))))
  :y lane
  :data nil)

(defun make-monster-segment (world leader index)
  "Create one :MONSTER-SEGMENT CREATURE trailing LEADER (a CREATURE returned
by MAKE-SEA-MONSTER) by INDEX segment-widths, on whichever side is behind
LEADER's direction of travel. Its own velocity is zero and its policy :NONE:
MONSTER-SEGMENT-TICK (update.lisp) repositions it from LEADER's current
position every tick instead, so the whole body moves as one synchronized
trail rather than each segment separately simulating its own off-screen exit."
  (let* ((behind (if (eq (creature-facing leader) :right) -1 1))
         (offset-x (* behind +sea-monster-segment-spacing+ index)))
    (make-creature :world world
                    :kind :monster-segment
                    :%sprite-prototype
                    (%static-sprite-prototype :monster-segment
                                               +sea-monster-segment-art+
                                               :green)
                    :z 6
                    :policy :none
                    :x (+ (creature-x leader) offset-x)
                    :y (creature-y leader)
                    :dx 0 :dy 0
                    :data (list :leader leader :offset-x offset-x :phase (* index 0.8)))))

(defun sea-monster-segments (world leader)
  "Return a fresh list of +SEA-MONSTER-SEGMENT-COUNT+ :MONSTER-SEGMENT
CREATUREs trailing LEADER, indices 1 through +SEA-MONSTER-SEGMENT-COUNT+."
  (loop for index from 1 to +sea-monster-segment-count+
        collect (make-monster-segment world leader index)))
