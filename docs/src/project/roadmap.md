# Roadmap

## Current scope

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
- Three visual themes (`:abyss`, `:coral`, and `:moonlight`), cycled with `t`,
  plus an ambient current and an optional HUD toggled with `u`.
- `q`/Ctrl-C to quit, `r` to redraw/reshuffle, space to pause/resume, `+`/`-`
  to grow/shrink the live fish count, `h` to toggle an on-screen help panel,
  and polled terminal-resize handling.
- `--monochrome` to render every creature in the terminal's default
  foreground color.
- `--theme abyss|coral|moonlight` to select the initial visual theme.

## Out of scope

- A general NxN interaction matrix. Only shark-vs-fish and
  dropped-anchor-vs-fish are checked (`src/collision.lisp`); other guests are
  decorative.
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

- A treasure chest or other bottom-of-tank decoration, alongside the castle.
- A crab or other seafloor walker, exercising a third motion pattern (bounded
  horizontal pacing) beyond the dolphin's arc and the sea monster's trail.
