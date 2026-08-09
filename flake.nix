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
      url = "github:nerima-lisp/cl-nix-forge/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sibling packages are ALWAYS pinned to a release tag; a bare
    # `github:nerima-lisp/<pkg>` follows that repo's default branch, which
    # would break this repo's CI without warning the moment upstream pushes
    # to main. `flake = false`: only the source tree is needed (to build a
    # `lispDerivation` below), never these repos' own flake outputs -- see
    # DEPENDENCY_POLICY.md "姉妹パッケージは flake = false で引きます".
    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.6.1";
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
      url = "github:nerima-lisp/cl-codec-kit/v0.5.0";
      flake = false;
    };

    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.3.1";
      flake = false;
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      flake = false;
    };

    # cl-concurrent-kit is a runtime sibling package; its release flake
    # publishes the complete package and its transitive runtime dependencies.
    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.6.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # Unlike the sibling *packages* above, this is consumed for its `lib`
    # output (`mkLintCheck`), which a `flake = false` source tree cannot
    # provide -- the same reason cl-cli keeps it a real flake input.
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.5.0";
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
      cl-concurrent-kit,
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
            pname = "cl-cli-host-kit";
            version = ctx.cl.fromAsdSystem "${cl-host-kit}/cl-host-kit.asd";
            src = cl-host-kit;
            lispSystem = "cl-host-kit";
          };
        in
        [
          # cl-concurrent-kit is published as a sibling mkPackageFlake package,
          # so retain its complete runtime dependency graph.
          cl-concurrent-kit.packages.${ctx.system}.cl-concurrent-kit
          (ctx.cl.lispDerivation {
            pname = "cl-tty-kit";
            version = ctx.cl.fromAsdSystem "${cl-tty-kit}/cl-tty-kit.asd";
            src = cl-tty-kit;
            lispSystem = "cl-tty-kit";
            lispDependencies = [
              codecKit
              cl-concurrent-kit.packages.${ctx.system}.cl-concurrent-kit
            ];
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

        # `pname`, because cl-nix-forge's mkExecutable derives BOTH the
        # installed `$out/bin/<name>` and `meta.mainProgram` from
        # `args.pname or lispSystem` (lib/batteries/app.nix `outputName`),
        # and the `mainProgram` declared in `meta` above is overwritten by
        # it unconditionally. Without this the delivered command is
        # `cl-asciiquarium`, contradicting the `:build-pathname` in the .asd
        # and every `./result/bin/asciiquarium` in README.md and docs/.
        pname = "asciiquarium";

        # `programPath`, because mkExecutable's non-Darwin (program-op) path
        # looks for the built program at `$out/<lispSystem>` unless told
        # otherwise, and ASDF does not write it there. `:build-pathname
        # "asciiquarium"` is merged against the system's own `:pathname
        # "src"`, not against the .asd's directory, so `asdf:output-files`
        # for program-op reports `<source-root>/src/asciiquarium` -- verify
        # with `nix develop --command sbcl` and
        # `(asdf:output-files (asdf:make-operation 'asdf:program-op)
        #  (asdf:find-system "cl-asciiquarium"))`. Unused on the Darwin
        # save-lisp-and-die fallback, which never reads it.
        programPath = "src/asciiquarium";
      };

      docs.root = ./docs;

      # ONE treefmt evaluation drives both `nix fmt` and `checks.formatting`.
      # Scope stays the preset's default of Nix only.
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      # Granularity lives here, not in an extra GitHub Actions job: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching -- see cl-cli's flake.nix, which this follows.
      extraOutputs = ctx: {
        checks = {
          # Structural parse gate over every Lisp source in the filtered tree:
          # fails if any .lisp/.asd file is not a balanced S-expression document.
          paredit-lint = paredit-cli.lib.${ctx.system}.mkLintCheck {
            inherit (ctx) src;
            name = "cl-asciiquarium-paredit-lint";
          };

          # Run the registered suite through cl-weave's public coverage API.
          #
          # The exclusions below are STRUCTURAL. cl-weave resets sb-cover's
          # counters before the suite runs (`coverage-reset` defaults to T --
          # see `prepare-coverage-run` in cl-weave's runner-coverage.lisp), so
          # an expression whose only execution is at LOAD time -- an
          # `in-package`, a top-level `defparameter` -- is wiped before any
          # test can mark it. A file that is almost nothing but such forms
          # reports a ceiling no test can raise, and gating on it would
          # penalise this repository for something unreachable rather than
          # something untested.
          #
          # That is the whole criterion, and it is checkable: exclude a file
          # only when its expressions cannot be reached from a test AT ALL,
          # never because the tests have not been written yet. Load a file's
          # system and report coverage before running anything -- if the
          # number moves once tests run, the file is reachable and belongs in
          # the measured set. src/bubble-data.lisp sat in this list until its
          # themed-prototype cache turned out to hold live branching that no
          # test exercised; it is measured now.
          coverage = ctx.cl.mkCoverageReport {
            drv = ctx.package;
            systems = [ "cl-asciiquarium" ];
            entryPointText = ''
              (require "asdf")
              (asdf:load-system "cl-asciiquarium/test")
              (uiop:symbol-call
               :cl-asciiquarium/test
               :run-tests
               :coverage t
               :coverage-minimum-expression 88
               :coverage-minimum-branch 90
               :coverage-exclude-pathnames
               '("src/art-decor-data.lisp"
                 "src/art-fish-data.lisp"
                 "src/art-guests-data.lisp"
                 "src/package.lisp"))
            '';
            name = "cl-asciiquarium-coverage";
            timeoutSeconds = 900;
          };
        };
      };
    };
}
