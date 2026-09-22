defmodule FuelexWeb.FlightLiveTest do
  use FuelexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "starts with mass, independent endpoint selectors, and three world buttons", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#flight-form input[name='flight[mass]'][value='']")
    assert has_element?(view, "#flight_first_action")
    assert has_element?(view, "#flight_last_action")
    assert has_element?(view, "#maneuvers-empty")
    assert has_element?(view, "#fuel-placeholder", "Insert flight data")
    refute has_element?(view, "#flight-error")

    for world <- ~w(earth moon mars) do
      assert has_element?(view, "#add-destiny-#{world}[type='button'][disabled]")
    end
  end

  test "requires a first action before adding worlds and still validates mass", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#flight_first_action option[value=''][disabled]", "Choose action")
    render_click(view, "add-destiny", %{"world" => "earth"})
    assert_steps(view, [])
    change(view, %{mass: "-10"})
    assert has_element?(view, "#flight-error")
    change(view, %{mass: "1000"})
    assert has_element?(view, "#fuel-placeholder", "Choose first action")
    refute has_element?(view, "#flight-error")

    change(view, %{first_action: "land"})
    refute has_element?(view, "#add-destiny-earth[disabled]")
    add_worlds(view, ~w(earth))
    assert_steps(view, land: :earth)
    assert has_element?(view, "#fuel-placeholder", "Choose last action")
    refute has_element?(view, "#fuel-result")
    change(view, %{last_action: "land"})
    assert_fuel(view, 1000, land: :earth)
    change(view, %{first_action: "launch", last_action: "land"})
    assert_steps(view, launch: :earth)
    assert has_element?(view, "#fuel-placeholder", "Add a landing destination")
  end

  test "destinations generate explicit Apollo maneuvers and calculate immediately", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    change(view, %{mass: "28801", first_action: "launch", last_action: "land"})
    add_worlds(view, ~w(earth moon earth))
    assert_steps(view, launch: :earth, land: :moon, launch: :moon, land: :earth)
    assert has_element?(view, "#fuel-result[data-fuel='51898']")
    change(view, %{mass: "1000"})
    assert_fuel(view, 1000, launch: :earth, land: :moon, launch: :moon, land: :earth)
  end

  test "endpoint switches remove leftover actions and final launch follows new destinations", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/")
    change(view, %{mass: "1000", first_action: "land", last_action: "launch"})
    add_worlds(view, ~w(earth moon))
    assert_steps(view, land: :earth, launch: :earth, land: :moon, launch: :moon)
    add_worlds(view, ~w(mars))
    steps = [land: :earth, launch: :earth, land: :moon, launch: :moon, land: :mars, launch: :mars]
    assert_steps(view, steps)
    assert_fuel(view, 1000, steps)

    change(view, %{first_action: "launch"})
    assert_steps(view, launch: :earth, land: :moon, launch: :moon, land: :mars, launch: :mars)
    change(view, %{last_action: "land"})
    assert_steps(view, launch: :earth, land: :moon, launch: :moon, land: :mars)
    change(view, %{first_action: "land"})
    assert_steps(view, land: :earth, launch: :earth, land: :moon, launch: :moon, land: :mars)
    change(view, %{last_action: "launch"})
    assert_steps(view, steps)
  end

  test "launch to land needs a second selected world and recovers after route edits", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/")
    change(view, %{mass: "1000", first_action: "launch", last_action: "land"})
    add_worlds(view, ~w(earth))
    assert_steps(view, launch: :earth)
    assert_incomplete(view)

    add_worlds(view, ~w(moon))
    assert_steps(view, launch: :earth, land: :moon)
    assert_fuel(view, 1000, launch: :earth, land: :moon)
    remove_visit(view, 2)
    assert_steps(view, launch: :earth)
    assert_incomplete(view)

    change(view, %{last_action: "launch"})
    assert_fuel(view, 1000, launch: :earth)
    change(view, %{last_action: "land"})
    assert_incomplete(view)
    change(view, %{first_action: "land"})
    assert_steps(view, land: :earth)
    assert_fuel(view, 1000, land: :earth)
    change(view, %{first_action: "launch"})
    assert_incomplete(view)

    add_worlds(view, ~w(earth))
    assert_steps(view, launch: :earth, land: :earth)
    assert_fuel(view, 1000, launch: :earth, land: :earth)
  end

  test "complete endpoint combinations work with a single world", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    change(view, %{first_action: "launch", last_action: "land"})
    add_worlds(view, ~w(earth))

    for {first, last, steps} <- [
          {"launch", "launch", [launch: :earth]},
          {"land", "launch", [land: :earth, launch: :earth]},
          {"land", "land", [land: :earth]}
        ] do
      change(view, %{mass: "1000", first_action: first, last_action: last})
      assert_steps(view, steps)
      assert_fuel(view, 1000, steps)
    end
  end

  test "removing visits reconnects the route and preserves endpoint choices", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    change(view, %{mass: "1000", first_action: "land", last_action: "launch"})
    add_worlds(view, ~w(earth moon mars))
    remove_visit(view, 3)
    assert_steps(view, land: :earth, launch: :earth, land: :mars, launch: :mars)
    assert_fuel(view, 1000, land: :earth, launch: :earth, land: :mars, launch: :mars)
    remove_visit(view, 4)
    assert_steps(view, land: :earth, launch: :earth)
    add_worlds(view, ~w(moon))
    remove_visit(view, 1)
    assert_steps(view, land: :moon, launch: :moon)
    remove_visit(view, 1)
    assert_steps(view, [])
    assert has_element?(view, "#maneuvers-empty")
    assert has_element?(view, "#fuel-placeholder", "Add actions to your flight")
    refute has_element?(view, "#flight-error")
  end

  test "consecutive repeated worlds are allowed and independently removable", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    change(view, %{first_action: "launch", last_action: "land"})
    add_worlds(view, ~w(moon moon moon))
    assert_steps(view, launch: :moon, land: :moon, launch: :moon, land: :moon)
    remove_visit(view, 2)
    assert_steps(view, launch: :moon, land: :moon)
    remove_visit(view, 1)
    assert_steps(view, launch: :moon)
    remove_visit(view, 1)
    assert_steps(view, [])
  end

  test "missing input stays a prompt while invalid mass stays a form error", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    change(view, %{mass: "1000", first_action: "launch", last_action: "land"})
    assert has_element?(view, "#fuel-placeholder", "Add actions to your flight")
    refute has_element?(view, "#flight-error")

    for mass <- ["0", "-10", "-0.5"] do
      change(view, %{mass: mass})

      assert has_element?(
               view,
               "#flight-form #flight-error",
               "Enter a positive spacecraft mass."
             )
    end

    add_worlds(view, ~w(earth))
    assert has_element?(view, "#flight-error")
    change(view, %{mass: ""})
    assert has_element?(view, "#fuel-placeholder", "Insert spacecraft mass")
    refute has_element?(view, "#flight-error")
    add_worlds(view, ~w(moon))
    assert has_element?(view, "#fuel-placeholder", "Insert spacecraft mass")
    refute has_element?(view, "#fuel-result")
    change(view, %{mass: "1000"})
    assert_fuel(view, 1000, launch: :earth, land: :moon)
    refute has_element?(view, "#flight-error")
  end

  defp assert_incomplete(view) do
    assert has_element?(view, "#fuel-placeholder", "Add a landing destination")
    refute has_element?(view, "#fuel-result")
    refute has_element?(view, "#flight-error")
  end

  defp change(view, params), do: view |> form("#flight-form", flight: params) |> render_change()

  defp add_worlds(view, worlds) do
    for world <- worlds, do: view |> element("#add-destiny-#{world}") |> render_click()
  end

  defp remove_visit(view, position) do
    view |> element("#maneuvers > li:nth-child(#{position}) button") |> render_click()
  end

  defp assert_steps(view, steps) do
    for {{action, world}, index} <- Enum.with_index(steps, 1) do
      assert has_element?(
               view,
               "#maneuvers > li:nth-child(#{index})[data-action='#{action}'][data-world='#{world}']"
             )
    end

    refute has_element?(view, "#maneuvers > li:nth-child(#{length(steps) + 1})")
  end

  defp assert_fuel(view, mass, steps) do
    {:ok, fuel} = Fuelex.Fuel.flight(mass, steps)
    assert has_element?(view, "#fuel-result[data-fuel='#{fuel}']")
  end
end
