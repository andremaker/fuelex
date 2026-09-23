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

  test "Apollo 11 acceptance scenario" do
    assert Fuel.calculate_for_departure(28_801, @apollo) == {:ok, 51_898}
  end

  test "Mars acceptance scenario" do
    assert Fuel.calculate_for_departure(14_606, @mars) == {:ok, 33_388}
  end

  test "Passenger Ship acceptance scenario" do
    assert Fuel.calculate_for_departure(75_432, @passenger) == {:ok, 212_161}
  end

  test "single landing includes fuel for its own fuel" do
    assert Fuel.calculate_for_action(28_801, {:land, :earth}) == {:ok, 13_447}
  end

  test "floors each recurrence rather than only the final sum" do
    # 1000 -> 378 -> 122 -> 17 -> negative
    assert Fuel.calculate_for_action(1000, {:launch, :earth}) == {:ok, 517}
  end

  test "stops at zero and negative additional fuel required" do
    assert Fuel.calculate_for_action(1, {:launch, :earth}) == {:ok, 0}
    assert Fuel.calculate_for_action(500, {:launch, :moon}) == {:ok, 1}
    assert Fuel.calculate_for_action(499, {:launch, :moon}) == {:ok, 0}
  end

  test "supports positive fractional mass" do
    assert Fuel.calculate_for_action(1000.5, {:launch, :earth}) == {:ok, 519}
  end

  test "earlier actions carry later fuel and order matters" do
    assert Fuel.calculate_for_departure(1000, launch: :earth, land: :moon) == {:ok, 536}
    assert {:ok, launch_first} = Fuel.calculate_for_departure(1000, launch: :earth, land: :earth)
    assert {:ok, land_first} = Fuel.calculate_for_departure(1000, land: :earth, launch: :earth)
    assert launch_first != land_first
  end

  test "empty flights and single-action flights" do
    assert Fuel.calculate_for_departure(1000, []) == {:ok, 0}

    assert Fuel.calculate_for_departure(1000, launch: :earth) ==
             Fuel.calculate_for_action(1000, {:launch, :earth})
  end

  test "rejects invalid masses even for empty flights" do
    for mass <- [0, -1, -0.5, "", "1000", nil, :earth] do
      assert Fuel.calculate_for_action(mass, {:launch, :earth}) == {:error, :invalid_mass}
      assert Fuel.calculate_for_departure(mass, []) == {:error, :invalid_mass}
      assert Fuel.calculate_for_departure(mass, @apollo) == {:error, :invalid_mass}
    end
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

  test "accepts either endpoint action" do
    for actions <- [
          [land: :earth],
          [launch: :earth],
          [land: :earth, launch: :earth],
          [land: :earth, launch: :earth, land: :moon],
          [launch: :earth, land: :moon, launch: :moon]
        ] do
      assert {:ok, fuel} = Fuel.calculate_for_departure(1000, actions)
      assert is_integer(fuel)
    end
  end

  test "rejects unsupported actions, worlds, and malformed actions" do
    for action <- [{:orbit, :earth}, {:launch, :venus}, {"launch", "earth"}, :launch, {}] do
      assert Fuel.calculate_for_action(1000, action) == {:error, :invalid_action}

      assert Fuel.calculate_for_departure(1000, [{:launch, :earth}, action]) ==
               {:error, :invalid_action}
    end

    assert Fuel.calculate_for_departure(1000, nil) == {:error, :invalid_actions}
  end
end
