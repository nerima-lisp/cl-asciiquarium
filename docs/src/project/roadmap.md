# Roadmap

## What v1 includes

- 3 original fish species (`:dart`, `:puffer`, `:ribbon`), each multi-line,
  direction-mirrored art.
- 1 predator: the shark, which removes any fish it overlaps.
- Rising bubble trails, periodically emitted from fish, removed at the
  waterline.
- Swaying seaweed (a 2-frame loop) and a static castle decoration.
- 2 special guests: a ship that drops an anchor (which removes a fish
  directly beneath it), and a decorative line of ducks.
- `q` to quit, `r` to redraw/reshuffle, polled terminal-resize handling.

## What was deliberately cut, and why

- **Dolphins and a sea monster.** The project brief asked for at least 2 of
  the 4 classic special guests; a ship-with-anchor and a duck line already
  exercise the same `CREATURE` machinery (a wide horizontal sprite that
  despawns off screen, one of which spawns a second creature mid-flight).
  Adding a jumping-arc dolphin or a sea monster would mean a genuinely
  different motion pattern (a parametric arc rather than constant velocity)
  for marginal additional proof that the `CREATURE` contract scales -- the
  two guests already implemented make that case.
- **A 4th+ fish species.** Three species already exercise every art/behavior
  axis this v1 has (species selection, mirroring, per-species color); a 4th
  would be more of the same data, not new capability.
- **A general NxN interaction matrix.** The project brief explicitly asked
  for this to be cut; only shark-vs-fish and dropped-anchor-vs-fish are
  checked (`src/collision.lisp`).
- **A generic ECS or config-driven guest-definition DSL.** Also explicitly
  out of scope; every creature is a plain `CREATURE` struct built by a plain
  Lisp function.

## Possible follow-up work

- A jumping-arc dolphin school, built on the same `CREATURE` shape with a
  parametric `Y` offset computed from `WORLD-TICK` rather than a constant
  `DY`.
- A sea monster with a longer, segmented body (multiple `CREATURE`s moving
  in a synchronized trail).
- Color variation within a fish species (currently one color per species).
