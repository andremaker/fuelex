# Fuelex

Fuelex is a Phoenix 1.8 / LiveView space-travel fuel calculator. It has no database or Ecto dependency.

## Workflow

* Run `mix precommit` after completing a change and fix any failures.
* Prefer focused changes. Do not perform unrelated cleanup or refactoring.
* Do not add dependencies unless they provide a clear benefit that cannot reasonably be achieved with the existing stack.
* Preserve existing DOM IDs, event names, behavior, accessibility, and visual appearance during refactors unless the task explicitly requires changing them.
* Do not update the README unless explicitly requested. It is finalized after the implementation stabilizes.

## Architecture

* `Fuelex.Fuel` owns fuel calculation and domain-level validation.
* `FuelexWeb.FlightLive` owns LiveView state, form handling, route-builder behavior, and conversion from UI state to explicit actions.
* `FuelexWeb.FlightComponents` owns reusable, stateless flight-specific presentation.
* Prefer function components over `Phoenix.LiveComponent` unless independent component state/lifecycle is genuinely needed.
* Do not introduce a Phoenix context merely to wrap `Fuelex.Fuel`; this application has no persistence subsystem requiring one.

### Route builder boundary

The domain API works with explicit `{action, world}` steps.

The UI exposes a higher-level route builder using ordered route points plus first/last action choices. `FlightLive` expands that compressed UI representation into explicit actions.

This expansion is UI/application behavior, not fuel-domain logic. Do not move it into `Fuelex.Fuel`.

Route points are ordered occurrences at worlds. Consecutive route points may refer to the same world.

Do not invent itinerary constraints that are not established by the exercise requirements.

## Fuel calculation

Supported actions are `:launch` and `:land`.

Supported worlds are Earth, Moon, and Mars.

Fuel required for later actions contributes to the mass carried through earlier actions, so a flight is calculated backwards through its explicit action sequence.

For each action, the fuel-for-fuel recurrence must apply `floor` on every iteration and stop when the next required fuel is nonpositive. Do not replace this with a continuous/geometric approximation.

## UI components

`world/1` owns the visual identity of Earth, Moon, and Mars, including their icon and color. Do not duplicate those mappings elsewhere.

`route_point/1` owns presentation of one route point and its actions. Route state and event handling remain in `FlightLive`.

Do not split planner, route, or result sections into components solely to reduce file size. Extract components only when they represent a meaningful reusable UI concept.

## Product and branding

Fuelex currently uses neutral placeholder branding.

The exercise states that the application is for NASA but does not establish permission to use NASA identifiers. Do not add NASA logos or other protected NASA branding unless explicit authorization or approved assets are provided.

The visual direction is a compact, functional scientific/NASA-inspired tool rather than a marketing-style interface.
