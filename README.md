# cl-asciiquarium

[![CI](https://github.com/nerima-lisp/cl-asciiquarium/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-asciiquarium/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-asciiquarium/)

An original ASCII-art aquarium screensaver for the terminal: swimming fish (5
species, color-varied), a shark, rising bubbles, an animated ambient current,
swaying seaweed, and periodic special guests (a ship that drops an anchor, a
line of ducks, a leaping dolphin, a segmented sea monster), rendered live via
[cl-tty-kit](https://github.com/nerima-lisp/cl-tty-kit). Choose between the
`abyss`, `coral`, and `moonlight` visual themes, watch the live HUD, pause, dial
the fish count up or down, spawn a shark or guest on demand, or run
monochrome. Press `h` in-app for the full key list. Every sprite is original
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

## Visual modes

The `t` key cycles the visual theme without changing the renderer contract:
`abyss` is the deep-water default, `coral` is warmer, and `moonlight` is a
cooler high-contrast palette. The `u` key toggles the HUD, which reports the
active theme, fish count, and paused/running state. The HUD and ambient current
are regular creatures in the scene, so they are clipped, ordered, cached, and
redrawn by the same incremental renderer as every fish and guest.

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
  url = "github:nerima-lisp/cl-asciiquarium/v0.1.0";
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
  the CREATURE contract every sprite type goes through, and what this v1
  deliberately included versus cut
- [Roadmap](https://nerima-lisp.github.io/cl-asciiquarium/project/roadmap/)

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix build            # -> ./result/bin/asciiquarium
nix run .#test       # run the test suite
nix flake check      # tests + formatting + docs + paredit lint, the same gate CI uses
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
bounds once for each active predator and live fish before scanning overlaps. Its
steady-state path creates no temporary collision lists or records; those bounds
are implementation details and do not expand the public `creature` API.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
