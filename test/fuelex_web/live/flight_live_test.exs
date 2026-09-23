defmodule FuelexWeb.FlightLiveTest do
  use FuelexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "starts with mass and six starting actions without default endpoints", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#flight-form input[name='flight[mass]']")
    assert has_element?(view, "#first-action")
    refute has_element?(view, "#action-controls")
    refute has_element?(view, "#world-controls")
    refute has_element?(view, "#flight-form select")
    assert has_element?(view, "#actions-empty")
    assert has_element?(view, "#fuel-placeholder", "Insert flight data")

    for world <- ~w(earth moon mars), action <- ~w(launch land) do
      assert has_element?(view, "#start-#{action}-#{world}[type='button']")
    end
  end

  test "each starting button sets the first action and synchronizes the radios", %{conn: conn} do
    for world <- ~w(earth moon mars), action <- ~w(launch land) do
      {:ok, view, _} = live(conn, ~p"/")
      change(view, %{mass: "1000"})
      start_flight(view, action, world)
      assert_actions(view, [{String.to_existing_atom(action), String.to_existing_atom(world)}])
      refute has_element?(view, "#first-action")
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
    render_click(view, "add-route-point", %{"world" => "earth"})
    assert_actions(view, [])
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
    assert_actions(view, launch: :earth)
    assert_incomplete(view)
  end

  test "removing the last route point restores cards and starting again preserves last action", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/")
    start_flight(view, "launch", "earth")
    change(view, %{mass: "1000", last_action: "launch"})

    [route_point_id] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#actions > li")
      |> LazyHTML.attribute("data-route-point-id")

    change(view, %{first_action: "land"})

    assert has_element?(
             view,
             "#actions > li[data-route-point-id='#{route_point_id}'] [data-action='land']"
           )

    assert has_element?(view, "#flight_first_action_land[checked]")
    render_click(view, "start-flight", %{"world" => "mars", "action" => "launch"})
    assert_actions(view, land: :earth, launch: :earth)
    remove_route_point(view, 1)
    assert has_element?(view, "#first-action")
    refute has_element?(view, "#action-controls")
    start_flight(view, "land", "moon")
    assert_actions(view, land: :moon, launch: :moon)
    assert has_element?(view, "#flight_first_action_land[checked]")
    assert has_element?(view, "#flight_last_action_launch[checked]")
    assert_fuel(view, 1000, land: :moon, launch: :moon)
  end

  test "destinations generate explicit Apollo actions and calculate immediately", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    start_flight(view, "launch", "earth")
    change(view, %{mass: "28801", last_action: "land"})
    add_worlds(view, ~w(moon earth))
    assert_actions(view, launch: :earth, land: :moon, launch: :moon, land: :earth)
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
    assert_actions(view, land: :earth, launch: :earth, land: :moon, launch: :moon)
    add_worlds(view, ~w(mars))

    actions = [
      land: :earth,
      launch: :earth,
      land: :moon,
      launch: :moon,
      land: :mars,
      launch: :mars
    ]

    assert_actions(view, actions)
    assert_fuel(view, 1000, actions)

    change(view, %{first_action: "launch"})
    assert_actions(view, launch: :earth, land: :moon, launch: :moon, land: :mars, launch: :mars)
    change(view, %{last_action: "land"})
    assert_actions(view, launch: :earth, land: :moon, launch: :moon, land: :mars)
    change(view, %{first_action: "land"})
    assert_actions(view, land: :earth, launch: :earth, land: :moon, launch: :moon, land: :mars)
    change(view, %{last_action: "launch"})
    assert_actions(view, actions)
  end

  test "launch to land needs a second selected world and recovers after route edits", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/")
    start_flight(view, "launch", "earth")
    change(view, %{mass: "1000", last_action: "land"})
    assert_actions(view, launch: :earth)
    assert_incomplete(view)

    add_worlds(view, ~w(moon))
    assert_actions(view, launch: :earth, land: :moon)
    assert_fuel(view, 1000, launch: :earth, land: :moon)
    remove_route_point(view, 2)
    assert_actions(view, launch: :earth)
    assert_incomplete(view)

    change(view, %{last_action: "launch"})
    assert_fuel(view, 1000, launch: :earth)
    change(view, %{last_action: "land"})
    assert_incomplete(view)
    change(view, %{first_action: "land"})
    assert_actions(view, land: :earth)
    assert_fuel(view, 1000, land: :earth)
    change(view, %{first_action: "launch"})
    assert_incomplete(view)

    add_worlds(view, ~w(earth))
    assert_actions(view, launch: :earth, land: :earth)
    assert_fuel(view, 1000, launch: :earth, land: :earth)
  end

  test "complete endpoint combinations work with a single world", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    start_flight(view, "launch", "earth")
    change(view, %{last_action: "land"})

    for {first, last, actions} <- [
          {"launch", "launch", [launch: :earth]},
          {"land", "launch", [land: :earth, launch: :earth]},
          {"land", "land", [land: :earth]}
        ] do
      change(view, %{mass: "1000", first_action: first, last_action: last})
      assert_actions(view, actions)
      assert_fuel(view, 1000, actions)
    end
  end

  test "removing route points reconnects the route and preserves endpoint choices", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    start_flight(view, "land", "earth")
    change(view, %{mass: "1000", last_action: "launch"})
    add_worlds(view, ~w(moon mars))
    remove_route_point(view, 2)
    assert_actions(view, land: :earth, launch: :earth, land: :mars, launch: :mars)
    assert_fuel(view, 1000, land: :earth, launch: :earth, land: :mars, launch: :mars)
    remove_route_point(view, 2)
    assert_actions(view, land: :earth, launch: :earth)
    add_worlds(view, ~w(moon))
    remove_route_point(view, 1)
    assert_actions(view, land: :moon, launch: :moon)
    remove_route_point(view, 1)
    assert_actions(view, [])
    assert has_element?(view, "#actions-empty")
    assert has_element?(view, "#fuel-placeholder", "Add actions to your flight")
    refute has_element?(view, "#flight-error")
  end

  test "consecutive repeated worlds are allowed and independently removable", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    start_flight(view, "launch", "moon")
    change(view, %{last_action: "land"})
    add_worlds(view, ~w(moon moon))
    assert_actions(view, launch: :moon, land: :moon, launch: :moon, land: :moon)
    remove_route_point(view, 2)
    assert_actions(view, launch: :moon, land: :moon)
    remove_route_point(view, 1)
    assert_actions(view, launch: :moon)
    remove_route_point(view, 1)
    assert_actions(view, [])
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
    for world <- worlds, do: view |> element("#add-route-point-#{world}") |> render_click()
  end

  defp remove_route_point(view, position) do
    [button_id] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(
        "#actions > li[data-route-point-id] > button[phx-click='remove-route-point']"
      )
      |> Enum.at(position - 1)
      |> LazyHTML.attribute("id")

    view |> element("##{button_id}") |> render_click()
  end

  defp assert_actions(view, actions) do
    elements =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#actions [data-action]")
      |> Enum.to_list()

    assert length(elements) == length(actions)

    for {element, {action, world}} <- Enum.zip(elements, actions) do
      assert LazyHTML.attribute(element, "data-action") == [to_string(action)]
      assert LazyHTML.attribute(element, "data-world") == [to_string(world)]
    end
  end

  defp assert_fuel(view, mass, actions) do
    {:ok, fuel} = Fuelex.Fuel.calculate_for_departure(mass, actions)
    assert has_element?(view, "#fuel-result[data-fuel='#{fuel}']")
  end
end
