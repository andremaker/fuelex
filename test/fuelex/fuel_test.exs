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
    assert Fuel.flight(28_801, @apollo) == {:ok, 51_898}
  end

  test "Mars acceptance scenario" do
    assert Fuel.flight(14_606, @mars) == {:ok, 33_388}
  end

  test "Passenger Ship acceptance scenario" do
    assert Fuel.flight(75_432, @passenger) == {:ok, 212_161}
  end

  test "single landing includes fuel for its own fuel" do
    assert Fuel.maneuver(28_801, {:land, :earth}) == {:ok, 13_447}
  end

  test "floors each recurrence rather than only the final sum" do
    # 1000 -> 378 -> 122 -> 17 -> negative
    assert Fuel.maneuver(1000, {:launch, :earth}) == {:ok, 517}
  end

  test "stops at zero and negative additional fuel required" do
    assert Fuel.maneuver(1, {:launch, :earth}) == {:ok, 0}
    assert Fuel.maneuver(500, {:launch, :moon}) == {:ok, 1}
    assert Fuel.maneuver(499, {:launch, :moon}) == {:ok, 0}
  end

  test "supports positive fractional mass" do
    assert Fuel.maneuver(1000.5, {:launch, :earth}) == {:ok, 519}
  end

  test "earlier maneuvers carry later fuel and order matters" do
    assert Fuel.flight(1000, launch: :earth, land: :moon) == {:ok, 536}
    assert {:ok, launch_first} = Fuel.flight(1000, launch: :earth, land: :earth)
    assert {:ok, land_first} = Fuel.flight(1000, land: :earth, launch: :earth)
    assert launch_first != land_first
  end

  test "empty flights and single-step flights" do
    assert Fuel.flight(1000, []) == {:ok, 0}
    assert Fuel.flight(1000, launch: :earth) == Fuel.maneuver(1000, {:launch, :earth})
  end

  test "rejects invalid masses even for empty flights" do
    for mass <- [0, -1, -0.5, "", "1000", nil, :earth] do
      assert Fuel.maneuver(mass, {:launch, :earth}) == {:error, :invalid_mass}
      assert Fuel.flight(mass, []) == {:error, :invalid_mass}
      assert Fuel.flight(mass, @apollo) == {:error, :invalid_mass}
    end
  end

  test "rejects invalid consecutive actions and departures from another world" do
    for steps <- [
          [launch: :earth, launch: :moon],
          [land: :earth, land: :moon],
          [land: :moon, launch: :earth],
          [launch: :earth, land: :moon, launch: :mars],
          [launch: :earth, land: :moon, land: :mars]
        ] do
      assert Fuel.flight(1000, steps) == {:error, :invalid_sequence}
    end
  end

  test "accepts either endpoint action" do
    for steps <- [
          [land: :earth],
          [launch: :earth],
          [land: :earth, launch: :earth],
          [land: :earth, launch: :earth, land: :moon],
          [launch: :earth, land: :moon, launch: :moon]
        ] do
      assert {:ok, fuel} = Fuel.flight(1000, steps)
      assert is_integer(fuel)
    end
  end

  test "rejects unsupported actions, worlds, and malformed steps" do
    for step <- [{:orbit, :earth}, {:launch, :venus}, {"launch", "earth"}, :launch, {}] do
      assert Fuel.maneuver(1000, step) == {:error, :invalid_step}
      assert Fuel.flight(1000, [{:launch, :earth}, step]) == {:error, :invalid_step}
    end

    assert Fuel.flight(1000, nil) == {:error, :invalid_steps}
  end
end
