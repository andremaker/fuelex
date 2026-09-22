defmodule FuelexWeb.FlightLive do
  use FuelexWeb, :live_view

  alias Fuelex.Fuel

  @actions %{"launch" => :launch, "land" => :land}
  @worlds %{"earth" => :earth, "moon" => :moon, "mars" => :mars}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Flight planner",
       form:
         to_form(%{},
           as: :flight
         ),
       maneuvers: [],
       result: nil,
       placeholder: "Insert flight data",
       error: nil
     )
     |> stream(:maneuvers, [])}
  end

  @impl true
  def handle_event("start-flight", %{"action" => action, "world" => world}, socket)
      when is_map_key(@actions, action) and is_map_key(@worlds, world) do
    if socket.assigns.maneuvers == [] do
      params = Map.put(socket.assigns.form.params, "first_action", action)
      visit = %{id: System.unique_integer([:positive]), world: world}

      {:noreply,
       socket
       |> assign(form: to_form(params, as: :flight))
       |> update_route([visit])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("start-flight", _params, socket), do: {:noreply, socket}

  def handle_event("add-destiny", %{"world" => world}, socket)
      when is_map_key(@worlds, world) do
    if socket.assigns.maneuvers != [] and
         is_map_key(@actions, socket.assigns.form.params["first_action"]) do
      visit = %{id: System.unique_integer([:positive]), world: world}
      {:noreply, update_route(socket, visits(socket) ++ [visit])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add-destiny", _params, socket), do: {:noreply, socket}

  def handle_event("remove-world", %{"id" => id}, socket) do
    remaining = Enum.reject(visits(socket), &(to_string(&1.id) == id))
    {:noreply, update_route(socket, remaining)}
  end

  def handle_event("calculate", %{"flight" => params}, socket) do
    params = Map.merge(socket.assigns.form.params, params)

    if (is_map_key(@actions, params["first_action"]) or params["first_action"] in [nil, ""]) and
         (is_map_key(@actions, params["last_action"]) or params["last_action"] in [nil, ""]) do
      route = visits(socket)
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

  # The explicit maneuvers remain the source of truth. Visit IDs only group the
  # actions belonging to a selected world for the convenience of the builder.
  defp visits(socket) do
    socket.assigns.maneuvers
    |> Enum.uniq_by(& &1.visit_id)
    |> Enum.map(&%{id: &1.visit_id, world: &1.world})
  end

  defp update_route(socket, visits) do
    first_action =
      case socket.assigns.form.params["first_action"] do
        action when action in [nil, ""] ->
          case socket.assigns.maneuvers do
            [first | _] -> first.action
            [] -> ""
          end

        action ->
          action
      end

    last_action = socket.assigns.form.params["last_action"]
    last_index = length(visits) - 1

    maneuvers =
      visits
      |> Enum.with_index()
      |> Enum.flat_map(fn {visit, index} ->
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
            id: "#{visit.id}-#{action}",
            visit_id: visit.id,
            visit_index: index,
            action: action,
            world: visit.world
          }
        end)
      end)

    socket
    |> assign(maneuvers: maneuvers)
    |> stream(:maneuvers, maneuvers, reset: true)
    |> calculate()
  end

  defp calculate(socket) do
    mass_value = socket.assigns.form.params["mass"] || ""
    socket = assign(socket, result: nil, error: nil, placeholder: "Insert spacecraft mass")

    if mass_value == "" do
      socket
    else
      calculate_fuel(socket, mass_value)
    end
  end

  defp calculate_fuel(socket, mass_value) do
    steps =
      socket.assigns.maneuvers
      |> Enum.map(&{Map.fetch!(@actions, &1.action), Map.fetch!(@worlds, &1.world)})

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

          match?([{:launch, _}], steps) and
              socket.assigns.form.params["last_action"] == "land" ->
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
        assign(socket, error: "Unable to calculate fuel for these maneuvers.")
    end
  end

  defp parse_mass(value) do
    case Integer.parse(value) do
      {mass, ""} -> {mass, ""}
      _ -> Float.parse(value)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mb-12 max-w-2xl">
        <h1 class="text-4xl font-semibold tracking-tight sm:text-6xl text-lime-300">
          Space Travel Fuel Calculator
        </h1>
        <p class="mt-6 text-lg leading-relaxed text-slate-400">
          Build an interplanetary itinerary and calculate the fuel you need on board before liftoff.
        </p>
      </div>
      <div class="grid gap-8 lg:grid-cols-[1.3fr_1fr]">
        <section
          class="rounded-3xl border border-white/10 bg-slate-900 p-6 sm:p-8"
          aria-labelledby="planner-title"
        >
          <h2 id="planner-title" class="text-xl font-semibold">Flight planner</h2>
          <.form
            for={@form}
            id="flight-form"
            phx-change="calculate"
            class="mt-6 space-y-6"
          >
            <.input
              field={@form[:mass]}
              type="number"
              label="Spacecraft mass (kg)"
              label_class="mb-1 block text-sm font-semibold"
              step="any"
              required
              class="flight-input"
            />
            <%= if @maneuvers == [] do %>
              <fieldset id="first-visit">
                <legend class="text-sm font-semibold">First stop</legend>
                <div class="mt-4 grid grid-cols-3 gap-2 sm:gap-3">
                  <div
                    :for={
                      {world, icon, color} <- [
                        {"earth", "hero-globe-americas", "text-sky-300"},
                        {"moon", "hero-moon", "text-slate-300"},
                        {"mars", "hero-globe-alt", "text-orange-300"}
                      ]
                    }
                    id={"first-visit-#{world}"}
                    class="min-w-0 rounded-xl border border-white/10 bg-slate-950/50 p-2 sm:p-3"
                  >
                    <div class={["flex flex-col items-center gap-2 py-3 text-sm font-semibold", color]}>
                      <.icon name={icon} class="size-6" />
                      {String.capitalize(world)}
                    </div>
                    <div class="mt-2 space-y-2">
                      <button
                        :for={
                          {action, icon} <- [{"launch", "hero-arrow-up"}, {"land", "hero-arrow-down"}]
                        }
                        id={"start-#{action}-#{world}"}
                        type="button"
                        phx-click="start-flight"
                        phx-value-action={action}
                        phx-value-world={world}
                        aria-label={"#{String.capitalize(action)} on #{String.capitalize(world)}"}
                        class={[
                          "flex min-h-11 w-full items-center justify-center gap-1 rounded-lg border px-2 py-2 text-sm font-medium transition focus-visible:outline-2 focus-visible:outline-offset-2 active:scale-95 sm:gap-2",
                          if(action == "launch",
                            do:
                              "border-lime-300/20 bg-lime-300/5 text-lime-300 hover:bg-lime-300/15 focus-visible:outline-lime-300",
                            else:
                              "border-sky-300/20 bg-sky-300/5 text-sky-300 hover:bg-sky-300/15 focus-visible:outline-sky-300"
                          )
                        ]}
                      >
                        <.icon name={icon} class="size-4" />
                        {String.capitalize(action)}
                      </button>
                    </div>
                  </div>
                </div>
              </fieldset>
            <% else %>
              <div id="action-controls" class="grid gap-4 sm:grid-cols-2">
                <fieldset
                  :for={
                    {field, label} <- [{:first_action, "First action"}, {:last_action, "Last action"}]
                  }
                  id={"flight_#{field}"}
                >
                  <legend class="text-sm font-semibold">{label}</legend>
                  <div class="mt-3 grid grid-cols-2 gap-2">
                    <.input
                      :for={action <- ["launch", "land"]}
                      field={@form[field]}
                      id={"flight_#{field}_#{action}"}
                      type="radio"
                      value={action}
                      checked={@form[field].value == action}
                      required={field == :last_action}
                      label={String.capitalize(action)}
                      label_class="flex min-h-11 cursor-pointer items-center justify-center gap-2 rounded-xl border border-white/10 bg-slate-950/50 px-2 py-3 text-sm font-medium transition hover:border-lime-300/50 has-checked:border-lime-300/50 has-checked:bg-lime-300/10 has-checked:text-lime-200"
                      class="size-4 shrink-0 cursor-pointer accent-lime-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lime-300"
                    />
                  </div>
                </fieldset>
              </div>
              <fieldset>
                <legend class="text-sm font-semibold">Add a visit</legend>
                <div id="world-controls" class="mt-4 grid grid-cols-3 gap-2 sm:gap-3">
                  <button
                    :for={
                      {world, icon, color} <- [
                        {"earth", "hero-globe-americas", "text-sky-300"},
                        {"moon", "hero-moon", "text-slate-300"},
                        {"mars", "hero-globe-alt", "text-orange-300"}
                      ]
                    }
                    id={"add-destiny-#{world}"}
                    type="button"
                    phx-click="add-destiny"
                    phx-value-world={world}
                    disabled={@form[:first_action].value == ""}
                    aria-label={"Add #{String.capitalize(world)}"}
                    class={[
                      "flex min-h-24 flex-col items-center justify-center gap-2 rounded-xl border border-white/10 bg-slate-950/50 p-3 text-sm font-semibold transition hover:border-lime-300/50 hover:bg-lime-300/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lime-300 active:scale-95 disabled:cursor-not-allowed disabled:opacity-40",
                      color
                    ]}
                  >
                    <.icon name={icon} class="size-6" />
                    {String.capitalize(world)}
                  </button>
                </div>
              </fieldset>
            <% end %>
            <section aria-labelledby="maneuvers-title">
              <h3 id="maneuvers-title" class="text-sm font-semibold">Actions</h3>
              <p
                :if={@maneuvers == []}
                id="maneuvers-empty"
                class="mt-3 rounded-xl border border-dashed border-slate-700 p-5 text-sm text-slate-400"
              >
                Choose a world to get started.
              </p>
              <ol
                id="maneuvers"
                phx-update="stream"
                class="mt-3 list-inside list-decimal space-y-2 text-slate-400"
              >
                <li
                  :for={{id, maneuver} <- @streams.maneuvers}
                  id={id}
                  data-action={maneuver.action}
                  data-world={maneuver.world}
                  data-visit-id={maneuver.visit_id}
                  class={[
                    "rounded-xl border border-l-4 px-4 py-3 text-sm transition-colors",
                    if(rem(maneuver.visit_index, 2) == 0,
                      do: "border-lime-300/20 border-l-lime-300 bg-lime-300/5 text-lime-300",
                      else: "border-sky-300/20 border-l-sky-300 bg-sky-300/5 text-sky-300"
                    )
                  ]}
                >
                  <span class="ml-1 inline-flex items-center gap-2 text-slate-100">
                    <.icon
                      name={
                        if(maneuver.action == "launch", do: "hero-arrow-up", else: "hero-arrow-down")
                      }
                      class={[
                        "size-4",
                        if(rem(maneuver.visit_index, 2) == 0,
                          do: "text-lime-300",
                          else: "text-sky-300"
                        )
                      ]}
                    />
                    {String.capitalize(maneuver.action)} - {String.capitalize(maneuver.world)}
                  </span>
                  <button
                    id={"remove-world-#{maneuver.id}"}
                    type="button"
                    phx-click="remove-world"
                    phx-value-id={maneuver.visit_id}
                    aria-label={"Remove #{String.capitalize(maneuver.world)} visit"}
                    class="float-right rounded-md p-1 text-slate-400 transition hover:bg-rose-400/10 hover:text-rose-300 focus-visible:outline-2 focus-visible:outline-lime-300"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </li>
              </ol>
            </section>
            <p
              :if={@error}
              id="flight-error"
              role="alert"
              class="rounded-xl border border-rose-400/30 bg-rose-400/10 p-4 text-sm text-rose-200"
            >
              {@error}
            </p>
          </.form>
        </section>
        <aside class="mt-6 space-y-6">
          <section
            class="rounded-3xl border border-lime-300/20 bg-lime-300/5 p-8"
            aria-labelledby="result-title"
            aria-live="polite"
          >
            <p id="result-title" class="text-xs uppercase tracking-widest text-lime-300">
              Fuel at departure
            </p>
            <%= if @result != nil do %>
              <p
                id="fuel-result"
                data-fuel={@result}
                class="mt-5 break-words text-5xl font-semibold tracking-tight"
              >
                {format_fuel(@result)} <span class="text-xl text-slate-400">kg</span>
              </p>
              <p class="mt-4 text-sm leading-6 text-slate-400">
                Includes fuel for every maneuver and the additional fuel needed to carry it.
              </p>
            <% else %>
              <p id="fuel-placeholder" class="mt-5 text-3xl font-medium">{@placeholder}</p>
            <% end %>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  defp format_fuel(fuel) do
    fuel
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
