defmodule FuelexWeb.FlightLive do
  use FuelexWeb, :live_view

  alias Fuelex.Fuel

  import FuelexWeb.FlightComponents

  @actions %{"launch" => :launch, "land" => :land}
  @worlds %{"earth" => :earth, "moon" => :moon, "mars" => :mars}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Flight planner",
       form: to_form(%{}, as: :flight),
       actions: [],
       result: nil,
       placeholder: "Insert flight data",
       error: nil
     )}
  end

  @impl true
  def handle_event("start-flight", %{"action" => action, "world" => world}, socket)
      when is_map_key(@actions, action) and is_map_key(@worlds, world) do
    if socket.assigns.actions == [] do
      params = Map.put(socket.assigns.form.params, "first_action", action)
      route_point = %{id: System.unique_integer([:positive]), world: world}

      {:noreply,
       socket
       |> assign(form: to_form(params, as: :flight))
       |> update_route([route_point])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("start-flight", _params, socket), do: {:noreply, socket}

  def handle_event("add-route-point", %{"world" => world}, socket) when is_map_key(@worlds, world) do
    if socket.assigns.actions != [] and
         is_map_key(@actions, socket.assigns.form.params["first_action"]) do
      route_point = %{id: System.unique_integer([:positive]), world: world}
      {:noreply, update_route(socket, route_points(socket) ++ [route_point])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add-route-point", _params, socket), do: {:noreply, socket}

  def handle_event("remove-route-point", %{"id" => id}, socket) do
    remaining = Enum.reject(route_points(socket), &(to_string(&1.id) == id))
    {:noreply, update_route(socket, remaining)}
  end

  def handle_event("reorder-route", %{"from" => from, "to" => to}, socket) do
    route = route_points(socket)
    from_index = Enum.find_index(route, &(to_string(&1.id) == from))
    to_index = Enum.find_index(route, &(to_string(&1.id) == to))

    if from_index != nil and to_index != nil and from_index != to_index do
      {route_point, route} = List.pop_at(route, from_index)
      {:noreply, update_route(socket, List.insert_at(route, to_index, route_point))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("calculate", %{"flight" => params}, socket) do
    params = Map.merge(socket.assigns.form.params, params)

    if (is_map_key(@actions, params["first_action"]) or params["first_action"] in [nil, ""]) and
         (is_map_key(@actions, params["last_action"]) or params["last_action"] in [nil, ""]) do
      route = route_points(socket)
      socket = assign(socket, form: to_form(params, as: :flight))

      if params["first_action"] in [nil, ""] do
        {:noreply, calculate(socket)}
      else
        {:noreply, update_route(socket, route)}
      end
    else
      {:noreply, socket}
    end
  end

  # The explicit actions remain the source of truth. Route point IDs only group the
  # actions belonging to a selected world for the convenience of the builder.
  defp route_points(socket) do
    socket.assigns.actions
    |> Enum.uniq_by(& &1.route_point_id)
    |> Enum.map(&%{id: &1.route_point_id, world: &1.world})
  end

  defp update_route(socket, route_points) do
    first_action =
      case socket.assigns.form.params["first_action"] do
        action when action in [nil, ""] ->
          case socket.assigns.actions do
            [first | _] -> first.action
            [] -> ""
          end

        action ->
          action
      end

    last_action = socket.assigns.form.params["last_action"]
    last_index = length(route_points) - 1

    actions =
      route_points
      |> Enum.with_index()
      |> Enum.flat_map(fn {route_point, index} ->
        actions =
          cond do
            last_index == 0 ->
              if first_action == "land" and last_action == "launch",
                do: ["land", "launch"],
                else: [first_action]

            index == 0 ->
              if first_action == "land", do: ["land", "launch"], else: ["launch"]

            index == last_index ->
              if last_action == "launch", do: ["land", "launch"], else: ["land"]

            true ->
              ["land", "launch"]
          end

        Enum.map(actions, fn action ->
          %{
            id: "#{route_point.id}-#{action}",
            route_point_id: route_point.id,
            route_point_index: index,
            action: action,
            world: route_point.world
          }
        end)
      end)

    socket
    |> assign(actions: actions)
    |> calculate()
  end

  defp calculate(socket) do
    mass_value = socket.assigns.form.params["mass"] || ""
    socket = assign(socket, result: nil, error: nil, placeholder: "Insert spacecraft mass")
    if mass_value == "", do: socket, else: calculate_fuel(socket, mass_value)
  end

  defp calculate_fuel(socket, mass_value) do
    steps =
      Enum.map(
        socket.assigns.actions,
        &{Map.fetch!(@actions, &1.action), Map.fetch!(@worlds, &1.world)}
      )

    result =
      with {mass, ""} <- parse_mass(mass_value) do
        Fuel.flight(mass, steps)
      else
        _ -> {:error, :invalid_mass}
      end

    case result do
      {:ok, fuel} ->
        cond do
          socket.assigns.form.params["first_action"] in [nil, ""] ->
            assign(socket, placeholder: "Choose first action")

          socket.assigns.form.params["last_action"] in [nil, ""] ->
            assign(socket, placeholder: "Choose last action")

          steps == [] ->
            assign(socket, placeholder: "Add actions to your flight")

          match?([{:launch, _}], steps) and socket.assigns.form.params["last_action"] == "land" ->
            assign(socket, placeholder: "Add a landing destination")

          true ->
            assign(socket, result: fuel)
        end

      {:error, :invalid_mass} ->
        assign(socket, error: "Enter a positive spacecraft mass.")

      {:error, :invalid_sequence} ->
        assign(socket,
          error:
            "Each landing must be followed by a launch from the same world, and each launch by a landing."
        )

      {:error, _} ->
        assign(socket, error: "Unable to calculate fuel for these actions.")
    end
  end

  defp parse_mass(value) do
    case Integer.parse(value) do
      {mass, ""} -> {mass, ""}
      _ -> Float.parse(value)
    end
  end

  defp format_fuel(fuel) do
    fuel
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
