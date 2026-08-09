# Keybindings and CLI

## Keybindings

Decoded via cl-tty-kit's input decoder (`WORLD-APPLY-KEY-EVENT` in
`src/input.lisp`):

- `q`, `Q`, or Ctrl-C -- quit. The realtime loop's `stop` predicate is
  `WORLD-QUITP`, checked once per tick after that tick's frame has already
  been rendered, so the frame that caused the quit is always shown before
  exit.
- `r` or `R` -- redraw. Calls `WORLD-REDRAW`, which removes every fish, the
  shark (if present), any bubbles in flight, and every special guest
  (including a dolphin or sea monster mid-crossing), then repopulates a fresh
  set of fish at random lanes and speeds. The waterline, castle, and seaweed
  are left in place, as are the ambient current, HUD, and help panel if they
  are visible.
- Space -- pause or resume. `WORLD-ADVANCE` becomes a no-op while
  `WORLD-PAUSED-P` is true: the whole simulation freezes, not just the
  redraw, so nothing moves, ages, or spawns until unpaused.
- `t` or `T` -- cycle the visual theme through `abyss`, `coral`, and
  `moonlight` (`WORLD-CYCLE-THEME`). The scene is rebuilt through the existing
  creature factories so all theme-dependent sprites invalidate their caches
  together.
- `u` or `U` -- toggle the HUD (`WORLD-TOGGLE-HUD`). The HUD shows the active
  theme, fish count, and paused/running state.
- `+` or `=` -- grow the live fish count by one (`WORLD-INCREASE-FISH-COUNT`),
  up to `+MAX-FISH-COUNT+`.
- `-` or `_` -- shrink the live fish count by one (`WORLD-DECREASE-FISH-COUNT`),
  down to zero.
- `s` or `S` -- spawn a shark immediately (`SPAWN-SHARK-NOW`), resetting its
  cooldown. A no-op when `--no-shark` is in effect.
- `g` or `G` -- spawn a random special guest immediately (`SPAWN-GUEST-NOW`),
  drawing among ship, duck line, dolphin, and sea monster with equal
  probability, and resetting the guest cooldown.
- `h` or `H` -- toggle a fixed help panel (`WORLD-TOGGLE-HELP-OVERLAY`)
  listing every binding above.

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
| `--monochrome` | flag | off | Render every creature in the terminal's default foreground color |
| `--theme` | `abyss`, `coral`, or `moonlight` | `abyss` | Select the initial visual theme |

`--help` and `--version` are handled automatically by cl-cli.

## Resizing

cl-tty-kit polls the terminal size rather than trapping `SIGWINCH` (see its
`terminal-size.lisp`), and this application follows the same approach:
`%POLL-RESIZE` in `src/app.lisp` compares the detected size against the
running `WORLD` once per tick and calls `WORLD-RESIZE` plus
`cl-tty-kit:renderer-resize` when it has changed.
