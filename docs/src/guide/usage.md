# Keybindings and CLI

## Keybindings

Decoded via cl-tty-kit's input decoder (`WORLD-APPLY-KEY-EVENT` in
`src/input.lisp`):

- `q`, `Q`, or Ctrl-C -- quit. The realtime loop's `stop` predicate is
  `WORLD-QUITP`, checked once per tick after that tick's frame has already
  been rendered, so the frame that caused the quit is always shown before
  exit.
- `r` or `R` -- redraw. Calls `WORLD-REDRAW`, which recreates every aquarium
  entity, including the waterline, castle, seaweed, fish, shark, bubbles, and
  special guests, then repopulates a fresh set of fish at random lanes and
  speeds. The help panel, if it is open, is preserved as UI state.
- `p`, `P`, or Space -- pause or resume. `WORLD-ADVANCE` becomes a no-op while
  `WORLD-PAUSED-P` is true: the whole simulation freezes, not just the
  redraw, so nothing moves, ages, or spawns until unpaused.
- `+` or `=` -- grow the live fish count by one (`WORLD-INCREASE-FISH-COUNT`),
  up to `+MAX-FISH-COUNT+` (40).
- `-` or `_` -- shrink the live fish count by one (`WORLD-DECREASE-FISH-COUNT`),
  down to zero.
- `s` or `S` -- spawn a shark immediately (`SPAWN-SHARK-NOW`), resetting its
  cooldown. A no-op when `--no-shark` is in effect.
- `g` or `G` -- spawn a random special guest immediately (`SPAWN-GUEST-NOW`
  with a `RANDOM-GUEST-KIND` draw), resetting the guest cooldown.
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

`--help` and `--version` are handled automatically by cl-cli.

## Resizing

cl-tty-kit polls the terminal size rather than trapping `SIGWINCH` (see its
`terminal-size.lisp`), and this application follows the same approach:
`%POLL-RESIZE` in `src/app.lisp` compares the detected size against the
running `WORLD` once per tick and calls `WORLD-RESIZE` plus
`cl-tty-kit:renderer-resize` when it has changed.
