;;;; src/package.lisp -- the sole DEFPACKAGE form for this repository.
;;;;
;;;; `:use` names only #:cl; sibling packages enter through `:import-from`.
(in-package #:cl-user)

(defpackage #:cl-asciiquarium
  (:use #:cl)
  ;; cl-tty-kit (L1): screens, sprites, entities, the tick loop, raw mode, and
  ;; input decoding. This is the whole rendering/IO substrate; see
  ;; docs/src/reference/architecture.md for how the pieces below compose.
  (:import-from #:cl-tty-kit
                #:make-screen
                #:screen-width
                #:screen-height
                #:screen-clear
                #:sprite-blit
                #:make-style
                #:style-fg
                #:named-color
                #:make-entity
                #:entity-tick
                #:entity-x
                #:entity-y
                #:entity-dx
                #:entity-dy
                #:entity-on-exit
                #:make-renderer
                #:renderer-screen
                #:renderer-width
                #:renderer-height
                #:renderer-render
                #:renderer-resize
                #:tick-loop-run
                #:tick-loop-run-realtime
                #:with-raw-mode
                #:with-terminal-session
                #:terminal-size
                #:make-input-decoder
                #:decode-input-chunk
                #:key-event-type
                #:key-event-code
                #:make-terminal-size-poller
                #:make-stream-input-poller)
  ;; cl-cli (L1): the --width/--height/--seed/--fps command-line surface.
  (:import-from #:cl-cli
                #:make-app
                #:make-option
                #:run-app
                #:option-value
                #:current-process-argv)
  ;; cl-concurrent-kit: fixed executors and promises for bounded render
  ;; preparation work. World mutation and terminal compositing remain local.
  (:import-from #:cl-concurrent-kit
                #:make-executor
                #:submit
                #:await
                #:shutdown-executor
                #:await-executor-termination)
  (:export
   ;; -- Conditions --
   #:asciiquarium-error
   #:asciiquarium-invalid-dimensions
   #:invalid-dimensions-width
   #:invalid-dimensions-height
   #:asciiquarium-unknown-species
   #:unknown-species-name
   #:asciiquarium-invalid-policy
   #:invalid-policy-policy

   ;; -- Geometry / sprite helpers --
   #:mirror-sprite-text
   #:sprite-dimensions
   #:sprite-width
   #:clamp
   #:rects-overlap-p

   ;; -- Creature: the one shape every sprite type goes through --
   #:creature
   #:creature-p
   #:make-creature
   #:creature-frames
   #:creature-facing
   #:creature-style
   #:creature-z
   #:creature-x
   #:creature-y
   #:creature-art
   #:creature-dimensions
   #:creature-tick-animation
   #:creature-bounds
   #:creatures-overlap-p

   ;; -- World state --
   #:world
   #:world-p
   #:make-world
   #:world-width
   #:world-height
   #:world-tick
   #:world-fish-count
   #:world-theme
   #:world-quitp
   #:world-paused-p
   #:world-shark-enabled-p
   #:world-resize
   #:world-redraw
   #:world-cycle-theme
   #:world-toggle-hud
   #:world-increase-fish-count
   #:world-decrease-fish-count
   #:+max-fish-count+
   #:+visual-themes+

   ;; -- Simulation step --
   #:world-advance
   #:apply-collisions
   #:+death-animation-ticks+
   #:+waterline-row+
   #:+anchor-dropped-ticks+

   ;; -- Spawning --
   #:make-fish
   #:make-shark
   #:make-bubble
   #:make-ship
   #:make-duck-line
   #:make-dolphin
   #:make-sea-monster
   #:sea-monster-segments
   #:spawn-shark-now
   #:spawn-guest-now
   #:+dolphin-arc-period+
   #:+sea-monster-segment-count+

   ;; -- Input --
   #:world-apply-key-event
   #:world-apply-key-events
   #:world-toggle-help-overlay

   ;; -- Rendering --
   #:draw-world
   #:render-frame
   #:shutdown-renderer

   ;; -- Application entry points --
   #:run
   #:*app*
   #:main
   #:image-entry-point))
