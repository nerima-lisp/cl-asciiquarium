# Getting started

## From a Lisp image

```lisp
(asdf:load-system "cl-asciiquarium")

(cl-asciiquarium:run)
```

`RUN` takes over the current terminal (alternate screen, cursor hidden, raw
input) until you press `q`. Useful keywords:

```lisp
(cl-asciiquarium:run :width 100 :height 30  ; override the detected terminal size
                      :seed 42              ; reproducible spawns and lanes
                      :fish-count 12
                      :theme :coral         ; initial visual theme
                      :interval 1/24)       ; seconds per frame (default 1/20)
```

## From the command line

Once built (`nix build`, which puts it at `./result/bin/asciiquarium`, or
`(asdf:operate 'asdf:program-op "cl-asciiquarium")`),
the delivered binary exposes the same knobs:

```sh
asciiquarium --width 100 --height 30 --seed 42 --fps 24 --theme coral
```

Run `asciiquarium --help` for the full option list.

## Controls

| Key | Effect |
|---|---|
| `q` / `Q` / Ctrl-C | Quit |
| `r` / `R` | Redraw: remove and respawn every fish, shark, guest, egg, and fry; background stays |
| Space | Pause / resume the simulation |
| `t` / `T` | Cycle the visual theme, recoloring everything in place |
| `u` / `U` | Toggle the status bar on the bottom row |
| `+` / `=` | Grow the target fish count by one (up to `--max-fish`, default 30) |
| `-` / `_` | Shrink the target fish count by one |
| `s` / `S` | Spawn a shark immediately (no-op under `--no-shark`) |
| `g` / `G` | Spawn a random special guest immediately |
| `c` / `C` | Spawn a school of six fish, when it fits under `--max-fish` |
| `h` / `H` | Toggle the on-screen key-list panel |

A terminal resize is picked up automatically -- cl-asciiquarium polls the
terminal size once per frame (see [Architecture](reference/architecture.md)).

## Flags worth knowing about

- `--no-shark` -- disable the shark. A landed anchor and the lantern fish
  still eat fish.
- `--max-fish N` -- the highest target fish count `+` reaches (1-40, default
  30).
- `--calm` -- stop blinking animations.
- `--color auto|truecolor|256|16|mono` -- choose the color depth; `auto`
  (the default) reads `COLORTERM`, `TERM`, and `NO_COLOR`.
- `--ascii` -- draw only ASCII symbols, for terminals that lack the Unicode
  ones or draw them two columns wide.
- `--monochrome` -- the same as `--color mono`: render everything in the
  terminal's default colors.
- `--theme abyss|coral|moonlight` -- select the initial visual theme.
