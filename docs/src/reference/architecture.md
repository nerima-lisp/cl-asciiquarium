# Architecture

## The single entity/collision contract

A prior architecture review of this project's plan warned that "the biggest
risk is scope creep in the entity/collision model... without an early,
explicit entity-update/collision contract, each new creature risks becoming
bespoke code that doesn't compose." This repository's answer is `CREATURE`
(`src/creature.lisp`): one struct, wrapping a `cl-tty-kit:ENTITY`
(position/velocity/off-bounds callback) with sprite art, an animation frame,
a paint order (`Z`), an optional lifetime (`TTL`), and a kind-specific `DATA`
plist.

Every sprite type in this repository -- the waterline, the castle, seaweed,
each fish species, the shark, bubbles, the ship, its anchor, and the duck
line -- is a `CREATURE`. None of them has its own struct or its own
per-kind update function. `WORLD-ADVANCE` (`src/update.lisp`) ticks every
creature the same way: `ENTITY-TICK`, then `CREATURE-TICK-ANIMATION`, then a
`TTL` countdown, then a small `CASE` on `CREATURE-KIND` for the handful of
kinds with extra per-tick behavior (a fish's bubble timer, a ship's anchor
drop, an anchor's fall-then-settle, a bubble's waterline removal). Collision
(`src/collision.lisp`) is one pass, not a per-pair matrix: only shark-vs-fish
and dropped-anchor-vs-fish are checked, matching the project's interaction
rule that only the shark and a dropped anchor ever remove a fish.

## Off-bounds policy

`MAKE-CREATURE`'s `:POLICY` selects what `ENTITY`'s `:ON-EXIT` callback does:

- `:WRAP` -- reposition the creature fully back inside the world at the edge
  it left (fish, ordinary swimmers).
- `:DESPAWN` -- mark it `REMOVEP`, removed at the end of the current tick
  (the shark, the ship, the duck line -- creatures whose next appearance is
  instead scheduled by a cooldown in `spawn.lisp`).
- `:NONE` -- no callback (static background, and things like bubbles and the
  anchor whose removal condition is not a hard screen edge).

`:WRAP` repositions *fully* inside the bounds, not just off the opposite
edge, deliberately: `cl-tty-kit:ENTITY-TICK` checks whether the *current*
position is out of bounds on every tick, not whether it just crossed the
edge, so landing still outside would re-trigger the callback every following
tick.

## Pure simulation, thin real I/O

Following the split `cl-tty-kit`'s `examples/renderer-loop.lisp` and
`examples/event-loop.lisp` establish: `WORLD-ADVANCE` (`src/update.lisp`) is
a pure state transition -- no I/O, no wall clock -- so
`cl-tty-kit:TICK-LOOP-RUN` can call it a fixed number of times and produce an
exactly reproducible result. Every test in `t/` drives the simulation this
way. `src/app.lisp` is the thin real-I/O side: it polls the terminal size and
stdin once per tick, applies decoded key events, calls `WORLD-ADVANCE`, and
hands the result to `cl-tty-kit:TICK-LOOP-RUN-REALTIME`.

## Randomness

Every random decision (species, lane, speed, spawn cooldowns, which special
guest, bubble timing) goes through `CL:RANDOM` against the ambient
`CL:*RANDOM-STATE*` -- nothing in this repository creates its own generator.
Binding `*RANDOM-STATE*` (via `SB-EXT:SEED-RANDOM-STATE`, as
`t/helpers-world.lisp`'s `SEEDED` does) therefore makes an entire run,
including predator/prey and special-guest spawn timing, exactly reproducible.

## What this v1 included, and what it deliberately cut

Included: 3 fish species, 1 predator (the shark), and 2 special guests (a
ship that drops an anchor, a line of ducks). See
[the roadmap](../project/roadmap.md) for what was cut and why.
