# API reference

## Application entry points

- `RUN (&key width height fish-count seed interval stream)` -- run the
  aquarium in the real terminal until `q`.
- `*APP*` -- the `cl-cli` application spec backing the `asciiquarium` binary.
- `MAIN` / `IMAGE-ENTRY-POINT` -- entry points for a script invocation and for
  the delivered executable, respectively (identical bodies).

## World

- `MAKE-WORLD (&key width height fish-count)` -- create a populated `WORLD`.
  Signals `INVALID-DIMENSIONS` for a non-positive width or height.
- `WORLD-WIDTH`, `WORLD-HEIGHT`, `WORLD-TICK`, `WORLD-CREATURES`,
  `WORLD-QUITP`, `WORLD-SHARK-COOLDOWN`, `WORLD-GUEST-COOLDOWN` -- accessors.
- `WORLD-RESIZE (world width height)` -- resize in place, clamping any
  creature the new bounds left outside.
- `WORLD-REDRAW (world)` -- remove and repopulate fish/shark/bubbles/guests.
- `WORLD-ADVANCE (world)` -- the one pure per-tick state transition; suitable
  as the `ADVANCE` argument to `cl-tty-kit:TICK-LOOP-RUN` /
  `TICK-LOOP-RUN-REALTIME`.

## Geometry / sprite helpers

Generic sprite-text operations shared by every creature kind (splitting
sprite text into lines, measuring it, mirroring it left-to-right); nothing
here is aquarium-specific. See [Architecture](architecture.md).

- `SPRITE-DIMENSIONS (text)` -- `(VALUES WIDTH HEIGHT)` for multi-line sprite
  TEXT: HEIGHT is the number of lines, WIDTH the length of the longest one.
- `SPRITE-WIDTH (text)` -- just the WIDTH of `SPRITE-DIMENSIONS`, for the
  common case of an off-screen spawn point that needs only the horizontal
  extent.
- `MIRROR-SPRITE-TEXT (text)` -- return multi-line sprite TEXT flipped
  left-to-right: each line is reversed and its directional glyphs swapped, so
  a creature authored facing right can reuse the same art facing left instead
  of a second hand-drawn copy.
- `CLAMP (value low high)` -- return VALUE clamped to the inclusive range
  `[LOW, HIGH]`.

## Creature

The one shape every sprite type goes through; see
[Architecture](architecture.md).

- `MAKE-CREATURE (&key world x y dx dy frames frame-period facing style z ttl
  kind data policy)` -- create a `CREATURE`. `POLICY` is one of `:WRAP`
  (reposition inside the world when it exits), `:DESPAWN` (mark for removal),
  or `:NONE` (no off-bounds callback).
- `CREATURE-P (object)` -- true when OBJECT is a `CREATURE`.
- `CREATURE-X`, `CREATURE-Y`, `CREATURE-KIND`, `CREATURE-DATA`,
  `CREATURE-TTL`, `CREATURE-REMOVEP`, `CREATURE-STYLE`, `CREATURE-Z` --
  accessors.
- `CREATURE-ENTITY` -- the underlying `cl-tty-kit:ENTITY`, which carries
  position and velocity (and fires an `:ON-EXIT` callback when it leaves the
  world bounds).
- `CREATURE-FRAMES` -- the simple-vector of sprite-art strings backing the
  creature (more than one entry for a looping animation, such as swaying
  seaweed).
- `CREATURE-FRAME-INDEX` -- the index into `CREATURE-FRAMES` of the frame
  currently shown.
- `CREATURE-FACING` -- `:RIGHT` (art drawn as authored) or `:LEFT` (art
  mirrored via `MIRROR-SPRITE-TEXT`).
- `CREATURE-ART (creature)` -- the current frame, mirrored if facing `:LEFT`.
- `CREATURE-DIMENSIONS (creature)` -- `(VALUES WIDTH HEIGHT)`.
- `CREATURE-TICK-ANIMATION (creature)` -- advance its looping frame.
- `CREATURE-BOUNDS (creature)` / `CREATURES-OVERLAP-P (a b)` -- bounding-box
  collision primitives.

## Spawning

- `MAKE-FISH`, `MAKE-SHARK`, `MAKE-BUBBLE`, `MAKE-SEAWEED`, `MAKE-WATERLINE`,
  `MAKE-CASTLE`, `MAKE-SHIP`, `MAKE-DUCK-LINE` -- creature factories, one per
  kind, all returning a plain `CREATURE`.
- `MAYBE-SPAWN-SHARK`, `MAYBE-SPAWN-GUEST`, `MAYBE-EMIT-BUBBLE` -- the
  cooldown-driven spawn triggers `WORLD-ADVANCE` calls every tick.

## Collision

- `APPLY-COLLISIONS (world)` -- the single collision pass: shark-vs-fish and
  dropped-anchor-vs-fish.

## Constants

- `+DEATH-ANIMATION-TICKS+` -- how many ticks a caught fish's death frame
  stays visible before removal.
- `+WATERLINE-ROW+` -- the screen row the waterline sits on; bubbles are
  removed once they rise to this row or above.

## Input and rendering

- `WORLD-APPLY-KEY-EVENT (world event)` / `WORLD-APPLY-KEY-EVENTS (world
  events)` -- apply decoded `cl-tty-kit:KEY-EVENT`s (`q`/`r`).
- `DRAW-WORLD (screen world)` -- paint every creature onto a `cl-tty-kit:SCREEN`.
- `RENDER-FRAME (renderer world)` -- draw and return the diffed frame output.

## Conditions

- `ASCIIQUARIUM-ERROR` -- base condition.
- `INVALID-DIMENSIONS` -- non-positive width/height, readers
  `INVALID-DIMENSIONS-WIDTH` / `-HEIGHT`.
- `UNKNOWN-SPECIES` -- an unrecognized fish species name, reader
  `UNKNOWN-SPECIES-NAME`.
