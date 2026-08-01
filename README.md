# cl-asciiquarium

[![CI](https://github.com/nerima-lisp/cl-asciiquarium/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-asciiquarium/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-asciiquarium/)

An original ASCII-art aquarium screensaver for the terminal: swimming fish,
a shark, rising bubbles, swaying seaweed, and periodic special guests (a ship
that drops an anchor, a line of ducks), rendered live via
[cl-tty-kit](https://github.com/nerima-lisp/cl-tty-kit). Every sprite is
original art authored for this repository. Targets SBCL only.

Full documentation is published at <https://nerima-lisp.github.io/cl-asciiquarium/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

```lisp
(asdf:load-system "cl-asciiquarium")

(cl-asciiquarium:run :seed 42)
;; Fills the current terminal until `q' is pressed; `r' reshuffles the fish.
```

Or, once built, from the command line:

```sh
asciiquarium --seed 42 --fps 24
```

## Install

```nix
# flake.nix
inputs.cl-asciiquarium = {
  url = "github:nerima-lisp/cl-asciiquarium/v0.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org must pin a release tag rather
than follow the default branch.

## Documentation

- [Getting started](https://nerima-lisp.github.io/cl-asciiquarium/getting-started/)
- [API reference](https://nerima-lisp.github.io/cl-asciiquarium/reference/api/)
- [Architecture](https://nerima-lisp.github.io/cl-asciiquarium/reference/architecture/) --
  the CREATURE contract every sprite type goes through, and what this v1
  deliberately included versus cut
- [Roadmap](https://nerima-lisp.github.io/cl-asciiquarium/project/roadmap/)

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix run .#test       # run the test suite
nix flake check      # tests + formatting + docs, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework. Every test that depends on randomness (spawn timing,
species/lane selection, which special guest appears) binds `cl:*random-state*`
via `sb-ext:seed-random-state` to a fixed seed first, so predator/prey and
special-guest spawn scenarios are exactly reproducible; see
`t/helpers-world.lisp`.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
