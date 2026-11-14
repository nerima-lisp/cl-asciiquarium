# Roadmap

## Current scope

- Original fish species (`+FISH-SPECIES+`, `src/art-fish-data.lisp`), each
  multi-line, direction-mirrored art, each with color *palettes* rather than
  one fixed color -- two individuals of the same species need not match.
- Three predators: the shark, which hunts the nearest fish ahead and eats with
  its mouth (disable-able for the whole run via `--no-shark`, or spawned on
  demand with the `s` key); a landed anchor, which eats any fish beneath it;
  and the lantern fish, which lures and eats small fish. Eaten fish are
  replaced from the screen edge.
- Schools of six that scatter from threats (`c` spawns one), puffers that
  inflate, and spawning: fish of one species lay eggs that grow into fish.
- Rising bubble trails, periodically emitted from fish, removed at the
  waterline.
- Swaying two-tone seaweed (a 2-frame loop), a castle with lit windows, and
  other seabed ornaments: coral, a rock, a starfish, a vent, and a chest.
- 4 special guests, spawned on a shared cooldown or on demand with the `g`
  key: a ship that drops an anchor (which removes a fish directly beneath
  it), a decorative line of ducks, a leaping dolphin (a parametric sine-arc
  `Y`, the first non-linear motion in this codebase), and a segmented sea
  monster (a head `CREATURE` plus several trailing `:MONSTER-SEGMENT`
  `CREATURE`s that follow it as a synchronized trail). See
  [Architecture](../reference/architecture.md) for both motion patterns.
- Three visual themes (`:abyss`, `:coral`, and `:moonlight`), cycled with `t`,
  plus an ambient current and a status bar on the bottom row toggled with
  `u`.
- `q`/Ctrl-C to quit, `r` to redraw/reshuffle, space to pause/resume, `+`/`-`
  to grow/shrink the live fish count, `h` to toggle an on-screen help panel,
  and polled terminal-resize handling.
- `--color auto|truecolor|256|16|mono` to choose the color depth
  (`--monochrome` is the same as `--color mono`), and `--ascii` to draw only
  ASCII symbols.
- `--theme abyss|coral|moonlight` to select the initial visual theme.

## Out of scope

- A general NxN interaction matrix. Each threat kind declares its interaction
  in a `:THREAT` row (the shark's mouth, a landed anchor, a lantern fish's
  light, and a courting fish), and `src/collision.lisp` checks them in one
  threats × creatures pass; no creature is tested against every other one. The
  dolphin, the sea monster, and the duck line are decorative.
- A generic ECS or config-driven guest-definition DSL. Creatures are plain
  `CREATURE` structs built by plain Lisp functions.

## Renderer

The renderer now combines cached sprite preparation, non-space blit runs, and
cached `Z` ordering with incremental frame rendering:

- mirrored frames reuse prepared sprite data;
- order caches are invalidated when the world changes;
- `RENDER-FRAME` tracks renderer-owned snapshots and redraws only dirty regions
  when that is cheaper than a full repaint;
- cache preparation is bounded and can run in parallel while retaining a serial
  path with equivalent output.

`DRAW-WORLD` remains the simple full-redraw reference path. To inspect the
deterministic update/render path locally, run:

```sh
nix develop --command sbcl --script scripts/benchmark-render.lisp
```

The full gate is `nix flake check`; it covers the test suite, documentation,
formatting, and structural Lisp lint.

## Possible follow-up work

- A crab or other seafloor walker, exercising a third motion pattern (bounded
  horizontal pacing) beyond the dolphin's arc and the sea monster's trail.
