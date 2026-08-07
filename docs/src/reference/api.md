# API reference

## Application entry points

- `RUN (&key width height fish-count seed interval stream shark-enabled-p
  monochrome-p)` -- run the aquarium in the real terminal until `q`.
  `SHARK-ENABLED-P` and `MONOCHROME-P` back the `--no-shark`/`--monochrome`
  CLI flags.
- `*APP*` -- the `cl-cli` application spec backing the `asciiquarium` binary.
- `MAIN` / `IMAGE-ENTRY-POINT` -- entry points for a script invocation and for
  the delivered executable, respectively; `IMAGE-ENTRY-POINT` delegates to
  `MAIN`.

## World

- `MAKE-WORLD (&key width height fish-count shark-enabled-p)` -- create a
  populated `WORLD`. Signals `ASCIIQUARIUM-INVALID-DIMENSIONS` for a
  non-positive width or height.
- `WORLD-WIDTH`, `WORLD-HEIGHT`, `WORLD-TICK`, `WORLD-CREATURES`,
  `WORLD-FISH-COUNT`, `WORLD-QUITP`, `WORLD-PAUSED-P`, `WORLD-SHARK-ENABLED-P`,
  `WORLD-SHARK-COOLDOWN`, `WORLD-GUEST-COOLDOWN` -- accessors.
  `WORLD-FISH-COUNT` is the count `MAKE-WORLD` was originally given, live
  adjustable via `WORLD-INCREASE-FISH-COUNT`/`WORLD-DECREASE-FISH-COUNT`;
  `WORLD-REDRAW` repopulates that many fish rather than a fixed default.
- `WORLD-RESIZE (world width height)` -- resize in place, clamping any
  creature the new bounds left outside.
- `WORLD-REDRAW (world)` -- remove and repopulate fish/shark/bubbles/guests.
- `WORLD-INCREASE-FISH-COUNT (world)` / `WORLD-DECREASE-FISH-COUNT (world)` --
  grow or shrink `WORLD-FISH-COUNT` by one and spawn/remove a fish to match,
  bound to `+`/`-`. Increasing is capped at `+MAX-FISH-COUNT+`; decreasing is
  capped at zero.
- `WORLD-ADVANCE (world)` -- the one pure per-tick state transition; a no-op
  while `WORLD-PAUSED-P` is true. Suitable as the `ADVANCE` argument to
  `cl-tty-kit:TICK-LOOP-RUN` / `TICK-LOOP-RUN-REALTIME`.

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
- `RECTS-OVERLAP-P (ax ay aw ah bx by bw bh)` -- true when the two
  axis-aligned boxes overlap; touching edges do not count. `CREATURES-OVERLAP-P`
  is the `CREATURE`-level wrapper around it.

## Creature

The one shape every sprite type goes through; see
[Architecture](architecture.md).

- `MAKE-CREATURE (&key world x y dx dy frames frame-period facing style z ttl
  kind data policy)` -- create a `CREATURE`. `POLICY` is one of `:WRAP`
  (reposition inside the world when it exits), `:DESPAWN` (mark for removal),
  or `:NONE` (no off-bounds callback); anything else signals
  `ASCIIQUARIUM-INVALID-POLICY`.
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
  `MAKE-CASTLE`, `MAKE-SHIP`, `MAKE-DUCK-LINE`, `MAKE-DOLPHIN`,
  `MAKE-SEA-MONSTER`, `MAKE-HELP-OVERLAY` -- creature factories, one per kind,
  all returning a plain `CREATURE`. `MAKE-FISH`, `MAKE-SHARK`, `MAKE-SHIP`,
  `MAKE-DUCK-LINE`, `MAKE-DOLPHIN`, and `MAKE-SEA-MONSTER` all accept an
  optional `:FACING` (`:LEFT` or `:RIGHT`), defaulting to a random choice as
  `MAKE-FISH`'s existing `:X`/`:Y`/`:DX` already do; an explicit override is
  what lets a test exercise one crossing direction deterministically.
  `MAKE-FISH` spawns one of five species (`:DART`, `:PUFFER`, `:RIBBON`,
  `:ANGEL`, `:GUPPY`), each with its own color *palette* rather than a single
  fixed color -- two fish of the same species need not match.
  `MAKE-SEA-MONSTER` returns only the head; pair it with...
- `MAKE-MONSTER-SEGMENT (world leader index)` / `SEA-MONSTER-SEGMENTS (world
  leader)` -- build the trailing `:MONSTER-SEGMENT` creatures behind a
  `MAKE-SEA-MONSTER` head, `+SEA-MONSTER-SEGMENT-COUNT+` of them, following
  the head's position every tick rather than carrying independent velocity.
- `MAYBE-SPAWN-SHARK`, `MAYBE-SPAWN-GUEST`, `MAYBE-EMIT-BUBBLE` -- the
  cooldown-driven spawn triggers `WORLD-ADVANCE` calls every tick.
  `MAYBE-SPAWN-SHARK` is a no-op for a `WORLD` with `WORLD-SHARK-ENABLED-P`
  false.
- `SPAWN-SHARK-NOW (world)` / `SPAWN-GUEST-NOW (world kind)` -- the immediate,
  cooldown-independent spawn actions bound to the `s`/`g` keys, also used
  internally by `MAYBE-SPAWN-SHARK`/`MAYBE-SPAWN-GUEST` once their cooldown
  reaches zero. `KIND` is one of `:SHIP`, `:DUCK-LINE`, `:DOLPHIN`, or
  `:SEA-MONSTER` (see `RANDOM-GUEST-KIND`).
- `RANDOM-GUEST-KIND ()` -- `:SHIP`, `:DUCK-LINE`, `:DOLPHIN`, or
  `:SEA-MONSTER` with equal probability.

## Collision

- `APPLY-COLLISIONS (world)` -- the single collision pass: shark-vs-fish and
  dropped-anchor-vs-fish.

## Constants

- `+DEATH-ANIMATION-TICKS+` -- how many ticks a caught fish's death frame
  stays visible before removal.
- `+WATERLINE-ROW+` -- the screen row the waterline sits on; bubbles are
  removed once they rise to this row or above.
- `+MAX-FISH-COUNT+` -- the upper bound `WORLD-INCREASE-FISH-COUNT` clamps to.
- `+DOLPHIN-ARC-AMPLITUDE+` / `+DOLPHIN-ARC-PERIOD+` -- how many rows a
  dolphin's leap carries it above/below its baseline, and how many ticks one
  full leap cycle takes.
- `+SEA-MONSTER-SEGMENT-COUNT+` / `+SEA-MONSTER-SEGMENT-SPACING+` -- how many
  trailing segments a sea monster has, and the column spacing between them.

## Input and rendering

- `WORLD-APPLY-KEY-EVENT (world event)` / `WORLD-APPLY-KEY-EVENTS (world
  events)` -- apply decoded `cl-tty-kit:KEY-EVENT`s: `q`/`Q`/Ctrl-C quit,
  `r`/`R` redraws all aquarium entities (the help overlay is preserved),
  `p`/`P`/Space pauses/resumes, `+`/`=`/`-`/`_` adjust the live fish count,
  `s`/`S` force-spawns a shark, `g`/`G` force-spawns a guest, `h`/`H` toggles
  the help panel.
- `WORLD-TOGGLE-HELP-OVERLAY (world)` -- add or remove the `:HELP-OVERLAY`
  creature (bound to `h`); excluded from `WORLD-REDRAW`, since it is UI state,
  not aquarium population.
- `DRAW-WORLD (screen world)` -- paint every creature onto a `cl-tty-kit:SCREEN`.
- `RENDER-FRAME (renderer world)` -- draw and return the diffed frame output.

## Conditions

Error hierarchy rooted at `ASCIIQUARIUM-ERROR`. See [Conditions](conditions.md)
for slots and signaling sites.

| Condition | Reader accessors |
| --- | --- |
| `ASCIIQUARIUM-ERROR` | -- (the root type) |
| `ASCIIQUARIUM-INVALID-DIMENSIONS` | `INVALID-DIMENSIONS-WIDTH`, `INVALID-DIMENSIONS-HEIGHT` |
| `ASCIIQUARIUM-UNKNOWN-SPECIES` | `UNKNOWN-SPECIES-NAME` |
| `ASCIIQUARIUM-INVALID-POLICY` | `INVALID-POLICY-POLICY` |
