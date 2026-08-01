;;;; src/package.lisp -- the sole DEFPACKAGE form for this repository.
;;;;
;;;; CODING_STANDARD.md requires `:use` to name only #:cl and every sibling
;;;; package to come in through `:import-from`, so the outsize import lists
;;;; below are the price of that rule, not an oversight.
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
                #:key-event-code)
  ;; cl-cli (L1): the --width/--height/--seed/--fps command-line surface.
  (:import-from #:cl-cli
                #:make-app
                #:make-option
                #:run-app
                #:option-value
                #:current-process-argv)
  (:export
   ;; -- Conditions --
   #:asciiquarium-error
   #:invalid-dimensions
   #:invalid-dimensions-width
   #:invalid-dimensions-height
   #:unknown-species
   #:unknown-species-name

   ;; -- Geometry / sprite helpers --
   #:mirror-sprite-text
   #:sprite-dimensions
   #:sprite-width
   #:clamp

   ;; -- Creature: the one shape every sprite type goes through --
   #:creature
   #:creature-p
   #:make-creature
   #:creature-entity
   #:creature-kind
   #:creature-frames
   #:creature-frame-index
   #:creature-facing
   #:creature-style
   #:creature-z
   #:creature-ttl
   #:creature-removep
   #:creature-data
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
   #:world-creatures
   #:world-quitp
   #:world-shark-cooldown
   #:world-guest-cooldown
   #:world-resize
   #:world-redraw

   ;; -- Simulation step --
   #:world-advance
   #:apply-collisions
   #:+death-animation-ticks+
   #:+waterline-row+

   ;; -- Spawning --
   #:make-fish
   #:make-shark
   #:make-bubble
   #:make-seaweed
   #:make-waterline
   #:make-castle
   #:make-ship
   #:make-duck-line
   #:maybe-spawn-shark
   #:maybe-spawn-guest
   #:maybe-emit-bubble

   ;; -- Input --
   #:world-apply-key-event
   #:world-apply-key-events

   ;; -- Rendering --
   #:draw-world
   #:render-frame

   ;; -- Application entry points --
   #:run
   #:*app*
   #:main
   #:image-entry-point))
