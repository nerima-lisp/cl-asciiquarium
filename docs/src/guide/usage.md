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
  coins from the chest go too, and so do the octopus's tentacle and ink cloud
  and any food. The background scenery (see [Screen layout](#screen-layout))
  is left in place, along with the seabed's residents (vent plume, crab,
  octopus), as are the status bar and the help or dex panel if one is visible. An octopus that was
  reaching or hiding in its ink peeks over its rock again on the next tick.
- Space -- pause or resume. `WORLD-ADVANCE` becomes a no-op while
  `WORLD-PAUSED-P` is true: the whole simulation freezes, not just the
  redraw, so nothing moves, ages, or spawns until unpaused.
- `t` or `T` -- cycle the visual theme through `abyss`, `coral`, and
  `moonlight` (`WORLD-CYCLE-THEME`). The scene is recolored in place
  (`WORLD-SET-THEME`): no creature is removed, added, or moved, and no random
  number is drawn, so a seeded run is not reshuffled. Everything but the fish
  takes the new theme's colors; fish keep the colors they were created with.
  The chosen theme also becomes the time of day, and the automatic
  time-of-day cycle restarts from it (`WORLD-CHANGE-DAYPART`; see
  [Weather and time of day](#weather-and-time-of-day)). The gulls are the one
  exception to the in-place recolor: whenever the time of day changes, by a
  key or on its own, they come back under `coral` or `abyss`
  (`POPULATE-GULLS`) and fly off under `moonlight`.
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
- `f` or `F` -- spawn a fisher immediately (`SPAWN-FISHER-NOW`), even when
  big events already fill their limit of two.
- `e` or `E` -- sprinkle six grains of food on the top row of the water,
  somewhere in the middle half of the screen. See [Food](#food).
- `w` or `W` -- move on to the next weather now (`WORLD-ADVANCE-WEATHER`):
  `clear`, then `rain`, then `storm`, then `clear` again. The next automatic
  change is scheduled from this moment.
- `n` or `N` -- move on to the next time of day now
  (`WORLD-ADVANCE-DAYPART`): day (`coral`), then dusk (`abyss`), then night
  (`moonlight`), then day again. It works under `--no-daycycle` too.
- `h` or `H` -- toggle the help panel (`WORLD-TOGGLE-HELP-OVERLAY`), a
  rounded box just below the waterline listing every binding above.
- `z` or `Z` -- toggle the fish dex panel, which lists every species in two
  columns: the name of each one discovered so far, with `✦` after a rare one,
  and `???` for the rest. The help and dex panels take the same place, so
  opening one closes the other. The panel is drawn when it opens; a species
  discovered while it is open shows the next time it is opened. See
  [Fish dex](#fish-dex).
- `p` or `P` -- save the screen as a text file. See [Snapshots](#snapshots).

Any other decoded key (arrows, function keys, ...) is accepted and ignored;
this application does not bind them.

### Mouse

The aquarium asks the terminal to report mouse button presses, and a left
click sprinkles three grains of food at the clicked cell (moved into the
water when the click is above or below it). Other buttons, releases, and the
wheel do nothing. While the aquarium runs, most terminals stop selecting text
with a plain drag; hold Shift while dragging to select text as usual. Mouse
reporting is turned off again when the aquarium exits.

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
| `--calm` | flag | off | Stop blinking animations (the lantern fish's light) and the storm's lightning flash |
| `--no-daycycle` | flag | off | Keep the starting theme instead of moving through day, dusk, and night on its own |
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
- **Gulls fish from the sky.** Two gulls cruise the sky by day and wrap
  around the screen. A gull above a fish within six rows of the waterline
  dives at it now and then, carries off a fish it grabs, and does not dive
  again for 700 ticks after a catch. Caught fish are replaced like eaten
  ones. The gulls leave at night and come back with the next day or dusk.
  There are no gulls when fewer than three sky rows fit above the waterline.
- **A fisher visits.** A small boat sails in from one edge, stops, and lowers
  a line until the hook rests just above the sand. A fish that touches the
  hook is caught and reeled up, and the fisher shows a `!` for 30 ticks
  before sailing on. A hook that catches nothing rests for 80 ticks and is
  reeled up empty. The first fisher comes at tick 800 and the next every
  1000 to 1800 ticks.

Ships, submarines, divers' dinghies, and fishers are big events: they appear
on their own only while fewer than two of them in total are on screen. The
`g`, `a`, `m`, `d`, and `f` keys spawn past that limit.

## Food

A grain of food (`•`, `o` under `--ascii`) sinks 0.05 rows per tick and rests
on the lowest row of the water, just above the sand. Every tick, the nearest
fish that is swimming toward a grain, is not in a school, and has at most 20
empty columns and 6 empty rows between itself and the grain moves up to one
column and a quarter row closer to it; a jelly or seahorse moves only
sideways. A fish facing away does not
come until it turns at the screen edge. The first fish to touch a grain eats
it and swims on; a grain nobody eats is gone after 400 ticks. Up to 18 grains
can be in the tank at once; `e` and clicks add nothing beyond that. Food can
be sprinkled while paused, but it sinks and is eaten only after the
simulation resumes.

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

## Weather and time of day

The weather starts `clear` and changes in a fixed order: `clear`, then `rain`,
then `storm`, then `clear` again. The first change comes at tick 700, and each
later weather lasts 500 to 900 ticks.

- **Rain** falls as `'` drops through the sky, with ripples on the row just
  under the waterline.
- **A storm** covers the top two sky rows with a dark cloud band, slants its
  rain down to the left, and puts choppy `^` crests on the waterline. Ships
  and the fisher's boat bob up and down by a row. Now and then lightning
  lights every sky row white for two ticks with a zigzag bolt; `--calm`
  turns the flash off.

Each time of day has its own theme: day is `coral`, dusk is `abyss`, and
night is `moonlight`. Every 1100 ticks the scene moves on to the next one in
that order. This order differs from the `t` key's: from `abyss`, `t` goes to
`coral` (back to day) while `n` goes to `moonlight`. `t` and `n` restart the
1100-tick wait, and `--no-daycycle` turns the automatic change off. Glowing plankton
dots the water, sparse by day, more at dusk, and densest at night.

## Fish dex

The dex records every species that has appeared in the tank, across runs. It
is the file `$XDG_STATE_HOME/cl-asciiquarium/zukan.sexp`, or
`~/.local/state/cl-asciiquarium/zukan.sexp` when `XDG_STATE_HOME` is unset,
empty, or not an absolute path. The file is read once at startup, and the
species in it count as already discovered, so a rare species is announced in
the status bar only the first time it ever appears. The file is written
right after each new discovery, not at exit; when a write fails, the status
bar says `dex save failed` and the next discovery tries again. Before each
write the file is read again and merged with this run's species, so with two
aquariums running at once, one can overwrite the other's latest discovery
only when both write within the same instant. The run whose discovery was
lost still remembers it and writes it again at its own next discovery.

A file this build cannot read (not one `(:zukan 1 :species (:dart :golden))`
form of distinct keywords, or not valid UTF-8) is left untouched: the status
bar says `dex file unreadable; not saving`, and that run starts with nothing
discovered and never writes the file.
Species a newer build added are kept and written back, but they are not
counted in the status bar or the dex panel.

## Snapshots

`p` saves the characters on screen, without colors, to a new text file named
`aquarium-YYYYMMDD-HHMMSS.txt` from the local time, with `-1`, `-2`, ... added
when that name is taken. Trailing spaces are removed from each row. The file
goes to the directory in the `XDG_PICTURES_DIR` environment variable when it
is an absolute path, and otherwise to the current directory; the
`~/.config/user-dirs.dirs` file is not read. A missing directory is not
created. The status bar then shows `Saved <file name>` or `Snapshot failed`.

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
the help and dex panels' box lines, the dex panel's `✦`, the status bar's dots,
food grains, the anchor chain's `¦`, the octopus's `▒` ink) with a one-column ASCII stand-in (`ASCII-TEXT`).

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
`moonlight`), the weather (`clear`, `rain`, or `storm`), the fish count, how many
of the known fish species have appeared so far (`dex`), and whether the
simulation is swimming or paused. Key hints fill the right-hand side. A
message passed to `WORLD-NOTIFY` replaces the key hints for four seconds, and
the summary drops groups (in the order below) to make room for it.

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
