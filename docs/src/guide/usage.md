# Keybindings and CLI

## Keybindings

Decoded via cl-tty-kit's input decoder (`WORLD-APPLY-KEY-EVENT` in
`src/input.lisp`):

- `q` or `Q` -- quit. The realtime loop's `stop` predicate is `WORLD-QUITP`,
  checked once per tick after that tick's frame has already been rendered, so
  the frame that caused the quit is always shown before exit.
- `r` or `R` -- redraw. Calls `WORLD-REDRAW`, which removes every fish, the
  shark (if present), any bubbles in flight, and any special guest, then
  repopulates a fresh set of fish at random lanes and speeds. The waterline,
  castle, and seaweed are left in place.

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

`--help` and `--version` are handled automatically by cl-cli.

## Resizing

cl-tty-kit polls the terminal size rather than trapping `SIGWINCH` (see its
`terminal-size.lisp`), and this application follows the same approach:
`%POLL-RESIZE` in `src/app.lisp` compares the detected size against the
running `WORLD` once per tick and calls `WORLD-RESIZE` plus
`cl-tty-kit:renderer-resize` when it has changed.
