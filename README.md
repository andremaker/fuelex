# Fuelex

Fuelex is a Phoenix LiveView application for calculating the fuel required for space flights based on spacecraft mass, route, launch/landing actions, and planetary gravity.

## Table of Contents

* [Requirements](#requirements)
* [Setup and Run](#setup-and-run)
* [Usage](#usage)
* [Tests](#tests)
* [Architecture](#architecture)
* [Technical Notes](#technical-notes)
* [EXERCISE NOTES](#exercise-notes)

  * [Considerations](#considerations)

    * [NASA-inspired visual direction](#nasa-inspired-visual-direction)
    * [AI-generated code](#ai-generated-code)
    * [Testing strategy](#testing-strategy)
    * [Replacement of iteration with a formula](#replacement-of-iteration-with-a-formula)
    * [Formula questions](#formula-questions)

      * [Zero-fuel boundary](#zero-fuel-boundary)
      * [Intermediate flooring](#intermediate-flooring)
    * [Combined route-point action](#combined-route-point-action)
    * [Landing as initial action and non-Earth departure](#landing-as-initial-action-and-non-earth-departure)
  * [Suggestions](#suggestions)

    * [Per-step fuel breakdown](#per-step-fuel-breakdown)
    * [Route import/export](#route-importexport)

## Requirements

* Elixir
* Erlang/OTP
* Mix

## Setup and Run

Install dependencies and prepare the project:

```bash
mix setup
```

Start the Phoenix server:

```bash
mix phx.server
```

Then open:

```text
http://localhost:4000
```

## Usage

Enter the spacecraft mass, choose the initial action and world, and add route points to build the flight path.

Fuelex recalculates the required fuel automatically as the route or mass changes.

Supported actions:

* `:launch`
* `:land`

Supported worlds:

* `:earth`
* `:moon`
* `:mars`

## Tests

Run the test suite with:

```bash
mix test
```

Run the complete project checks with:

```bash
mix precommit
```

## Architecture

`Fuelex.Fuel` contains the fuel-calculation logic and domain validation and is independent of Phoenix.

`FuelexWeb.FlightLive` owns application state, form handling, route-building behavior, and translation of the UI representation into explicit flight actions.

`FuelexWeb.FlightComponents` contains reusable, stateless presentation components specific to the flight interface.

The UI works with route points for easier route construction, while the calculation layer works with explicit launch and landing actions.

## Technical Notes

Fuel required for later actions is carried through earlier actions, so complete flight paths are calculated backwards.

Each maneuver also accounts for the fuel required to carry its own fuel, repeating the corresponding formula until the next calculated fuel requirement is nonpositive.

## EXERCISE NOTES

### Considerations

#### Usage context

The exercise defines the calculation itself, but not the operational context in which the application would be used. In a real project, I would clarify at least:

- expected number of users and simultaneous accesses;
- whether results are only rough estimates or may feed real engineering decisions;
- whether future integrations with other systems are expected;
- whether calculations need to be persisted, shared, reproduced, or audited;
- whether domain data such as formulas, supported worlds, or parameters is expected to change.

These answers could materially affect decisions around numerical precision, validation, APIs, persistence, scalability, observability, deployment, and the overall domain model.

#### NASA-inspired visual direction

I reviewed a few NASA websites to find a visual direction that felt appropriate for the application, and the NASA Software Catalog became the main reference because it captured the broader visual language shared across them. I deliberately avoided using NASA’s space-simulation tools as the primary reference, since their darker and even more minimal interfaces are designed to preserve the atmosphere of viewing space itself. For a practical calculation tool, I considered the lighter, more conventional scientific-tool style a better fit.

#### AI-generated code

My previous stance was to avoid shipping significant amounts of AI-generated code to production, using it mainly for prototyping. The newest tooling changed that stance somewhat. This was my first time using Astra for frontend work, and the initial generation, which I expected to be only a prototype, produced surprisingly strong results and responded effectively to visual and UX feedback. I decided to keep iterating on it, and through extensive trial and error it proved to be a very effective approach for this scenario in terms of final quality. That gave me enough confidence to retain most of the AI-generated frontend, with extra careful review and adjustments, rather than rebuilding it from scratch for the final result. I still kept a more conservative AI-assisted approach to backend internals.

#### Testing strategy

Tests intentionally focus on calculation correctness using the provided examples and on the main UI behaviors rather than exhaustive implementation-detail coverage.

#### Replacement of iteration with a formula

Looking at the recursive calculation, one thing that immediately came to mind was whether it could be replaced with a geometric closed-form solution. In practice, however, the iterative approach already converges extremely quickly because each step reduces the value by a constant factor, giving it logarithmic step growth (even 1 billion kg takes only about 18 iterations). A closed-form implementation would therefore add mathematical and implementation complexity without providing a meaningful computational benefit. The required intermediate flooring would make deriving an exact equivalent formula even more complex, further weakening the case for replacing the simple iterative solution.

#### Formula questions

Even though the formula is evidently a fictional simplification for the classical "tyranny of the rocket equation" for exercise purposes, there are still a few details that called my attention and could be relevant in a real scenario:

- Zero-fuel boundary - The specification allows the calculation to return `0 kg` of fuel when the first application of the formula is already nonpositive.

- Intermediate flooring - The formula applies `floor` at every recursive step, instead of only at the final result as usual, meaning each truncated value becomes the input to the next calculation. It does not seem to correspond naturally to the underlying physical behavior and could instead be an oversight in the specification. Repeatedly discarding fractional values compounds the loss of precision across iterations and can considerably affect the final fuel requirement.

I followed the requirements as written in the current implementation because both was straightforward to support, but in a real scenario I would clarify whether this they are intentional before considering the job done.

#### Combined route-point action

I chose to use a single “Add route point” control instead of requiring users to add landing and launch actions separately. Adding another route point automatically inserts the expected launch from the current world, reducing repetitive interaction and making route construction faster. The backend still keeps them as separate explicit actions so the calculation model remains simple, flexible, and independent of the UI abstraction. The first- and last-action controls preserve customization at the route boundaries, where that automatic pairing does not necessarily apply. I also visually grouped landing and launch for each route point in the action list, making the sequence easier to understand while using less space.

#### Consecutive identical route points

The current route model allows returning to the same world multiple times, including back-and-forth routes between the same planets. This is mechanically valid for the calculator, but the intended meaning of repeated visits to the same world is not explicitly defined in the requirements, so I would confirm whether that behavior is expected in a real project.

#### Fractional spacecraft mass

The calculation accepts fractional spacecraft mass, although the repeated use of `floor` means sub-kilogram precision is progressively discarded during the recursive calculation. That makes fractional input less significant in practice, but I would still verify whether mass is intended to support decimals or only whole kilograms.


#### Landing as initial action and non-Earth departure

The requirements do not clearly establish that fueling must happen on Earth or immediately before a launch, so I did not constrain the first action to always be `launch` or the initial world to always be Earth. While that may seem unusual at first, space-based refueling already exists in limited forms and is expected to become more relevant over time, so a modeled flight could legitimately begin after fueling in orbit and have `land` as its first surface action. Enforcing “flight must start with launch from Earth” would therefore introduce a constraint that is not stated in the requirements. In case it should in fact be supported, it brings a related modeling question: if departure occurs from an orbital station or another off-surface location, how that departure should be represented when `launch` is defined using a planet’s surface gravity. In a real project, I would clarify the assumed fueling location and how off-surface departures should be modeled before considering the behavior complete.

#### NASA branding

Although the exercise places the developer in the role of a NASA contractor, NASA’s branding guidelines do not allow contractors to use NASA identifiers simply because they are working for the agency. Public use of the NASA Insignia (“meatball”), Logotype (“worm”), Seal, and other NASA emblems requires prior NASA review and approval, and contractor use must not imply sponsorship or endorsement beyond what has actually been authorized.

For that reason, I kept the initial Fuelex branding neutral and easily replaceable rather than assuming permission to use official NASA branding. In a real engagement, I would obtain the approved assets and usage guidance before introducing NASA identifiers into the application.


### Suggestions
A few suggestions I would give in a real scenario.

#### Per-step fuel breakdown

Showing the fuel contribution of each individual maneuver would make the result more useful for planning and comparison, while also making the impact of route changes easier to understand. It would also provide a better foundation for future features such as space refueling or handling mass changes from stage separation and payload delivery/retrieval.

#### Route import/export

Supporting route editing through a text input would enable import and export, which could save engineers time since routes are likely to already be produced by other software in a textual form.
