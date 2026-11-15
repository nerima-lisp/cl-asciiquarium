# Roadmap

This page lists implemented features and explicit out-of-scope designs.

## Current scope

- Sixteen original fish species (`+FISH-SPECIES+`, `src/art-fish-data.lisp`)
  use multi-line, direction-mirrored art and color palettes. Fish of the same
  species can lay eggs that grow through fry; schools of six scatter from
  threats, puffers inflate, and fish emit bubbles. `e` or a left click adds
  food that nearby fish can eat.
- Threat interactions include the shark, lantern fish, courting fish, food,
  fisher's hook, landed anchor, submarine hull and sonar, vent plume, octopus
  tentacle, and a diving gull's body. Eaten or caught fish are later replaced
  by newly spawned fish that enter from a screen edge.
- The seabed has seaweed, a castle, coral, a rock, a starfish, a vent, a crab,
  an octopus, and a treasure chest. A ship lowers an anchor; a diver visits
  the chest in a dinghy.
- Visitors include ships, divers, fishers, gulls, a line of ducks, a leaping
  dolphin, and a segmented sea monster. Automatic guest events count ships,
  submarines, divers' dinghies, and fishers; at most two such events can be
  on screen at once. The `g`, `a`, `m`, `d`, and `f` keys can spawn guests on
  demand regardless of that limit.
- Weather cycles through clear, rain, and storm. Time of day cycles through
  day, dusk, and night; night has denser glowing plankton. `w` and `n` advance
  those cycles, and `--calm` stops the storm's lightning flash.
- Three visual themes (`:abyss`, `:coral`, and `:moonlight`) can be cycled
  with `t`. The ambient current and a status bar share the scene; `u` toggles
  the status bar.
- `q`/Ctrl-C quits, `r` redraws the fish, space pauses or resumes, `+`/`-`
  changes the target fish count, `s` spawns a shark, `c` spawns a school, `h`
  toggles help, and `z` toggles the fish dex. Terminal resizing is polled while
  the aquarium runs.
- The fish dex remembers discovered species between runs in
  `$XDG_STATE_HOME/cl-asciiquarium/zukan.sexp`, or
  `~/.local/state/cl-asciiquarium/zukan.sexp` when `$XDG_STATE_HOME` is unset,
  empty, or relative. `p` saves a text snapshot in an absolute
  `$XDG_PICTURES_DIR`, or in the current directory when that variable is unset,
  empty, or relative.
- `--color auto|truecolor|256|16|mono` chooses color depth
  (`--monochrome` is the same as `--color mono`), and `--ascii` draws only
  ASCII symbols. `--theme abyss|coral|moonlight` selects the starting theme;
  `--no-daycycle` disables automatic time-of-day changes, and `--no-shark`
  disables the shark.

## Out of scope

- A general NxN interaction matrix. Each threat kind declares its interaction
  in a `:THREAT` row (the shark's mouth, a landed anchor, a lantern fish's
  light, a courting fish, food, the fisher's hook, a diving gull's body, the
  submarine hull or sonar rings, the vent's plume, or the octopus tentacle),
  and `src/collision.lisp` checks them in one
  threats × creatures pass; no creature is tested against every other one. The
  dolphin, sea monster, and duck line are decorative.
- A generic ECS or config-driven guest-definition DSL. Creatures are plain
  `CREATURE` structs built by plain Lisp functions.

