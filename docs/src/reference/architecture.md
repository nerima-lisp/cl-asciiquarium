# Architecture

## Data apart from logic: the `-data.lisp` files

The `art-*-data.lisp` files hold sprite strings, color and timing constants,
threat rows, and the fish species table; matching `art-*.lisp` files hold the
creature factories, while `update-*.lisp` files hold per-tick behaviour. The
food feature follows that split in `art-food-data.lisp`, `art-food.lisp`, and
`update-food.lisp`. `bubble-data.lisp` holds bubble art and immutable sprite
prototypes selected by `bubble.lisp`. The fish dex and screen snapshots use
application-side file I/O in `app-zukan.lisp` and `app-snapshot.lisp`, outside
the world simulation.

## The single entity/collision contract

`CREATURE` (`src/creature.lisp`) is the entity/collision contract: one struct,
wrapping a `cl-tty-kit:ENTITY`
(position/velocity/off-bounds callback) with sprite art, an animation frame,
a paint order (`Z`), an optional lifetime (`TTL`), and a kind-specific `DATA`
plist.

Background pieces, UI panels, food grains, fish, predators, visitors, and
seabed residents are all `CREATURE`s. None has its own struct.
`WORLD-ADVANCE` (`src/update.lisp`) ticks every creature the same way:
`ENTITY-TICK`, then `CREATURE-TICK-ANIMATION`, then a `TTL` countdown. A
creature with extra per-tick behaviour (a fish's bubble timer, a food grain's
lure, a gull's dive, the fisher's line and hook, a ship's anchor drop, an
anchor's fall, rest on the seabed, and rise, a submarine's sonar timer, the
chest's opening schedule, the dinghy's dive phases, the crab's turn at an edge,
the octopus's reach and ink, a bubble's waterline removal, a dolphin's leap
arc, a sea-monster segment following its leader, the shark steering toward the
nearest fish ahead) carries a `:TICK` function in its `:DATA` plist, set by the
factory that builds it, and `TICK-CREATURE` calls it last. The anchor and
its chain, which hang from the ship, and the fisher's line and hook, which
hang from the boat, also carry a `:PLACE` function that puts them back where
they belong. Their `:TICK` calls it (for the line and hook, it is the
`:TICK` itself), and `WORLD-RESIZE` calls
it for every creature that has one, so a paused world shows them in place at
the new size. The calls follow creature-list order, so a `:PLACE` that reads
another creature's position (the chain reads the anchor's) needs that creature
earlier in the list.

Collision (`src/collision.lisp`) is one pass, not a per-pair matrix. A
creature is a threat when its `:DATA` plist carries a `:THREAT` row. The row
declares where the threat grips (its whole body or its leading N columns), the
function applied to a fish it grips, which species it may take, and whether
creatures carrying a `:SENSE` entry react when it comes within their range.
Today the threats are the shark's mouth, a landed anchor, a lantern fish's
light (its leading column, small species only), one courting fish at a time,
food grains, the fisher's hook, a diving gull's beak (one fish per dive), the
submarine (it only alarms), its sonar rings (they stun), the vent's plume (it
lifts fish), and an octopus tentacle's tip.
The pass loops over active threats and, for each, over every creature once, so
its cost is threats × creatures. Food is capped at 18 grains. The pass returns at once
while the world has held no threat since its creature list was last recounted.
A vent always holds the plume's threat row; screens without one can still have
threats from the shark, food, and other creatures. Fish do interact with fish,
but only through threats. A lantern fish picks the nearest small fish in range
as its lure target on its own tick and eats it with its leading column. For
spawning, one courting fish at a time becomes a temporary threat whose whole
body is its grip.

Three motion patterns beyond simple constant-velocity travel now live inside
this same contract, all still expressed as ordinary `CREATURE`s rather than
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
- The **crab** walks along the seabed at a constant horizontal speed and
  reverses that speed when it reaches either screen edge (`CRAB-TICK` in
  `src/update-vent.lisp`).

A creature leaves the world by being marked `REMOVEP`;
`%FLUSH-REMOVED-CREATURES` deletes marked creatures at the end of each
`WORLD-ADVANCE` call, even while paused. Two functions mark by kind and then
flush at once: `WORLD-REDRAW` marks every kind in `+TRANSIENT-CREATURE-KINDS+`,
and `WORLD-RESIZE` marks every kind in `+BACKGROUND-CREATURE-KINDS+` and
rebuilds the background. Two more take UI creatures, which have no children,
straight out of the list so that a key pressed while paused shows at once:
`WORLD-TOGGLE-HUD` removes the status bar, and `WORLD-TOGGLE-OVERLAY` (the `h`
and `z` keys) removes the help and dex panels.

Some creatures belong to another one and must leave with it: a lantern fish's
night glow, the `!` over a stunned fish, the octopus's tentacle and ink cloud,
and a caught fish. The code that creates the first four adds them with
`ATTACH-CREATURE` (`src/world.lisp`), which records the child in its owner's
`:ATTACHED` data entry. A caught fish is already in the world, so
`CATCH-EFFECT` records it on its captor with `ATTACH-EXISTING-CREATURE`.
`RELEASE-ATTACHED` marks an owner's children `REMOVEP`, and their children in
turn, so a fish held by a tentacle leaves with the octopus.
`%FLUSH-REMOVED-CREATURES` calls `RELEASE-ATTACHED` on every marked creature
before deleting any, so whatever marked an owner (a TTL, an exit, its own tick,
a key, a resize), its children leave in the same flush. A fish also releases
its children as soon as it stops (`FISH-STOP-BEHAVIOUR`: eaten, caught, the
`-` key, or a school leaving the screen), because an eaten fish stays on screen
for its death animation while its children must go. The tentacle and the ink
are transient kinds, so a redraw clears them while the octopus stays; the
octopus finds them `REMOVEP`, peeks again, and forgets them.

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
  (the shark, ship, submarine, diver's dinghy, fisher, duck line, dolphin,
  and sea monster; their next automatic appearance is scheduled by a cooldown
  in `spawn.lisp`).
- `:NONE` -- no callback (the background scenery, the status bar, and things
  like bubbles and the anchor whose removal condition is not a hard screen
  edge).

`:WRAP` repositions *fully* inside the bounds, not just off the opposite
edge, deliberately: `cl-tty-kit:ENTITY-TICK` checks whether the *current*
position is out of bounds on every tick, not whether it just crossed the
edge, so landing still outside would re-trigger the callback every following
tick. A diagonal exit (both axes out of bounds the same tick) fires
`:ON-EXIT` once per violated edge, not once per tick, so `WRAP-CREATURE`
dispatches on the `EDGE` argument it is given rather than re-deriving which
axis to fix from position -- the two calls each correctly wrap their own
axis.

`:DESPAWN` has the mirror-image subtlety: `MAKE-SHARK`, `MAKE-SHIP`,
`MAKE-DUCK-LINE`, `MAKE-DOLPHIN`, `MAKE-SEA-MONSTER`, `MAKE-SUBMARINE`,
`SPAWN-DIVER-NOW`, and `MAKE-FISHER` spawn fully off-screen (`X` already
negative, or already >= `WORLD-WIDTH`) so the creature visibly enters the screen, but
`ENTITY-TICK`'s off-bounds check does not know that and fires `:ON-EXIT` for
the spawn-side edge on every tick until the creature crosses back on-screen.
`EXIT-EDGE-IN-TRAVEL-DIRECTION-P` (`src/creature.lisp`) guards `:DESPAWN` so
it only removes the creature on the edge its own velocity is carrying it
toward -- the far edge it is *leaving through*, never the near edge it
*entered from*.

## Theme, ambient motion, and status bar

`WORLD` owns the selected visual theme (`:ABYSS`, `:CORAL`, or `:MOONLIGHT`)
and whether the status bar is visible. Each theme has a 24-bit palette of named color
roles (`+THEME-RGB-PALETTES+` in `src/palette.lisp`), and `*COLOR-MODE*` decides
how a role reaches the terminal: as a 24-bit color, the nearest 256-color
index, the nearest of the 16 system colors, or no color. `COLOR-STYLE` resolves
a role into a `cl-tty-kit` style for the active mode once, when a creature or
sprite prototype is built; nothing on the per-frame path converts a color.

`WORLD-SET-THEME` switches theme by recoloring creatures in place rather than
rebuilding the scene: each art file registers a restyler per creature kind
with `REGISTER-CREATURE-RESTYLER`, and `WORLD-SET-THEME` calls the one
registered for each creature's kind. No creature is removed, added, or moved
and no random number is drawn, so a theme change never reshuffles a seeded
run. Restylers cover the scenery, status bar, help and zukan panels, bubbles,
food, fish, the shark, and special guests (which share
`REGISTER-NAMED-COLOR-RESTYLER`). `WORLD-CYCLE-THEME` is `WORLD-SET-THEME` with the next
member of `+VISUAL-THEMES+`. `WORLD-TOGGLE-HUD` adds or removes the status bar
creature without changing simulation state.

The scenery is laid out from the screen size by `MAKE-BACKGROUND-CREATURES`
(`src/art-decor.lisp`): sky, waterline, ripple row, ambient current, castle,
seaweed, seabed ornaments, and sand. `LAYOUT-WATERLINE-ROW` puts the waterline
on `+WATERLINE-ROW+` on screens at least 24 rows tall and proportionally
higher on shorter ones;
`WORLD-SWIM-BAND`, `WORLD-SAND-TOP`, and `WORLD-STATUS-ROW` derive the other
bands from it and from the height. `WORLD-RESIZE` therefore removes and rebuilds
the scenery for the new size instead of clamping it.

The ambient current is a four-row animated `:AMBIENT-CURRENT` creature with
four deterministic frames, its rows spread through the water between the
ripple row and the sand. It has no edge callback, but it still participates
in z-ordering, clipping, prepared-sprite caching, and incremental redraw. The
status bar is a one-row `:HUD` creature at the top render layer on the bottom
row. `WORLD-REFRESH-HUD` rebuilds its text after theme, pause, fish-target,
weather, redraw, resize, or notification changes, never per tick. `%ADD-WORLD-CREATURE`
also refreshes it when it records a new fish species, so the dex count changes
immediately. `WORLD-NOTIFY` sets a notification that
`WORLD-ADVANCE` counts down, paused or not, for four seconds of ticks at the
`TICKS-PER-SECOND` given to `MAKE-WORLD`. This makes status information a
composited part of the scene instead of a second output path.

## Render order, blit runs, and incremental frames

`CREATURE`'s data model (`src/creature.lisp`) and private prepared-sprite cache
(`src/creature-cache.lisp`), plus `WORLD` (`src/world.lisp`), cache the derived
data needed for compositing. Renderer lifecycle state, snapshots, dirty-region
reconciliation, and bounded parallel cache preparation live in
`src/render-state.lisp`; `DRAW-WORLD` remains the simple full-repaint reference
path, while `RENDER-FRAME` (`src/render.lisp`) owns screen compositing and uses
the same cached data to update only the screen regions affected since its
previous call:

- Each `CREATURE` keeps its private `%FRAMES`/`%STYLE` alongside prepared,
  already-mirrored copies and precomputed opaque "blit runs" (flat
  X/Y/screen triples `CREATURE-BLIT` composites directly, without reparsing
  sprite text). Every cell in a run carries its final style, resolved once
  when the runs are prepared, so per-character coloring costs nothing per
  frame. Under `*ASCII*`, frames pass through `ASCII-TEXT` as they are stored.
  `%ENSURE-CREATURE-CACHES-CURRENT` only rebuilds these when the
  public `CREATURE-FRAMES`/`CREATURE-STYLE` accessors have been used to
  plausibly mutate the source data (tracked via `%FRAMES-ESCAPED-P` and
  `%STYLE-ESCAPED-P`) and the current value no longer matches the last
  prepared snapshot -- a getter alone does not force a rebuild, only a getter
  *followed by* a change does.
- A creature built with `:MASKS` and `:ROLE-STYLES` has one mask per frame,
  with exactly the frame's line shape (otherwise `MAKE-CREATURE` signals
  `ASCIIQUARIUM-INVALID-MASK`). A space in the mask leaves the cell to the
  art and `STYLE`, so a space under a space stays transparent. Any other mask
  character names a role: the cell takes that role's style from
  `:ROLE-STYLES` and is opaque even where the art has a space. Such a masked
  space is painted with the role's foreground color as its background, a solid
  fill, in the modes that paint backgrounds; in the 16-color and monochrome
  modes, whose role styles carry no background color, it keeps the role's
  style unchanged. Facing `:LEFT` uses masks mirrored by
  `MIRROR-SPRITE-MASK`, which pads lines to the longest one and reverses them
  by the same rule as `MIRROR-SPRITE-TEXT`, so art and mask stay aligned.
- An in-place restyle (`WORLD-SET-THEME` calling a kind's restyler) replaces a
  creature's `STYLE` and role styles and rebuilds its blit runs once, leaving
  frames, masks, position, and animation state alone. The renderer compares a
  creature's runs with its snapshot by identity, so the rebuilt runs mark that
  creature's bounds dirty like any other change.
- `WORLD` keeps a private `%CREATURES` list alongside a cached
  `Z`-sorted render order. Internal mutation paths (`%ADD-WORLD-CREATURE`,
  `%SET-WORLD-CREATURES`) invalidate that cache directly.
- `RENDER-FRAME` delegates renderer-owned snapshots and dirty-region
  reconciliation to `RENDER-STATE`, which stores snapshots in a weak table. It
  compares the current creature state with the previous frame, coalesces each
  changed creature's old and new clipped bounds, clears those rectangles to
  the background cell, and blits only creatures intersecting them. Added,
  removed, and reordered creatures all invalidate the necessary regions. It
  falls back to a full repaint when the dirty area covers at least half the
  screen or there are too many dirty rectangles, avoiding pathological
  incremental work after large changes, and when the background cell differs
  from the previous frame's: a theme change moves no creature, so no dirty
  rectangle would cover the open water. `RENDER-FRAME` and `SHUTDOWN-RENDERER`
  share one ownership boundary, so shutdown cannot remove a renderer state
  while a frame is using its reusable executor.
- The background cell (`WORLD-BACKGROUND-CELL`, built by `BACKGROUND-CELL`) is
  a space over the theme's water color in the `:TRUECOLOR` and `:ANSI256`
  modes, and `NIL`, the plain blank, in `:ANSI16` and `:MONO`. `DRAW-WORLD`
  clears to it, and `RUN` passes it to the renderer as its initial cell, so
  the water shows between sprites without a full-screen background creature.
  `WORLD` caches it per theme and color mode, so asking for it every frame
  allocates nothing.
- `MAKE-BUBBLE` (`src/bubble.lisp`) selects a cached immutable prototype keyed
  by visual theme and effective color mode, and shares its prepared frames, style,
  and blit runs across every bubble it spawns (bubbles are the highest-churn
  creature, one per fish roughly every 20-60 ticks) via `MAKE-CREATURE`'s
  `%SPRITE-PROTOTYPE` argument. Selection happens at spawn time, so a dynamic
  `*COLOR-MODE*` or `*MONOCHROME*` binding remains correct without reconstructing the equivalent
  style and prepared runs for every bubble. Public frame/style access still
  materializes private mutable copies before exposing them.

## Pure simulation, thin real I/O

Following the split `cl-tty-kit`'s `examples/renderer-loop.lisp` and
`examples/event-loop.lisp` establish: `WORLD-ADVANCE` (`src/update.lisp`) is
a pure state transition -- no I/O, no wall clock -- so
`cl-tty-kit:TICK-LOOP-RUN` can call it a fixed number of times and produce an
exactly reproducible result. Every test in `t/` drives the simulation this
way. `src/app.lisp` is the thin real-I/O side: `src/app-zukan.lisp` reads and
writes the dex, and `src/app-snapshot.lisp` writes screen snapshots outside
`WORLD-ADVANCE`. The terminal session enables mouse reporting, and
`WORLD-APPLY-KEY-EVENTS` routes left-button presses to
`WORLD-APPLY-MOUSE-EVENT` for food. `MAKE-WORLD-POLLER` composes
`cl-tty-kit:MAKE-TERMINAL-SIZE-POLLER` and `cl-tty-kit:MAKE-STREAM-INPUT-POLLER`
(provided by `cl-tty-kit` 1.5.0) into the terminal-size/stdin poll
`TICK-LOOP-RUN-REALTIME` runs once per tick, ahead of `WORLD-ADVANCE` itself.

`RUN` (`src/app.lisp`) uses continuation-passing style here. It does not call
the tick loop's poll/advance/render/quit steps directly; it hands
`TICK-LOOP-RUN-REALTIME` four closures: the poller `MAKE-WORLD-POLLER`
returns, an advancer from `MAKE-ZUKAN-ADVANCER` (or `#'WORLD-ADVANCE` when the
dex is not writable), a frame drawer from `MAKE-FRAME-DRAWER`, and
`#'WORLD-QUITP`. Control never
returns to `RUN` until the loop itself decides to quit -- `RUN` is inverted,
and the loop is what drives the continuations forward each tick, polling for
new terminal state before every pure advance. `cl-tty-kit`'s loop owns when
the next tick happens, so this is the effectful boundary where CPS is useful.
`WORLD-ADVANCE` and everything it calls stay direct-style on purpose;
rewriting a pure, already-total state transition into continuation-passing
form would add an
indirection with no boundary to justify it, at the direct cost of the
readability this project otherwise prioritizes.

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
