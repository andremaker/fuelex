defmodule FuelexWeb.FlightLiveTest do
  use FuelexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "starts with mass and six starting actions without default endpoints", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#flight-form input[name='flight[mass]']")
    assert has_element?(view, "#first-visit")
    refute has_element?(view, "#action-controls")
    refute has_element?(view, "#world-controls")
    refute has_element?(view, "#flight-form select")
    assert has_element?(view, "#maneuvers-empty")
    assert has_element?(view, "#fuel-placeholder", "Insert flight data")

    for world <- ~w(earth moon mars), action <- ~w(launch land) do
      assert has_element?(view, "#start-#{action}-#{world}[type='button']")
    end
  end

  test "each starting button sets the first visit and synchronizes the radios", %{conn: conn} do
    for world <- ~w(earth moon mars), action <- ~w(launch land) do
      {:ok, view, _} = live(conn, ~p"/")
      change(view, %{mass: "1000"})
      start_flight(view, action, world)
      assert_steps(view, [{String.to_existing_atom(action), String.to_existing_atom(world)}])
      refute has_element?(view, "#first-visit")
      assert has_element?(view, "#world-controls")
      assert has_element?(view, "#flight_first_action_#{action}[type='radio'][checked]")
      refute has_element?(view, "#flight_last_action input[checked]")
      assert has_element?(view, "#flight_last_action_launch[type='radio'][required]")
      assert has_element?(view, "#flight_last_action_land[type='radio'][required]")
      assert has_element?(view, "#fuel-placeholder", "Choose last action")
      refute has_element?(view, "#fuel-result")
      refute has_element?(view, "#flight-form select")
    end
  end

  test "starting cards preserve mass validation and unset last action", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    render_click(view, "start-flight", %{"world" => "venus", "action" => "launch"})
    render_click(view, "start-flight", %{"world" => "earth", "action" => "orbit"})
    render_click(view, "add-destiny", %{"world" => "earth"})
    assert_steps(view, [])
    change(view, %{mass: "-10"})
    assert has_element?(view, "#flight-error")
    start_flight(view, "land", "earth")
    assert has_element?(view, "#flight-error")
    change(view, %{mass: "1000"})
    assert has_element?(view, "#fuel-placeholder", "Choose last action")
    refute has_element?(view, "#flight-error")
    change(view, %{last_action: "land"})
    assert_fuel(view, 1000, land: :earth)
    change(view, %{first_action: "launch"})
    assert_steps(view, launch: :earth)
    assert_incomplete(view)
  end

  test "removing the last visit restores cards and starting again preserves last action", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/")
    start_flight(view, "launch", "earth")
    change(view, %{mass: "1000", last_action: "launch"})

    [visit_id] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#maneuvers > li")
      |> LazyHTML.attribute("data-visit-id")

    change(view, %{first_action: "land"})
    assert has_element?(view, "#maneuvers > li[data-visit-id='#{visit_id}'][data-action='land']")
    assert has_element?(view, "#flight_first_action_land[checked]")
    render_click(view, "start-flight", %{"world" => "mars", "action" => "launch"})
    assert_steps(view, land: :earth, launch: :earth)
    remove_visit(view, 1)
    assert has_element?(view, "#first-visit")
    refute has_element?(view, "#action-controls")
    start_flight(view, "land", "moon")
    assert_steps(view, land: :moon, launch: :moon)
    assert has_element?(view, "#flight_first_action_land[checked]")
    assert has_element?(view, "#flight_last_action_launch[checked]")
    assert_fuel(view, 1000, land: :moon, launch: :moon)
  end

  test "destinations generate explicit Apollo maneuvers and calculate immediately", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    start_flight(view, "launch", "earth")
    change(view, %{mass: "28801", last_action: "land"})
    add_worlds(view, ~w(moon earth))
    assert_steps(view, launch: :earth, land: :moon, launch: :moon, land: :earth)
    assert has_element?(view, "#fuel-result[data-fuel='51898']")
    change(view, %{mass: "1000"})
    assert_fuel(view, 1000, launch: :earth, land: :moon, launch: :moon, land: :earth)
  end

  test "endpoint switches remove leftover actions and final launch follows new destinations", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/")
    start_flight(view, "land", "earth")
    change(view, %{mass: "1000", last_action: "launch"})
    add_worlds(view, ~w(moon))
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
    start_flight(view, "launch", "earth")
    change(view, %{mass: "1000", last_action: "land"})
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
    start_flight(view, "launch", "earth")
    change(view, %{last_action: "land"})

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
    start_flight(view, "land", "earth")
    change(view, %{mass: "1000", last_action: "launch"})
    add_worlds(view, ~w(moon mars))
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
    start_flight(view, "launch", "moon")
    change(view, %{last_action: "land"})
    add_worlds(view, ~w(moon moon))
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
    start_flight(view, "launch", "earth")
    change(view, %{mass: "1000", last_action: "land"})
    assert_incomplete(view)
    refute has_element?(view, "#flight-error")

    for mass <- ["0", "-10", "-0.5"] do
      change(view, %{mass: mass})

      assert has_element?(
               view,
               "#flight-form #flight-error",
               "Enter a positive spacecraft mass."
             )
    end

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

  defp start_flight(view, action, world) do
    view |> element("#start-#{action}-#{world}") |> render_click()
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
