# API reference

## Application entry points

- `RUN (&key width height fish-count seed interval stream shark-enabled-p
  monochrome-p theme)` -- run the aquarium in the real terminal until `q`.
  `SHARK-ENABLED-P` and `MONOCHROME-P` back the `--no-shark`/`--monochrome`
  CLI flags. `THEME` selects the initial palette and accepts one of
  `+VISUAL-THEMES+` -- `:ABYSS`, `:CORAL`, or `:MOONLIGHT`.
- `*APP*` -- the `cl-cli` application spec backing the `asciiquarium` binary.
- `MAIN` / `IMAGE-ENTRY-POINT` -- entry points for a script invocation and for
  the delivered executable, respectively; `IMAGE-ENTRY-POINT` delegates to
  `MAIN`.

## World

- `MAKE-WORLD (&key width height fish-count shark-enabled-p theme
  hud-visible-p)` -- create a populated `WORLD`. `THEME` selects the
  `:ABYSS`, `:CORAL`, or `:MOONLIGHT` palette, and `HUD-VISIBLE-P` controls the
  initial HUD. Signals `ASCIIQUARIUM-INVALID-DIMENSIONS` for a non-positive
  width or height.
- `WORLD-P (object)` -- true when OBJECT is a `WORLD`.
- `WORLD-WIDTH`, `WORLD-HEIGHT`, `WORLD-TICK`,
  `WORLD-FISH-COUNT`, `WORLD-QUITP`, `WORLD-PAUSED-P`, `WORLD-SHARK-ENABLED-P`,
  `WORLD-THEME` -- accessors.
  `WORLD-FISH-COUNT` is the count `MAKE-WORLD` was originally given, live
  adjustable via `WORLD-INCREASE-FISH-COUNT`/`WORLD-DECREASE-FISH-COUNT`;
  `WORLD-REDRAW` repopulates that many fish rather than a fixed default.
  The spawn cooldowns and the HUD-visibility flag are not accessors a consumer
  reads: they are simulation bookkeeping that `WORLD-ADVANCE` and the key
  handlers own.

- `WORLD-RESIZE (world width height)` -- resize in place, clamping any
  creature the new bounds left outside.
- `WORLD-REDRAW (world)` -- remove and repopulate fish/shark/bubbles/guests.
- `WORLD-CYCLE-THEME (world)` -- switch to the next visual theme and rebuild
  the theme-dependent scene decorations.
- `WORLD-TOGGLE-HUD (world)` -- show or hide the HUD creature.
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
  kind data policy %sprite-prototype %trusted-frames-p %trusted-style-p)` --
  create a `CREATURE`. `POLICY` is one of `:WRAP`
  (reposition inside the world when it exits), `:DESPAWN` (mark for removal),
  or `:NONE` (no off-bounds callback); anything else signals
  `ASCIIQUARIUM-INVALID-POLICY`.
  The last three keywords are internal and unsupported. They tell the
  constructor that the caller privately owns the frames and style it is passing,
  which lets the new creature share another creature's prepared sprite caches
  instead of copying them. Nothing enforces this: a keyword argument is a symbol
  in the `KEYWORD` package, so the leading `%` is a naming convention and not a
  package barrier, and any caller can pass `:%TRUSTED-FRAMES-P T` over art it
  does not own. Doing so defeats the cache-ownership invariant and lets one
  creature's mutation show up in another's art. Treat them as private to
  `cl-asciiquarium`: pass `:FRAMES` and `:STYLE` instead, and expect no
  compatibility guarantee for the three.
- `CREATURE-P (object)` -- true when OBJECT is a `CREATURE`.
- `CREATURE-X`, `CREATURE-Y`, `CREATURE-STYLE`, `CREATURE-Z` -- accessors.
  The simulation-internal slots -- kind, data plist, TTL, removal flag, current
  frame index, and the underlying `cl-tty-kit:ENTITY` -- have no public
  accessors. See [Architecture](architecture.md) for the entity model.
- `CREATURE-FRAMES` -- the simple-vector of sprite-art strings backing the
  creature (more than one entry for a looping animation, such as swaying
  seaweed).
- `CREATURE-FACING` -- `:RIGHT` (art drawn as authored) or `:LEFT` (art
  mirrored via `MIRROR-SPRITE-TEXT`).
- `CREATURE-ART (creature)` -- the current frame, mirrored if facing `:LEFT`.
  Whether the result aliases the creature depends on that facing: facing `:LEFT`
  it returns a fresh `COPY-SEQ` of the mirrored frame, while facing `:RIGHT` it
  returns the creature's live frame string itself. Destructively modifying the
  returned string therefore corrupts a right-facing creature's art and leaves a
  left-facing one untouched -- the same call site behaves differently as a fish
  turns around. Copy the result before modifying it.
- `CREATURE-DIMENSIONS (creature)` -- `(VALUES WIDTH HEIGHT)`.
- `CREATURE-TICK-ANIMATION (creature)` -- advance its looping frame.
- `CREATURE-BOUNDS (creature)` / `CREATURES-OVERLAP-P (a b)` -- bounding-box
  collision primitives.

## Spawning

- `MAKE-FISH`, `MAKE-SHARK`, `MAKE-BUBBLE`, `MAKE-SHIP`, `MAKE-DUCK-LINE`,
  `MAKE-DOLPHIN`,
  `MAKE-SEA-MONSTER` -- creature factories,
  all returning a plain `CREATURE`. `MAKE-FISH`, `MAKE-SHARK`, `MAKE-SHIP`,
  `MAKE-DUCK-LINE`, `MAKE-DOLPHIN`, and `MAKE-SEA-MONSTER` all accept an
  optional `:FACING` (`:LEFT` or `:RIGHT`), defaulting to a random choice as
  `MAKE-FISH`'s existing `:X`/`:Y`/`:DX` already do; an explicit override is
  what lets a test exercise one crossing direction deterministically.
  `MAKE-FISH` spawns one of five species (`:DART`, `:PUFFER`, `:RIBBON`,
  `:ANGEL`, `:GUPPY`), each with its own color *palette* rather than a single
  fixed color -- two fish of the same species need not match.
  `MAKE-SEA-MONSTER` returns only the head; pair it with...
- `SEA-MONSTER-SEGMENTS (world leader)` -- build the trailing
  `:MONSTER-SEGMENT` creatures behind a `MAKE-SEA-MONSTER` head,
  `+SEA-MONSTER-SEGMENT-COUNT+` of them, following the head's position every
  tick rather than carrying independent velocity.
- `SPAWN-SHARK-NOW (world)` / `SPAWN-GUEST-NOW (world kind)` -- the immediate,
  cooldown-independent spawn actions bound to the `s`/`g` keys. The same two
  actions are what the internal per-tick cooldown countdown calls when a
  cooldown reaches zero, so a forced spawn and an automatic one produce
  identical creatures. `KIND` is one of `:SHIP`, `:DUCK-LINE`, `:DOLPHIN`, or
  `:SEA-MONSTER`; the automatic path draws among those four with equal
  probability.

## Collision

- `APPLY-COLLISIONS (world)` -- the single collision pass: shark-vs-fish and
  dropped-anchor-vs-fish.

## Constants

- `+VISUAL-THEMES+` -- the visual palettes in cycle order, `(:ABYSS :CORAL
  :MOONLIGHT)`. This is the accepted set for the `THEME` argument of `RUN` and
  `MAKE-WORLD`, and the order `WORLD-CYCLE-THEME` walks, wrapping from the last
  back to the first.
- `+DEATH-ANIMATION-TICKS+` -- how many ticks a caught fish's death frame
  stays visible before removal.
- `+ANCHOR-DROPPED-TICKS+` -- how many ticks a dropped anchor stays in place,
  and interactive, before it is winched back up and despawns. It is the `TTL`
  assigned to the anchor at the moment it drops.
- `+WATERLINE-ROW+` -- the screen row the waterline sits on; bubbles are
  removed once they rise to this row or above.
- `+MAX-FISH-COUNT+` -- the upper bound `WORLD-INCREASE-FISH-COUNT` clamps to.
- `+DOLPHIN-ARC-PERIOD+` -- how many ticks one full dolphin leap cycle takes.
- `+SEA-MONSTER-SEGMENT-COUNT+` -- how many trailing segments a sea monster
  has.

## Input and rendering

- `WORLD-APPLY-KEY-EVENT (world event)` / `WORLD-APPLY-KEY-EVENTS (world
  events)` -- apply decoded `cl-tty-kit:KEY-EVENT`s: `q`/`Q`/Ctrl-C quit,
  `r`/`R` redraw, space pauses/resumes, `+`/`=`/`-`/`_` adjust the live fish
  count, `t`/`T` cycles the theme, `u`/`U` toggles the HUD, `s`/`S`
  force-spawns a shark, `g`/`G` force-spawns a guest, and `h`/`H` toggles the
  help panel.
- `WORLD-TOGGLE-HELP-OVERLAY (world)` -- add or remove the `:HELP-OVERLAY`
  creature (bound to `h`); excluded from `WORLD-REDRAW`, since it is UI state,
  not aquarium population.
- `DRAW-WORLD (screen world)` -- paint every creature onto a `cl-tty-kit:SCREEN`.
- `RENDER-FRAME (renderer world &key stream)` -- draw and return the diffed
  frame output, reusing validated sprite caches and dirty regions where
  possible. When the scene is large enough to be worth splitting, it prepares
  the per-creature sprite snapshots on a pool of worker threads that the
  renderer creates on first use and then keeps.
- `SHUTDOWN-RENDERER (renderer)` -- stop the renderer's worker executor and
  release its frame state. Call it from cleanup such as `UNWIND-PROTECT`; it is
  idempotent and waits for workers to terminate. `RUN` handles its own
  renderer.

## Conditions

Error hierarchy rooted at `ASCIIQUARIUM-ERROR`. See [Conditions](conditions.md)
for slots and signaling sites.

| Condition | Reader accessors |
| --- | --- |
| `ASCIIQUARIUM-ERROR` | -- (the root type) |
| `ASCIIQUARIUM-INVALID-DIMENSIONS` | `INVALID-DIMENSIONS-WIDTH`, `INVALID-DIMENSIONS-HEIGHT` |
| `ASCIIQUARIUM-UNKNOWN-SPECIES` | `UNKNOWN-SPECIES-NAME` |
| `ASCIIQUARIUM-INVALID-POLICY` | `INVALID-POLICY-POLICY` |
