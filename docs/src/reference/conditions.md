# Conditions

Every error `cl-asciiquarium` signals descends from a single base,
`asciiquarium-error`, defined in `src/conditions.lisp`. Catch that one type to
handle any library error; catch a specific subtype to inspect the structured
slots a caller needs to react to it programmatically instead of parsing the
formatted `:report` message.

## Hierarchy

```text
error
└── asciiquarium-error                  (base for everything below)
    ├── asciiquarium-invalid-dimensions
    ├── asciiquarium-unknown-species
    └── asciiquarium-invalid-policy
```

## `asciiquarium-error`

The abstract base condition. It has no slots; its only role is to give every
condition below a common supertype, so `(handler-case ... (asciiquarium-error
(e) ...))` catches all of them at once.

## `asciiquarium-invalid-dimensions`

Raised when a world's width or height is not a positive integer.

| Slot | Reader | Value |
| --- | --- | --- |
| width | `invalid-dimensions-width` | the rejected width |
| height | `invalid-dimensions-height` | the rejected height |

Signaled by `make-world` and `world-resize` when given a non-positive width or
height.

## `asciiquarium-unknown-species`

Raised when a fish species name is not recognized.

| Slot | Reader | Value |
| --- | --- | --- |
| name | `unknown-species-name` | the unrecognized species name |

Signaled by `make-fish` when asked for a species outside the five it knows
(`:dart`, `:puffer`, `:ribbon`, `:angel`, `:guppy`).

## `asciiquarium-invalid-policy`

Raised when a creature's off-bounds policy is not one of the three recognized
keywords.

| Slot | Reader | Value |
| --- | --- | --- |
| policy | `invalid-policy-policy` | the rejected policy value |

Signaled by `make-creature` when its `:policy` argument is anything other than
`:wrap`, `:despawn`, or `:none`. See [Off-bounds policy](architecture.md#off-bounds-policy)
for what each of the three does.

## See also

- [API Reference](api.md) -- the full exported symbol list in context
- [Architecture](architecture.md) -- the `creature`/`policy` contract these
  conditions guard
