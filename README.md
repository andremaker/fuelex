# Fuelex

A Phoenix 1.8 / LiveView mission fuel calculator. No database or external services
are required. Enter spacecraft mass in kilograms and a chronological itinerary,
or load an Apollo 11, Mars, or Passenger Ship preset.

## Run

```sh
mix setup
mix phx.server
```

Open http://localhost:4000. Run `mix precommit` for compilation with warnings as
errors, dependency checks, formatting, and tests. Run `mix assets.build` to build
CSS and JavaScript.

## Domain API

```elixir
Fuelex.Fuel.maneuver(28_801, {:land, :earth})
# {:ok, 13447}

Fuelex.Fuel.mission(28_801, [
  {:launch, :earth}, {:land, :moon}, {:launch, :moon}, {:land, :earth}
])
# {:ok, 51898}
```

Both functions accept positive numeric mass and return `{:ok, fuel_in_kg}` or
`{:error, reason}`. Actions are `:launch` and `:land`; worlds are `:earth`, `:moon`,
and `:mars`, with gravity 9.807, 1.62, and 3.711 respectively. Invalid mass,
unsupported/malformed steps, and non-list missions are rejected. An empty domain
mission requires zero fuel; the UI requires at least one maneuver. The calculator
validates supported steps, without imposing additional itinerary constraints.

Launch uses `floor(mass * gravity * 0.042 - 33)` and landing uses
`floor(mass * gravity * 0.033 - 42)`. Each maneuver repeats its formula on the
previous fuel requirement, adding positive results until the next is nonpositive.
Integer masses use scaled integer constants to preserve exact decimal arithmetic
at floor boundaries. Fractional masses are accepted too.

A mission folds its steps backwards. Each earlier maneuver carries spacecraft
mass plus all fuel already calculated for later maneuvers. Calculation lives in
`Fuelex.Fuel`, independently of Phoenix; LiveView handles form parsing and display.

| Acceptance scenario | Spacecraft mass | Departure fuel |
| --- | ---: | ---: |
| Apollo 11 | 28,801 kg | 51,898 kg |
| Mars | 14,606 kg | 33,388 kg |
| Passenger Ship | 75,432 kg | 212,161 kg |

## Iteration versus a continuous model

For one maneuver, let `a = gravity * coefficient` and `b` be the subtraction
constant. The required recurrence is `x[k+1] = floor(a*x[k] - b)`, with `x[0]`
equal to carried mass. All supported factors satisfy `0 < a < 1`, so it terminates
in O(log mass) iterations using a tail-recursive accumulator.

Without intermediate flooring, the recurrence would instead give
`x[k] = a^k * (mass + b/(1-a)) - b/(1-a)`. Its positive terms can be summed as a
finite geometric series, but that is a different model: flooring the final sum
cannot recover the floors at each step. Mission composition also propagates
these differences backwards. The required iterative implementation remains the
source of truth. No benchmark or continuous alternative is included; there is
no demonstrated performance need to justify the extra implementation.
