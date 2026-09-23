defmodule Fuelex.FuelTest do
  use ExUnit.Case, async: true

  alias Fuelex.Fuel

  @apollo [launch: :earth, land: :moon, launch: :moon, land: :earth]
  @mars [launch: :earth, land: :mars, launch: :mars, land: :earth]
  @passenger [
    launch: :earth,
    land: :moon,
    launch: :moon,
    land: :mars,
    launch: :mars,
    land: :earth
  ]


  test "calculates action according to example scenario" do
    assert Fuel.calculate_for_action(28801, {:land, :earth}) == {:ok, 13447}
  end

  test "calculates correctly for single-action flights" do
    assert Fuel.calculate_for_departure(28801, launch: :earth) ==
             Fuel.calculate_for_action(28801, {:launch, :earth})
  end

  test "calculates total fuel for complex flights according to example scenarios" do
    scenarios = [
      {"Apollo 11", 28_801, @apollo, 51_898},
      {"Mars", 14_606, @mars, 33_388},
      {"Passenger Ship", 75_432, @passenger, 212_161}
    ]

    for {scenario, mass, actions, expected_fuel} <- scenarios do
      assert Fuel.calculate_for_departure(mass, actions) == {:ok, expected_fuel},
            "#{scenario} fuel calculation failed"
    end
  end

  test "earlier actions carry later fuel and order matters" do
    assert Fuel.calculate_for_departure(1000, launch: :earth, land: :moon) == {:ok, 536}
    assert {:ok, launch_first} = Fuel.calculate_for_departure(1000, launch: :earth, land: :earth)
    assert {:ok, land_first} = Fuel.calculate_for_departure(1000, land: :earth, launch: :earth)
    assert launch_first != land_first
  end

  test "rejects invalid consecutive actions and departures from another world" do
    for actions <- [
          [launch: :earth, launch: :moon],
          [land: :earth, land: :moon],
          [land: :moon, launch: :earth],
          [launch: :earth, land: :moon, launch: :mars],
          [launch: :earth, land: :moon, land: :mars]
        ] do
      assert Fuel.calculate_for_departure(1000, actions) == {:error, :invalid_sequence}
    end
  end

  test "rejects unsupported actions, worlds, and malformed actions" do
    for action <- [{:orbit, :earth}, :launch, {}] do
      assert Fuel.calculate_for_action(1000, action) == {:error, :invalid_action}

      assert Fuel.calculate_for_departure(1000, [{:launch, :earth}, action]) ==
               {:error, :invalid_action}
    end

    action_invalid_world = {:launch, :venus}
    assert Fuel.calculate_for_action(1000, action_invalid_world) == {:error, :invalid_world}
    assert Fuel.calculate_for_departure(1000, [action_invalid_world]) == {:error, :invalid_world}

    assert Fuel.calculate_for_departure(1000, nil) == {:error, :invalid_actions}
  end
end
