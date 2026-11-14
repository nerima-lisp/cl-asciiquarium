# API reference

## Application entry points

- `RUN (&key width height fish-count seed interval stream shark-enabled-p
  monochrome-p theme color-mode ascii-p)` -- run the aquarium in the real
  terminal until `q`.
  `SHARK-ENABLED-P` and `MONOCHROME-P` back the `--no-shark`/`--monochrome`
  CLI flags. `THEME` selects the initial palette and accepts one of
  `+VISUAL-THEMES+` -- `:ABYSS`, `:CORAL`, or `:MOONLIGHT`. `COLOR-MODE`, one
  of `+COLOR-MODES+`, and `ASCII-P` bind `*COLOR-MODE*` and `*ASCII*` for the
  run. `COLOR-MODE` defaults to `:ANSI16`; only the CLI detects a mode from the
  environment (`--color auto`).
- `*APP*` -- the `cl-cli` application spec backing the `asciiquarium` binary.
- `MAIN` / `IMAGE-ENTRY-POINT` -- entry points for a script invocation and for
  the delivered executable, respectively; `IMAGE-ENTRY-POINT` delegates to
  `MAIN`.

## World

- `MAKE-WORLD (&key width height fish-count shark-enabled-p theme
  hud-visible-p ticks-per-second)` -- create a populated `WORLD`. `THEME`
  selects the `:ABYSS`, `:CORAL`, or `:MOONLIGHT` palette, and `HUD-VISIBLE-P`
  controls the initial status bar. `TICKS-PER-SECOND` (default 20) converts
  `WORLD-NOTIFY`'s four seconds into ticks; `RUN` passes its frame rate. Signals `ASCIIQUARIUM-INVALID-DIMENSIONS` for a non-positive
  width or height.
- `WORLD-P (object)` -- true when OBJECT is a `WORLD`.
- `WORLD-WIDTH`, `WORLD-HEIGHT`, `WORLD-TICK`,
  `WORLD-FISH-COUNT`, `WORLD-QUITP`, `WORLD-PAUSED-P`, `WORLD-SHARK-ENABLED-P`,
  `WORLD-THEME` -- accessors.
  `WORLD-FISH-COUNT` is the count `MAKE-WORLD` was originally given, live
  adjustable via `WORLD-INCREASE-FISH-COUNT`/`WORLD-DECREASE-FISH-COUNT`;
  `WORLD-REDRAW` repopulates that many fish rather than a fixed default.
  The spawn cooldowns and the status-bar visibility flag are not accessors a consumer
  reads: they are simulation bookkeeping that `WORLD-ADVANCE` and the key
  handlers own.

- `WORLD-RESIZE (world width height)` -- resize in place, clamping any
  creature the new bounds left outside, rebuilding the scenery for the new
  size, and moving the status bar to the new bottom row.
- `WORLD-REDRAW (world)` -- remove and repopulate fish/shark/bubbles/guests.
- `WORLD-SET-THEME (world theme)` -- switch to THEME by recoloring every
  creature in place through its kind's registered restyler. No creature is
  removed, added, or moved, and no random number is drawn. A kind with no
  restyler keeps its colors.
- `WORLD-CYCLE-THEME (world)` -- `WORLD-SET-THEME` with the next member of
  `+VISUAL-THEMES+`.
- `REGISTER-CREATURE-RESTYLER (kind function)` -- register FUNCTION, called
  as `(FUNCTION world creature)`, as the restyler for creatures of KIND,
  replacing any restyler already registered for it. The table is global, not
  per `WORLD`.
- `REGISTER-NAMED-COLOR-RESTYLER (kind color)` -- register a restyler that
  repaints creatures of KIND solid in the named 16-color COLOR mapped through
  the new theme, as the shark and every special guest use.
- `WORLD-TOGGLE-HUD (world)` -- show or hide the status bar creature.
- `WORLD-NOTIFY (world message)` -- show the string MESSAGE in place of the
  status bar's key hints for four seconds of ticks (see `MAKE-WORLD`'s
  `TICKS-PER-SECOND`), replacing any notification already showing. The
  countdown runs while paused too.
- `WORLD-WATERLINE-ROW (world)`, `WORLD-STATUS-ROW (world)`,
  `WORLD-SAND-TOP (world)` -- the layout rows for the current height: the
  waterline (`+WATERLINE-ROW+` on screens at least 24 rows tall,
  proportionally less on shorter ones),
  the bottom row the status bar occupies, and the first sand row.
- `WORLD-SWIM-BAND (world)` -- `(VALUES TOP BOTTOM)`, the inclusive rows a
  swimmer's top line may use, below the ripple row and above the sand. Callers
  subtract a sprite's own height from BOTTOM.
- `WORLD-BACKGROUND-CELL (world)` -- the `BACKGROUND-CELL` for the world's
  theme and the effective color mode, cached until either changes.
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
  left-to-right about its full width: each line is padded on the right with
  spaces to the longest line's length, then reversed with its directional
  glyphs swapped, so a creature authored facing right can reuse the same art
  facing left instead of a second hand-drawn copy. Because of the padding, a
  short line keeps its place over the rest of the sprite, and every line of the
  result has the same length.
- `MIRROR-SPRITE-MASK (mask)` -- return multi-line sprite MASK flipped by the
  same pad-then-reverse rule, so it stays aligned with the mirrored art. No
  character is swapped, since a mask character names a color role.
- `CLAMP (value low high)` -- return VALUE clamped to the inclusive range
  `[LOW, HIGH]`.
- `RECTS-OVERLAP-P (ax ay aw ah bx by bw bh)` -- true when the two
  axis-aligned boxes overlap; touching edges do not count. `CREATURES-OVERLAP-P`
  is the `CREATURE`-level wrapper around it.

## Creature

The one shape every sprite type goes through; see
[Architecture](architecture.md).

- `MAKE-CREATURE (&key world x y dx dy frames masks role-styles frame-period
  facing style z ttl kind data policy %sprite-prototype %trusted-frames-p
  %trusted-style-p)` -- create a `CREATURE`. `POLICY` is one of `:WRAP`
  (reposition inside the world when it exits), `:DESPAWN` (mark for removal),
  or `:NONE` (no off-bounds callback); anything else signals
  `ASCIIQUARIUM-INVALID-POLICY`.
  `MASKS`, a string or a list parallel to `FRAMES`, gives each frame a mask of
  exactly its line shape. A non-space mask character selects the cell's style
  from `ROLE-STYLES`, an alist of `(CHARACTER . STYLE)` such as
  `MASK-ROLE-STYLES` returns, and makes the cell opaque even where the art has
  a space; a space in the mask leaves the cell to the art and `STYLE`. A
  mismatched mask, or a mask character with no role style, signals
  `ASCIIQUARIUM-INVALID-MASK`. `ROLE-STYLES` is ignored without `MASKS`.
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

### Colors and symbols

A creature's colors resolve into `cl-tty-kit` styles when the creature or its
sprite prototype is built or restyled, never per frame (`src/palette.lisp`).
A creature already on screen keeps the styles resolved for it until then.

- `+COLOR-MODES+` -- `(:TRUECOLOR :ANSI256 :ANSI16 :MONO)`: a 24-bit color,
  the nearest xterm 256-color index, the nearest of the 16 system colors, or
  no color.
- `*COLOR-MODE*` -- the active member of `+COLOR-MODES+`, default `:ANSI16`.
  `RUN` binds it. `RUN`'s `MONOCHROME-P` overrides it to `:MONO`.
- `DETECT-COLOR-MODE (&key colorterm term no-color)` -- the color mode a
  terminal with those environment values (strings or `NIL`) supports: `:MONO`
  when NO-COLOR is non-empty, `:TRUECOLOR` when COLORTERM is `truecolor` or
  `24bit`, `:ANSI256` when TERM contains `256color`, and `:ANSI16` otherwise.
  It reads no environment itself.
- `RESOLVE-COLOR-MODE (choice &key colorterm term no-color monochrome-p)` --
  the color mode for a `--color` CHOICE string (`auto`, `truecolor`, `256`,
  `16`, or `mono`; `NIL` means `auto`). MONOCHROME-P forces `:MONO`; `auto`
  delegates to `DETECT-COLOR-MODE`, and any other choice wins over NO-COLOR.
  An unknown choice signals `ASCIIQUARIUM-INVALID-ARGUMENT`.
- `RGB-COLOR (designator &optional theme)` -- DESIGNATOR as an `(R G B)` list.
  DESIGNATOR is a `"#rrggbb"` string, an `(R G B)` list, or a role keyword
  looked up in THEME's palette and then in the theme-independent colors. An
  unknown role keyword, or any other value, signals
  `ASCIIQUARIUM-INVALID-ARGUMENT`.
- `COLOR-STYLE (foreground &key theme background bold-p)` -- the style painting
  FOREGROUND, an `RGB-COLOR` designator, over BACKGROUND (default THEME's
  `:BG` role; `NIL` leaves the terminal background) in the effective color
  mode. Returns `NIL` in `:MONO`; `:ANSI16` never paints a background.
- `MASK-ROLE-STYLES (color-set &key theme background extra-roles)` -- the
  `:ROLE-STYLES` alist for a masked sprite. COLOR-SET is a `(BODY FIN TAIL
  EYE)` list of `RGB-COLOR` designators for the mask characters `b`, `f`, `t`,
  and `e`; `s` (stripe) and `l` (light) take fixed colors. EXTRA-ROLES, an
  alist of `(CHARACTER . DESIGNATOR)`, adds or overrides roles.
- `BACKGROUND-CELL (theme)` -- the blank cell every uncovered screen position
  shows under THEME: a space over THEME's `:BG` color in `:TRUECOLOR` and
  `:ANSI256`, or `NIL` (the plain blank cell) in `:ANSI16` and `:MONO`.
- `*ASCII*` -- when true (`--ascii`), every creature frame passes through
  `ASCII-TEXT` as it is stored. `RUN` binds it.
- `ASCII-TEXT (text)` -- TEXT with every non-ASCII symbol the sprites use
  replaced by a one-column ASCII stand-in, or TEXT itself when it has none.
  The column count is kept, so a mask stays aligned with its art.

## Spawning

- `MAKE-FISH`, `MAKE-SHARK`, `MAKE-BUBBLE`, `MAKE-SHIP`, `MAKE-DUCK-LINE`,
  `MAKE-DOLPHIN`,
  `MAKE-SEA-MONSTER` -- creature factories,
  all returning a plain `CREATURE`. `MAKE-FISH`, `MAKE-SHARK`, `MAKE-SHIP`,
  `MAKE-DUCK-LINE`, `MAKE-DOLPHIN`, and `MAKE-SEA-MONSTER` all accept an
  optional `:FACING` (`:LEFT` or `:RIGHT`), defaulting to a random choice as
  `MAKE-FISH`'s existing `:X`/`:Y`/`:DX` already do; an explicit override is
  what lets a test exercise one crossing direction deterministically.
  `MAKE-FISH` spawns one of the species defined in `src/art-fish-data.lisp`, each with its
  own color *palettes* rather than a single fixed color -- two fish of the
  same species need not match.
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

- `APPLY-COLLISIONS (world)` -- the single collision pass: every creature
  carrying a `:THREAT` row (for example the shark, a landed anchor, sonar
  rings, the vent plume, an octopus tentacle) against the live fish.

## Constants

- `+VISUAL-THEMES+` -- the visual palettes in cycle order, `(:ABYSS :CORAL
  :MOONLIGHT)`. This is the accepted set for the `THEME` argument of `RUN` and
  `MAKE-WORLD`, and the order `WORLD-CYCLE-THEME` walks, wrapping from the last
  back to the first.
- `+DEATH-ANIMATION-TICKS+` -- how many ticks a caught fish's death frame
  stays visible before removal.
- `+ANCHOR-REST-TICKS+` -- how many ticks a landed anchor rests on the seabed,
  killing the fish it touches, before it is hauled back up to the surface and
  removed with its chain.
- `+WATERLINE-ROW+` -- the waterline row on a screen at least 24 rows tall;
  the rows above it are sky. Shorter screens put the waterline higher, so read
  the current row from `WORLD-WATERLINE-ROW`. Bubbles are removed once they
  rise to that row or above.
- `+MAX-FISH-COUNT+` -- the upper bound `WORLD-INCREASE-FISH-COUNT` clamps to.
- `+DOLPHIN-ARC-PERIOD+` -- how many ticks one full dolphin leap cycle takes.
- `+SEA-MONSTER-SEGMENT-COUNT+` -- how many trailing segments a sea monster
  has.

## Input and rendering

- `WORLD-APPLY-KEY-EVENT (world event)` / `WORLD-APPLY-KEY-EVENTS (world
  events)` -- apply decoded `cl-tty-kit:KEY-EVENT`s: `q`/`Q`/Ctrl-C quit,
  `r`/`R` redraw, space pauses/resumes, `+`/`=`/`-`/`_` adjust the live fish
  count, `t`/`T` cycles the theme, `u`/`U` toggles the status bar, `s`/`S`
  force-spawns a shark, `g`/`G` force-spawns a guest, `c`/`C` spawns a
  school, `a`/`A` a ship, `m`/`M` a submarine, `d`/`D` a diver, and `h`/`H`
  toggles the help panel.
- `WORLD-TOGGLE-HELP-OVERLAY (world)` -- add or remove the `:HELP-OVERLAY`
  creature (bound to `h`); excluded from `WORLD-REDRAW`, since it is UI state,
  not aquarium population.
- `DRAW-WORLD (screen world)` -- clear a `cl-tty-kit:SCREEN` to
  `WORLD-BACKGROUND-CELL` and paint every creature onto it.
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
| `ASCIIQUARIUM-INVALID-MASK` | `INVALID-MASK-FRAME-INDEX`, `INVALID-MASK-LINE`, `INVALID-MASK-DETAIL` |
| `ASCIIQUARIUM-INVALID-ARGUMENT` | `INVALID-ARGUMENT-VALUE`, `INVALID-ARGUMENT-EXPECTED` |
