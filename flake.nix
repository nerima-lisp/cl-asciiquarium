{
  description = "An original ASCII-art aquarium screensaver for the terminal.";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The org flake preset. The single `mkPackageFlake` call below generates
    # this repository's entire required-output table, so none of it is
    # spelled out here and none of it can drift from the other repositories.
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.4.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sibling packages are ALWAYS pinned to a release tag; a bare
    # `github:nerima-lisp/<pkg>` follows that repo's default branch, which
    # would break this repo's CI without warning the moment upstream pushes
    # to main. `flake = false`: only the source tree is needed (to build a
    # `lispDerivation` below), never these repos' own flake outputs -- see
    # DEPENDENCY_POLICY.md "姉妹パッケージは flake = false で引きます".
    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.4.0";
      flake = false;
    };

    cl-cli = {
      url = "github:nerima-lisp/cl-cli/v1.3.0";
      flake = false;
    };

    # Transitive sibling dependencies of the two above -- cl-tty-kit.asd
    # depends on cl-codec-kit, cl-cli.asd depends on cl-host-kit. Nix builds
    # each lispDerivation as its own sandboxed derivation, so cl-tty-kit's and
    # cl-cli's OWN :depends-on must be satisfied by giving THEIR
    # lispDerivation calls a lispDependencies list (see `lispDependencies`
    # below) -- flattening every sibling into this repository's own list
    # would not reach a nested build. See DEPENDENCY_POLICY.md's L1 table.
    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.4.0";
      flake = false;
    };

    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.3.0";
      flake = false;
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.2.0";
      flake = false;
    };

    # Unlike the sibling *packages* above, this is consumed for its `lib`
    # output (`mkLintCheck`), which a `flake = false` source tree cannot
    # provide -- the same reason cl-cli keeps it a real flake input.
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      cl-tty-kit,
      cl-cli,
      cl-codec-kit,
      cl-host-kit,
      cl-weave,
      paredit-cli,
      treefmt-nix,
    }:
    let
      # x86_64-linux is what CI gates; aarch64-darwin is the development
      # machine. Every per-system output -- packages, checks, apps AND devShells
      # -- comes from this one list, so leaving aarch64-darwin out takes `nix
      # build` and `nix develop` off the development machine as well. That trade
      # was made on 2026-08-01 and reverted on 2026-08-02; aarch64-darwin carries
      # no CI gate, which PACKAGE_STANDARD.md's "systems" section accepts
      # explicitly. aarch64-linux and x86_64-darwin are nobody's verification and
      # are not declared.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
    in
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;

      pname = "cl-asciiquarium";

      # Single source of truth for the version: the `:version` form in
      # cl-asciiquarium.asd.
      asd = ./cl-asciiquarium.asd;

      root = ./.;

      meta = {
        description = "An original ASCII-art aquarium screensaver for the terminal.";
        homepage = "https://github.com/nerima-lisp/cl-asciiquarium";
        license = nixpkgs.lib.licenses.mit;
        platforms = nixpkgs.lib.platforms.unix;
        mainProgram = "asciiquarium";
      };

      # Runtime dependencies: cl-asciiquarium's own :DEPENDS-ON. These are
      # BUILT DERIVATIONS, not CL_SOURCE_REGISTRY strings -- cl-nix-forge
      # assembles the registry transitively from them. cl-tty-kit and cl-cli
      # each need one further sibling of their own (cl-codec-kit,
      # cl-host-kit respectively); each nested lispDerivation call gets its
      # OWN lispDependencies for the same reason this list exists at all --
      # see the flake input comment above.
      lispDependencies =
        ctx:
        let
          codecKit = ctx.cl.lispDerivation {
            pname = "cl-codec-kit";
            version = ctx.cl.fromAsdSystem "${cl-codec-kit}/cl-codec-kit.asd";
            src = cl-codec-kit;
            lispSystem = "cl-codec-kit";
          };
          hostKit = ctx.cl.lispDerivation {
            pname = "cl-host-kit";
            version = ctx.cl.fromAsdSystem "${cl-host-kit}/cl-host-kit.asd";
            src = cl-host-kit;
            lispSystem = "cl-host-kit";
          };
        in
        [
          (ctx.cl.lispDerivation {
            pname = "cl-tty-kit";
            version = ctx.cl.fromAsdSystem "${cl-tty-kit}/cl-tty-kit.asd";
            src = cl-tty-kit;
            lispSystem = "cl-tty-kit";
            lispDependencies = [ codecKit ];
          })
          (ctx.cl.lispDerivation {
            pname = "cl-cli";
            version = ctx.cl.fromAsdSystem "${cl-cli}/cl-cli.asd";
            src = cl-cli;
            lispSystem = "cl-cli";
            lispDependencies = [ hostKit ];
          })
        ];

      # Test-only: cl-weave (the test framework) plus cl-tty-kit again, since
      # t/input-test.lisp calls cl-tty-kit:decode-input directly (see
      # t/package.lisp). cl-tty-kit is already a runtime dependency above;
      # ASDF's own :depends-on on cl-asciiquarium/test is what makes it visible
      # there too, this just gives the check derivation the same tree.
      lispCheckDependencies = ctx: [
        (ctx.cl.lispDerivation {
          pname = "cl-weave";
          version = ctx.cl.fromAsdSystem "${cl-weave}/cl-weave.asd";
          src = cl-weave;
          lispSystem = "cl-weave";
        })
      ];

      # The delivered `asciiquarium` binary: packages.default, apps.default,
      # and apps.cl-asciiquarium, all built from the :build-operation /
      # :build-pathname / :entry-point already declared in
      # cl-asciiquarium.asd -- nothing here repeats them. installSource lets
      # the delivered binary find its own installed ASDF sources when it
      # needs to re-resolve itself; see cl-weave/flake.nix, whose comment on
      # this option this follows.
      executable = {
        installSource = true;
      };

      docs.root = ./docs;

      # ONE treefmt evaluation drives both `nix fmt` and `checks.formatting`.
      # Scope stays the preset's default of Nix only.
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      # Granularity lives here, not in an extra GitHub Actions job: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching -- see cl-cli's flake.nix, which this follows.
      extraOutputs = ctx: {
        checks =
          # paredit-cli's latest tagged release (v1.4.0, pinned above) has not
          # cut a release carrying aarch64-darwin in its own `systems` list yet
          # -- that support exists only on its main branch so far, and
          # DEPENDENCY_POLICY.md's "姉妹パッケージは flake = false で引きます"
          # rule pins every sibling to a release tag, never a branch. Guard
          # this one check on the sibling actually publishing it for
          # ctx.system, rather than reverting cl-asciiquarium's own `systems`
          # list: `nix build` / `nix develop` and every other check are
          # unaffected on aarch64-darwin, and this check reappears with no
          # further change here once paredit-cli tags a release that has it.
          (
            if paredit-cli.lib ? ${ctx.system} then
              {
                # Structural parse gate over every Lisp source in the filtered
                # tree: fails if any .lisp/.asd file is not a balanced S-expression
                # document. The test suite would not catch it -- an unbalanced file
                # makes ASDF fail to load the system, which reads like any other
                # build error and points at the wrong cause.
                paredit-lint = paredit-cli.lib.${ctx.system}.mkLintCheck {
                  inherit (ctx) src;
                  name = "cl-asciiquarium-paredit-lint";
                };
              }
            else
              { }
          )
          // {
            # An sb-cover HTML coverage report for src/, as a buildable
            # artifact rather than a pass/fail gate: `nix build
            # .#checks.<system>.coverage --no-link --print-out-paths` prints a
            # store path whose cover-index.html is the report to open. No
            # minimum-coverage threshold -- see cl-nix-forge's
            # lib/batteries/coverage.nix for why one would gate on the wrong
            # thing here (sb-cover's raw expression percentage under-attributes
            # top-level defstruct/define-condition forms by design).
            coverage = ctx.cl.mkCoverageReport {
              drv = ctx.package;
              systems = [ "cl-asciiquarium" ];
              name = "cl-asciiquarium-coverage";
              timeoutSeconds = 900;
            };
          };
      };
    };
}
