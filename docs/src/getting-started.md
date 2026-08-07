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
| `r` / `R` | Redraw: remove and respawn every fish, shark, and guest; background stays |
| Space | Pause / resume the simulation |
| `t` / `T` | Cycle the visual theme |
| `u` / `U` | Toggle the HUD |
| `+` / `=` | Grow the live fish count by one (up to 40) |
| `-` / `_` | Shrink the live fish count by one |
| `s` / `S` | Spawn a shark immediately (no-op under `--no-shark`) |
| `g` / `G` | Spawn a random special guest immediately |
| `h` / `H` | Toggle the on-screen key-list panel |

A terminal resize is picked up automatically -- cl-asciiquarium polls the
terminal size once per frame (see [Architecture](reference/architecture.md)).

## Flags worth knowing about

- `--no-shark` -- disable the shark, so fish are never eaten.
- `--monochrome` -- render every creature in the terminal's default
  foreground color instead of its species color.
- `--theme abyss|coral|moonlight` -- select the initial visual theme.
