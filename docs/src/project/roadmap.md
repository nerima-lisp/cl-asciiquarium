# Roadmap

## What this includes

- 5 original fish species (`:dart`, `:puffer`, `:ribbon`, `:angel`,
  `:guppy`), each multi-line, direction-mirrored art, each with a color
  *palette* rather than one fixed color -- two individuals of the same
  species need not match (`RANDOM-SPECIES-COLOR`, `src/art-fish.lisp`).
- 1 predator: the shark, which removes any fish it overlaps; disable-able for
  the whole run via `--no-shark`, or spawned on demand with the `s` key.
- Rising bubble trails, periodically emitted from fish, removed at the
  waterline.
- Swaying seaweed (a 2-frame loop) and a static castle decoration.
- 4 special guests, spawned on a shared cooldown or on demand with the `g`
  key: a ship that drops an anchor (which removes a fish directly beneath
  it), a decorative line of ducks, a leaping dolphin (a parametric sine-arc
  `Y`, the first non-linear motion in this codebase), and a segmented sea
  monster (a head `CREATURE` plus several trailing `:MONSTER-SEGMENT`
  `CREATURE`s that follow it as a synchronized trail). See
  [Architecture](../reference/architecture.md) for both motion patterns.
- `q`/Ctrl-C to quit, `r` to redraw/reshuffle, space to pause/resume, `+`/`-`
  to grow/shrink the live fish count, `h` to toggle an on-screen help panel,
  and polled terminal-resize handling.
- `--monochrome` to render every creature in the terminal's default
  foreground color.

## What was deliberately cut, and why -- and what has since shipped

Both guests this document previously tracked as deliberate v1 cuts --
dolphins and a sea monster -- are now implemented above, exactly along the
lines this section originally sketched (a parametric arc for the dolphin, a
multi-`CREATURE` synchronized trail for the monster); see "Possible follow-up
work" below for what that looked like before it shipped. Likewise, fish now
vary in color within a species. What remains cut, and why:

- **A general NxN interaction matrix.** The project brief explicitly asked
  for this to be cut; only shark-vs-fish and dropped-anchor-vs-fish are
  checked (`src/collision.lisp`). The dolphin and sea monster stay purely
  decorative, like the duck line, rather than growing a third interaction
  pair apiece.
- **A generic ECS or config-driven guest-definition DSL.** Also explicitly
  out of scope; every creature is a plain `CREATURE` struct built by a plain
  Lisp function.

## Possible follow-up work

- A configurable color theme (a named palette swapped in for every species'
  default colors at once), building on `*MONOCHROME*`'s precedent of a
  dynamically bound rendering-time switch (`src/creature.lisp`).
- A treasure chest or other bottom-of-tank decoration, alongside the castle.
- A crab or other seafloor walker, exercising a third motion pattern (bounded
  horizontal pacing) beyond the dolphin's arc and the sea monster's trail.
