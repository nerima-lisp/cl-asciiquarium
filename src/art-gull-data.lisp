;;;; src/art-gull-data.lisp -- the gull's flap frames, masks, dive threat row,
;;;; and flight tuning. Pure data; art-gull.lisp builds gulls from it and
;;;; update-gull.lisp flies them.
(in-package #:cl-asciiquarium)

(defparameter +gull-frames+ '("\\_v_/" "_/v\\_")
  "Original gull art, wings down then wings up.")

(defparameter +gull-masks+ '("ffbff" "ffbff")
  "Masks for +GULL-FRAMES+: wings in the fin role, the beak in the body role.")

(defparameter +gull-colors+ '(:gull-beak :gull :gull :gull)
  "The (BODY FIN TAIL EYE) color set MASK-ROLE-STYLES gets for a gull.")

(defparameter +gull-beak-column+ 2
  "Column of the beak inside the gull art, the same in both facings.")

(defparameter +gull-threat+ '(:grip :body :effect gull-catch-effect :prey nil :alarm nil)
  "The :THREAT row a gull carries only while it dives: it grabs one fish under
its body and alarms nobody.")

(defparameter +gull-count+ 2
  "How many gulls POPULATE-GULLS keeps in the sky by day.")

(defparameter +gull-min-sky-rows+ 3
  "The fewest sky rows (WORLD-WATERLINE-ROW) a world needs for gulls: the
same threshold below which SKY-SPRITE (art-decor.lisp) draws no sky.")

(defparameter +gull-slots+ '((1/4 :right 0.4f0) (3/4 :left 0.3f0))
  "Fixed start of each gull slot: the fraction of the width it starts at, its
facing, and its cruising speed in columns per tick. Fixed so that building
gulls draws no random number.")

(defparameter +gull-flap-period+ 4
  "Ticks between wing flaps.")

(defparameter +gull-dive-depth+ 6
  "How many rows below the waterline a gull spots fish and dives to.")

(defparameter +gull-dive-odds+ 40
  "A gull above a fish starts a dive with probability 1 in this, per tick.")

(defparameter +gull-dive-cooldown-ticks+ 700
  "Ticks after a catch before the same gull may dive again.")
