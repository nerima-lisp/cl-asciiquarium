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
      url = "github:nerima-lisp/cl-nix-forge/v0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sibling packages are ALWAYS pinned to a release tag; a bare
    # `github:nerima-lisp/<pkg>` follows that repo's default branch, which
    # would break this repo's CI without warning the moment upstream pushes
    # to main. `flake = false`: only the source tree is needed (to build a
    # `lispDerivation` below), never these repos' own flake outputs -- see
    # DEPENDENCY_POLICY.md "姉妹パッケージは flake = false で引きます".
    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.1.0";
      flake = false;
    };

    cl-cli = {
      url = "github:nerima-lisp/cl-cli/v1.1.0";
      flake = false;
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.1.0";
      flake = false;
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
      cl-weave,
      treefmt-nix,
    }:
    let
      # CI builds and tests only x86_64-linux, so that is the sole declared
      # system. See PACKAGE_STANDARD.md, section "systems", for the 2026-08-01
      # decision this follows and the consequence it accepts (no `nix develop`
      # / `nix build` on macOS).
      systems = [
        "x86_64-linux"
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
      # assembles the registry transitively from them.
      lispDependencies = ctx: [
        (ctx.cl.lispDerivation {
          pname = "cl-tty-kit";
          version = ctx.cl.fromAsdSystem "${cl-tty-kit}/cl-tty-kit.asd";
          src = cl-tty-kit;
          lispSystem = "cl-tty-kit";
        })
        (ctx.cl.lispDerivation {
          pname = "cl-cli";
          version = ctx.cl.fromAsdSystem "${cl-cli}/cl-cli.asd";
          src = cl-cli;
          lispSystem = "cl-cli";
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
    };
}
