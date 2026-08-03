# Architecture

## Data apart from logic: the `-data.lisp` files

`art-fish-data.lisp`, `art-decor-data.lisp`, and `art-guests-data.lisp` hold
nothing but sprite-art strings, color/timing constants, and (for fish) the
small `FISH-SPECIES-ENTRY` table -- no function bodies, no control flow.
`art-fish.lisp`, `art-decor.lisp`, and `art-guests.lisp` hold the factories
that read that data. The split runs one level below the CREATURE contract
below: every sprite's *identity* (what it looks like, what it's called, how
long its cooldown or arc is) is data a designer could hand-edit without
touching a function body, and every sprite's *behavior* (how it's placed,
how it animates) is logic that reads that data by name. `art-shark.lisp` and
`bubble.lisp` stay as one file each -- one art string and one factory apiece
is too little to split without turning "find the shark's art" into two file
opens for no reader benefit.

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
each fish species, the shark, bubbles, the ship, its anchor, the duck line,
the dolphin, and the sea monster's head and body segments -- is a `CREATURE`.
None of them has its own struct or its own per-kind update function.
`WORLD-ADVANCE` (`src/update.lisp`) ticks every creature the same way:
`ENTITY-TICK`, then `CREATURE-TICK-ANIMATION`, then a `TTL` countdown, then a
small `CASE` on `CREATURE-KIND` for the handful of kinds with extra per-tick
behavior (a fish's bubble timer, a ship's anchor drop, an anchor's
fall-then-settle, a bubble's waterline removal, a dolphin's leap arc, a
sea-monster segment following its leader). Collision (`src/collision.lisp`)
is one pass, not a per-pair matrix: only shark-vs-fish and
dropped-anchor-vs-fish are checked, matching the project's interaction rule
that only the shark and a dropped anchor ever remove a fish -- the dolphin
and sea monster, like the duck line before them, are purely decorative.

Two motion patterns beyond simple constant-velocity travel now live inside
this same contract, both still expressed as ordinary `CREATURE`s rather than
as new struct types:

- The **dolphin**'s vertical position is not a constant `DY`: `DOLPHIN-TICK`
  (`src/update.lisp`) recomputes its `Y` every tick from a sine wave around a
  `:BASELINE-Y` stored in its `DATA`, driven by `WORLD-TICK`. `ENTITY-TICK`
  still owns its horizontal `X` via a constant `DX`, so the two axes are
  independent.
- The **sea monster** is several `CREATURE`s -- one head (kind
  `:SEA-MONSTER`) and a handful of trailing `:MONSTER-SEGMENT`s -- moving as
  a synchronized trail. Each segment stores a direct reference to the head
  `CREATURE` struct in its `DATA` and, every tick, repositions itself from
  the head's *current* position plus a fixed offset, rather than carrying its
  own velocity. Because segments are ticked before the head within the same
  `WORLD-ADVANCE` pass (list order is fixed at spawn time: `SPAWN-GUEST-NOW`
  pushes the head first, then each segment, and `PUSH` prepends), a segment
  actually reads the head's position from one tick prior -- a small, constant
  lag that reads as a trailing body rather than a bug. The same reference is
  how a despawning head propagates: a segment marks itself `REMOVEP` once it
  observes the head already `REMOVEP`, one tick after the head itself exits.

Four of those factories -- `MAKE-SHIP`, `MAKE-DUCK-LINE`, `MAKE-DOLPHIN`, and
`MAKE-SEA-MONSTER` (`src/art-guests.lisp`) -- share a further, more specific
shape on top of `CREATURE` itself: each enters `WORLD` fully off-screen on one
edge, crosses it via `OFF-SCREEN-ENTRY`, and despawns past the other, differing
only in art, color, paint order, speed, and how their `Y` and kind-specific
`DATA` are derived. `DEFINE-OFF-SCREEN-GUEST`, a small macro local to
`art-guests.lisp`, factors that shared shape into one place instead of four
near-identical bodies: it generates the `(WORLD &KEY FACING)` `DEFUN`, binding
`WORLD`, `WIDTH`, `HEIGHT`, `ART-WIDTH`, `FACING`, `SPEED`, `X`, and `DX` as
intentional anaphora each guest's declarative `:KIND`/`:ART`/`:COLOR`/`:Z`/
`:SPEED`/`:LET*`/`:Y`/`:DATA` clauses are written against. `MAKE-ANCHOR` and
`MAKE-MONSTER-SEGMENT` stay hand-written functions, since neither enters from
off-screen (an anchor falls from its ship's position; a segment is positioned
from its leader) -- the macro's scope is exactly the shape it was factored
from, not "every guest factory."

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
tick. A diagonal exit (both axes out of bounds the same tick) fires
`:ON-EXIT` once per violated edge, not once per tick, so `WRAP-CREATURE`
dispatches on the `EDGE` argument it is given rather than re-deriving which
axis to fix from position -- the two calls each correctly wrap their own
axis.

`:DESPAWN` has the mirror-image subtlety: `MAKE-SHARK`, `MAKE-SHIP`, and
`MAKE-DUCK-LINE` all spawn fully off-screen (`X` already negative, or
already >= `WORLD-WIDTH`) so the creature visibly enters the screen, but
`ENTITY-TICK`'s off-bounds check does not know that and fires `:ON-EXIT` for
the spawn-side edge on every tick until the creature crosses back on-screen.
`EXIT-EDGE-IN-TRAVEL-DIRECTION-P` (`src/creature.lisp`) guards `:DESPAWN` so
it only removes the creature on the edge its own velocity is carrying it
toward -- the far edge it is *leaving through*, never the near edge it
*entered from*.

## Pure simulation, thin real I/O

Following the split `cl-tty-kit`'s `examples/renderer-loop.lisp` and
`examples/event-loop.lisp` establish: `WORLD-ADVANCE` (`src/update.lisp`) is
a pure state transition -- no I/O, no wall clock -- so
`cl-tty-kit:TICK-LOOP-RUN` can call it a fixed number of times and produce an
exactly reproducible result. Every test in `t/` drives the simulation this
way. `src/app.lisp` is the thin real-I/O side: `MAKE-WORLD-POLLER` composes
`cl-tty-kit:MAKE-TERMINAL-SIZE-POLLER` and `cl-tty-kit:MAKE-STREAM-INPUT-POLLER`
(both new in `cl-tty-kit` 1.4.0) into the terminal-size/stdin poll
`TICK-LOOP-RUN-REALTIME` runs once per tick, ahead of `WORLD-ADVANCE` itself.

This is also where continuation-passing style genuinely belongs in this
codebase, and nowhere else. `RUN` (`src/app.lisp`) does not call the tick
loop's poll/advance/render/quit steps directly; it hands
`TICK-LOOP-RUN-REALTIME` four closures (the poller `MAKE-WORLD-POLLER`
returns, `WORLD-ADVANCE`, `RENDER-FRAME`, `WORLD-QUITP`) and control never
returns to `RUN` until the loop itself decides to quit -- `RUN` is inverted,
and the loop is what drives the continuations forward each tick, polling for
new terminal state before every pure advance. That is CPS, exactly where it
belongs: at the one real effectful boundary, selected because `cl-tty-kit`'s
loop, not this application, owns when the next tick happens. `WORLD-ADVANCE`
and everything it calls stay direct-style on purpose -- rewriting a pure,
already-total state transition into continuation-passing form would add an
indirection with no boundary to justify it, at the direct cost of the
readability this project otherwise prioritizes (see `CODING_STANDARD.md`).

`WORLD-QUITP` is also how `RUN` quits cleanly when nothing inside the tick
loop asked it to. `INSTALL-QUIT-SIGNAL-HANDLER` (`src/app.lisp`) wires
SIGTERM and SIGHUP to `QUIT-ON-SIGNAL`, which just sets `WORLD-QUITP` -- the
same flag the `q` key sets (`src/input.lisp`). An external `kill` or a closed
controlling terminal therefore returns control to `RUN` through the tick
loop's own `STOP` check and an ordinary function return, not a forced signal
exit, so `WITH-TERMINAL-SESSION`'s `UNWIND-PROTECT` still restores the
terminal (exits the alternate screen, shows the cursor, disables raw mode)
before the process ends. Without this, an externally killed run leaves the
terminal in raw/alternate-screen mode until the user manually runs `reset` or
`stty sane`.

## Randomness

Every random decision (species, lane, speed, spawn cooldowns, which special
guest, bubble timing) goes through `CL:RANDOM` against the ambient
`CL:*RANDOM-STATE*` -- nothing in this repository creates its own generator.
Binding `*RANDOM-STATE*` (via `SB-EXT:SEED-RANDOM-STATE`, as
`t/helpers-world.lisp`'s `WITH-SEEDED-RANDOM-STATE` does) therefore makes an entire run,
including predator/prey and special-guest spawn timing, exactly reproducible.

## What this includes, and what remains deliberately cut

Included: 5 fish species (each with a color palette rather than one fixed
color), 1 predator (the shark, disable-able via `--no-shark`), and 4 special
guests (a ship that drops an anchor, a line of ducks, a leaping dolphin, and
a segmented sea monster) -- plus a small set of interactive controls beyond
quit/redraw: pause, a live fish-count dial, on-demand shark/guest spawning,
and a help panel. See [the roadmap](../project/roadmap.md) for what remains
cut and why.
