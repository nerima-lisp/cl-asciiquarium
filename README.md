# cl-asciiquarium

[![CI](https://github.com/nerima-lisp/cl-asciiquarium/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-asciiquarium/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-asciiquarium/)

An original ASCII-art aquarium screensaver for the terminal: swimming fish of
many color-varied species, a hunting shark, rising bubbles, an animated
ambient current, swaying seaweed, a seabed with a castle and ornaments, a sky above the
waterline, and periodic special guests (a ship that drops an anchor, a
line of ducks, a leaping dolphin, a segmented sea monster), rendered live via
[cl-tty-kit](https://github.com/nerima-lisp/cl-tty-kit). Choose between the
`abyss`, `coral`, and `moonlight` visual themes, watch the status bar, pause,
dial the fish count up or down, or spawn a shark, guest, or school on demand,
and choose a color depth from 24-bit color down to monochrome at startup. Press
`h` in-app for the full key list. Every sprite is original
art authored for this repository. Targets SBCL only.

Full documentation is published at <https://nerima-lisp.github.io/cl-asciiquarium/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

```lisp
(asdf:load-system "cl-asciiquarium")

(cl-asciiquarium:run :seed 42 :theme :coral)
;; Fills the current terminal until `q' is pressed; `r' reshuffles the fish.
```

Or, once built, from the command line:

```sh
asciiquarium --seed 42 --fps 24 --theme coral
```

## Life in the tank

The shark hunts, eaten fish are replaced from the screen edge, schools scatter
and regroup, puffers inflate, lantern fish lure small fish to their light, and
fish of the same species lay eggs that grow into new fish. On the seabed an
octopus under the rock snatches passing fish, a vent's plume lifts them, a crab
walks the sand, and a treasure chest throws up gold until a diver comes for it.
A ship lowers an anchor that eats fish, and a submarine's sonar stuns them; the
`a`, `m`, and `d` keys bring a ship, a submarine, or a diver on demand. See
[Keybindings and CLI](https://nerima-lisp.github.io/cl-asciiquarium/guide/usage/).
The tank starts with 18 fish, or `--max-fish N` (1-40, default 30) if that is
lower, and `+` grows it up to `N`. `--calm` stops blinking animations and the
storm's lightning flash.

Press `e`, or left-click in the water, to sprinkle food: nearby fish swim over
and eat it. `z` opens the fish dex, the list of species seen so far, which is
kept across runs in `$XDG_STATE_HOME/cl-asciiquarium/zukan.sexp`, or in
`~/.local/state/cl-asciiquarium/zukan.sexp` when that variable is unset, empty,
or relative. If the dex file is malformed or cannot be read, the run starts
with an empty dex and does not save discoveries during that run. The status
bar reports the error, and the file remains untouched.
Each save rereads and merges the file. If two aquariums read it before either
replaces it, the later save can omit the other run's latest discovery. The run
whose discovery was omitted keeps it in memory and saves it on its next
discovery. `p` saves a text snapshot of the screen in `$XDG_PICTURES_DIR` when
that variable is an absolute path, otherwise in the current directory. To
select the terminal's text with the mouse while the aquarium runs, hold Shift
on most terminals.

Above the water, two gulls dive now and then for a fish near the surface and
leave at night, and a fisher sails in from time to time to lower a hook for
one; `f` calls a fisher at once. The weather moves from clear to rain to storm
and back, with rain, ripples, dark clouds, choppy water, rocking boats, and
lightning; `w` skips to the next weather.

## Visual modes

The `t` key cycles the visual theme without changing the renderer contract:
`abyss` is the deep-water default, `coral` is warmer, and `moonlight` is a
cooler high-contrast palette. The theme also sets the sky: day for `coral`,
dusk for `abyss`, and night for `moonlight`. A theme change recolors the
scenery, status bar, shark, and bubbles in place instead of rebuilding the
scene, so nothing moves or respawns.
The gulls are the exception: they fly off when the sky turns to night and
come back by day or dusk.

The time of day also changes on its own, from day to dusk to night and back,
and a `t` press restarts the wait before the next change from the chosen
theme. `n` skips to the
next time of day, and `--no-daycycle` keeps the starting theme until a key
changes it.

`--color auto|truecolor|256|16|mono` selects how the themes' 24-bit palettes
reach the terminal; `auto`, the command-line default, reads `COLORTERM`,
`TERM`, and `NO_COLOR`. From Lisp, `RUN` uses 16 colors unless given
`:color-mode`. The `truecolor` and `256` modes also paint the water's background.
`--monochrome` is the same as `--color mono`, and `--ascii` draws only ASCII
symbols.

The `u` key toggles the status bar on the bottom row, which reports the theme,
time of day, weather, fish count, discovered species, and paused/swimming state,
with key hints on the right. See
[Keybindings and CLI](https://nerima-lisp.github.io/cl-asciiquarium/guide/usage/)
for the screen layout and color-mode detection rules.

## Install

As a command, from a checkout:

```sh
nix build              # -> ./result/bin/asciiquarium
./result/bin/asciiquarium --seed 42 --fps 24
```

Or without cloning: `nix run github:nerima-lisp/cl-asciiquarium`.

As a library, from another flake:

```nix
# flake.nix
inputs.cl-asciiquarium = {
  url = "github:nerima-lisp/cl-asciiquarium/v0.3.1";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org must pin a release tag rather
than follow the default branch. On a `lispDependencies` edge, read
`cl-asciiquarium.packages.<system>.cl-asciiquarium` -- `packages.default` is
the delivered binary, not the ASDF system.

## Documentation

- [Getting started](https://nerima-lisp.github.io/cl-asciiquarium/getting-started/)
- [Keybindings and CLI](https://nerima-lisp.github.io/cl-asciiquarium/guide/usage/)
- [API reference](https://nerima-lisp.github.io/cl-asciiquarium/reference/api/)
- [Conditions](https://nerima-lisp.github.io/cl-asciiquarium/reference/conditions/) --
  the error hierarchy every condition this package signals descends from
- [Architecture](https://nerima-lisp.github.io/cl-asciiquarium/reference/architecture/) --
  the CREATURE contract every sprite type goes through
- [Roadmap](https://nerima-lisp.github.io/cl-asciiquarium/project/roadmap/)

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix build            # -> ./result/bin/asciiquarium
nix run .#test       # run the test suite
nix flake check      # tests + formatting + docs + paredit lint, the same gate CI uses
nix develop --command sbcl --script scripts/benchmark-render.lisp
                     # deterministic renderer/update-loop benchmark
nix fmt              # format Nix sources (treefmt)
nix build .#checks.x86_64-linux.coverage --no-link --print-out-paths
                     # sb-cover HTML report for src/; the build also gates
                     # executable logic at 88% expression / 90% branch
                     # coverage. Immutable art data and package declarations
                     # are explicitly excluded; see flake.nix.
```

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework. Every test that depends on randomness (spawn timing,
species/lane selection, which special guest appears) binds `cl:*random-state*`
via `sb-ext:seed-random-state` to a fixed seed first, so predator/prey and
special-guest spawn scenarios are exactly reproducible; see
`t/helpers-world.lisp`. `nix flake check` additionally runs
[paredit-cli](https://github.com/nerima-lisp/paredit-cli)'s structural lint
over every Lisp source file.

The collision pass validates mutable sprite caches and refreshes internal scalar
bounds once for each threat, sensing creature, and live fish before scanning overlaps. Its
steady-state path creates no temporary collision lists or records; those bounds
are implementation details and do not expand the public `creature` API.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
