# Keybindings and CLI

## Keybindings

Decoded via cl-tty-kit's input decoder (`WORLD-APPLY-KEY-EVENT` in
`src/input.lisp`):

- `q`, `Q`, or Ctrl-C -- quit. The realtime loop's `stop` predicate is
  `WORLD-QUITP`, checked once per tick after that tick's frame has already
  been rendered, so the frame that caused the quit is always shown before
  exit.
- `r` or `R` -- redraw. Calls `WORLD-REDRAW`, which removes every fish, the
  shark (if present), any bubbles in flight, every egg, fry, and heart, and
  every special guest (including a dolphin or sea monster mid-crossing), then
  repopulates a fresh
  set of fish at random lanes and speeds. Ships with their anchor and chain,
  submarines with their sonar rings, divers with their dinghy and rope, and
  coins from the chest go too, and so do the octopus's tentacle and ink cloud.
  The background scenery (see [Screen layout](#screen-layout)) is left in
  place, along with the seabed's residents (vent plume, crab, octopus), as are
  the status bar and help panel if they are visible. An octopus that was
  reaching or hiding in its ink peeks over its rock again on the next tick.
- Space -- pause or resume. `WORLD-ADVANCE` becomes a no-op while
  `WORLD-PAUSED-P` is true: the whole simulation freezes, not just the
  redraw, so nothing moves, ages, or spawns until unpaused.
- `t` or `T` -- cycle the visual theme through `abyss`, `coral`, and
  `moonlight` (`WORLD-CYCLE-THEME`). The scene is recolored in place
  (`WORLD-SET-THEME`): no creature is removed, added, or moved, and no random
  number is drawn, so a seeded run is not reshuffled. Everything but the fish
  takes the new theme's colors; fish keep the colors they were created with.
- `u` or `U` -- toggle the status bar on the bottom row (`WORLD-TOGGLE-HUD`);
  see [Status bar](#status-bar).
- `+` or `=` -- grow the target fish count by one and add a fish
  (`WORLD-INCREASE-FISH-COUNT`), up to `--max-fish`.
- `-` or `_` -- shrink the target fish count by one
  (`WORLD-DECREASE-FISH-COUNT`), down to zero. A live fish is removed only
  when more live fish than the new target remain, so pressing `-` while a
  refill is pending cancels the refill instead of taking another fish.
- `s` or `S` -- spawn a shark immediately (`SPAWN-SHARK-NOW`), resetting its
  cooldown. A no-op when `--no-shark` is in effect.
- `g` or `G` -- spawn a random special guest immediately (`SPAWN-GUEST-NOW`),
  drawing among ship, duck line, dolphin, and sea monster with equal
  probability, and resetting the guest cooldown.
- `c` or `C` -- spawn a school of six fish immediately
  (`SPAWN-SCHOOL-IF-ROOM`). When the six would take the tank past
  `--max-fish`, nothing spawns and the status bar says the tank is too full.
- `a` or `A` -- spawn a ship immediately (`WORLD-SPAWN-SHIP`); it stops near
  mid-screen and lowers its anchor. See [Seabed life](#seabed-life).
- `m` or `M` -- spawn a submarine immediately (`WORLD-SPAWN-SUBMARINE`).
- `d` or `D` -- send a diver in a dinghy for the treasure chest immediately
  (`WORLD-SPAWN-DIVER`). When the screen is too small to hold a chest, nothing
  spawns and the status bar says "No treasure chest for a diver"; while a
  diver is already out, nothing spawns and it says "A diver is already out".
- `h` or `H` -- toggle the help panel (`WORLD-TOGGLE-HELP-OVERLAY`), a
  rounded box just below the waterline listing every binding above.

Any other decoded key (arrows, function keys, ...) is accepted and ignored;
this application does not bind them.

## Command-line options

The `asciiquarium` binary (see `src/cli.lisp`, built via cl-cli):

| Option | Type | Default | Effect |
|---|---|---|---|
| `--width` | integer | detected terminal width | Initial `WORLD` width |
| `--height` | integer | detected terminal height | Initial `WORLD` height |
| `--seed` | integer | none (unseeded) | Seeds `cl:*random-state*` for a reproducible run |
| `--fps` | integer, 1-60 | 20 | Target frames per second |
| `--no-shark` | flag | off | Disable the shark for the whole run |
| `--max-fish` | integer, 1-40 | 30 | The highest target fish count `+` reaches; the tank starts with 18 fish, or this many if lower |
| `--calm` | flag | off | Stop blinking animations (the lantern fish's light) |
| `--color` | `auto`, `truecolor`, `256`, `16`, or `mono` | `auto` | Select the color depth; see [Color modes](#color-modes) |
| `--ascii` | flag | off | Draw only ASCII symbols, for terminals that lack the Unicode ones or draw them two columns wide |
| `--monochrome` | flag | off | Same as `--color mono`: render everything in the terminal's default colors |
| `--theme` | `abyss`, `coral`, or `moonlight` | `abyss` | Select the initial visual theme |

`--help` and `--version` are handled automatically by cl-cli.

## Life in the tank

Each of the following happens on its own; the `s` and `c` keys can also
bring the shark and a school in early. Times are in ticks: one tick is one
frame, 20 per second unless `--fps` says otherwise.

- **The shark hunts.** It steers up or down toward the nearest fish within 45 columns ahead of its nose, and eats a fish its
  mouth touches. After two meals it grows larger; after three it is full,
  stops hunting, and leaves at twice its speed, with a notice in the status
  bar.
- **Eaten fish are replaced.** 90 ticks after a fish is eaten, a new one swims
  in from the left or right edge, one at a time, until the tank is back at the
  target fish count.
- **Schools.** Six fish of one small species swim in formation. When a threat
  (the shark, a landed anchor, the submarine, or an octopus's tentacle) comes
  within 26 columns, they scatter for 30 ticks and then regroup. A school also
  appears on its own, first at tick 600 and then every 900 to 1600 ticks, but
  only when it fits under `--max-fish`.
- **Puffers** inflate for 45 ticks when a threat comes within 18 columns and 7
  rows.
- **Lantern fish** blink their light. Every 240 ticks one draws in the
  nearest small fish (dart, guppy, or clownfish) within 30 columns and eats it
  when it reaches the light. Under the `moonlight` theme the light has a halo.
- **Spawning.** Every 50 ticks, one fish ready to breed starts courting. If it
  meets a ready fish of its own species, a heart appears and they lay an egg,
  and neither breeds again for 700 ticks. The egg hatches into a fry after 100
  ticks, and the fry grows into a fish 220 ticks later. A full tank (as many
  live fish as `--max-fish`) keeps it a fry until there is room. At most three
  eggs and fry exist at once.

Ships, submarines, and divers' dinghies are big events: they appear on their
own only while fewer than two of them in total are on screen. The `g`, `a`,
`m`, and `d` keys spawn past that limit.

## Seabed life

The chest, rock, and vent are placed only where they fit (see
[Screen layout](#screen-layout)); on a small screen any of them may be left
out, and then so is what lives on it: the diver needs the chest, the octopus
the rock, and the plume the vent.

- **The anchor.** A ship stops near mid-screen and lowers its anchor on a `¦`
  chain to the seabed. Only after landing does it eat fish: for 70 ticks it
  eats any fish it rests on, then it rises and the ship sails on.
- **The submarine** crosses the water at 0.35 columns per tick. It enters on
  its own first at tick 900 and then every 1200 to 2000 ticks. Every 50 ticks it
  sends out a sonar ring, `( )`, that widens; a fish the ring passes stops
  for 25 ticks with a `!` over its head. Fish in a school stop too, even while
  the school scatters, and rejoin the school's formation once the stun ends.
- **The treasure chest** opens every 380 to 520 ticks for 45 ticks, releasing
  8 bubbles and throwing 6 `$` coins that arc up and fall back. A diver also
  arrives on their own, first at tick 1200 and then every 1400 to 2400 ticks:
  a dinghy stops on the surface, the diver climbs down a rope beside the
  chest, breathing out bubbles, takes the gold, and climbs back, and the
  dinghy sails on. After the diver takes the gold, the chest stays shut for
  700 ticks.
- **The vent** always sends up a plume of bubbles 9 columns wide, which
  pushes any fish swimming in it upward.
- **The crab** walks along the sand and turns around at the screen edges.
- **The octopus** peeks over the rock. When a fish swims within 12 columns
  and 6 rows of the rock, it reaches a `()()` tentacle out and drags the fish
  into its den; the fish is replaced from the screen edge like an eaten one.
  When the shark, a landed anchor, or the submarine comes within 14 columns
  and 6 rows, the octopus spits a `▒` ink cloud that thins away over 50 ticks
  and hides behind the rock until the ink is gone.

## Color modes

`--color` decides how each theme's 24-bit palette (`src/palette.lisp`) reaches
the terminal:

- `truecolor` -- 24-bit colors, with the water's background color painted
  behind the scene.
- `256` -- the nearest xterm 256-color index for each color, background
  included.
- `16` -- the nearest of the 16 system colors. No background is painted, so
  the terminal's own background shows through.
- `mono` -- no color.

`auto` (`DETECT-COLOR-MODE`) picks `mono` when `NO_COLOR` is set and
non-empty, `truecolor` when `COLORTERM` is `truecolor` or `24bit`, `256` when
`TERM` contains `256color`, and `16` otherwise. An explicit `--color` value
wins over `NO_COLOR`, and `--monochrome` forces `mono` whatever `--color` says
(`RESOLVE-COLOR-MODE`).

`--ascii` replaces every non-ASCII symbol a sprite draws (the waterline crest,
the help panel's box lines, the status bar's dots, the anchor chain's `¦`, the
octopus's `▒` ink) with a one-column ASCII stand-in (`ASCII-TEXT`).

## Screen layout

On a screen at least 24 rows tall, the layout runs top to bottom as follows:

- Rows 0-4: the sky, which follows the theme: the sun and a cloud for
  `coral`, the sun setting on the horizon and a cloud for `abyss`, and the
  moon and stars for `moonlight`.
- Row 5: the waterline (`+WATERLINE-ROW+`), with a moving bright crest.
- Row 6: a ripple row.
- The water, with four rows of ambient current spread through it.
- The seabed: a castle with lit windows on the left, then coral, a rock, a
  starfish, a vent, and a chest, each placed only where it fits clear of the
  two-tone seaweed strands.
- Three rows of sand.
- The bottom row: the status bar.

Below 24 rows the waterline moves up in proportion (`WORLD-WATERLINE-ROW`),
and the sky is left out once fewer than three rows remain above it. A resize
lays the scenery out again for the new size.

## Status bar

The status bar fills the bottom row. On the left it shows the theme badge,
the time of day (`day` for `coral`, `dusk` for `abyss`, `night` for
`moonlight`), the weather (currently always `clear`), the fish count, how many
of the known fish species have appeared so far (`dex`), and whether the
simulation is swimming or paused. Key hints fill the right-hand side. A
message passed to `WORLD-NOTIFY` replaces the key hints for four seconds.

When the screen is too narrow, the key hints are dropped first, then the
summary groups in this order: time of day and weather, the species count,
and the fish count. The theme badge and the swimming/paused state are never
dropped.

## Resizing

cl-tty-kit polls the terminal size rather than trapping `SIGWINCH` (see its
`terminal-size.lisp`), and this application follows the same approach:
`%POLL-RESIZE` in `src/app.lisp` compares the detected size against the
running `WORLD` once per tick and calls `WORLD-RESIZE` plus
`cl-tty-kit:renderer-resize` when it has changed.
