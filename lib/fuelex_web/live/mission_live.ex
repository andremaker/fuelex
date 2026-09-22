defmodule FuelexWeb.MissionLive do
  use FuelexWeb, :live_view

  alias Fuelex.Fuel

  @actions %{"launch" => :launch, "land" => :land}
  @worlds %{"earth" => :earth, "moon" => :moon, "mars" => :mars}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Mission planner",
       form:
         to_form(%{"mass" => "", "first_action" => "", "last_action" => ""},
           as: :mission
         ),
       maneuvers: [],
       result: nil,
       placeholder: "Insert flight data",
       error: nil
     )
     |> stream(:maneuvers, [])}
  end

  @impl true
  def handle_event("add-destiny", %{"world" => world}, socket)
      when is_map_key(@worlds, world) do
    if is_map_key(@actions, socket.assigns.form.params["first_action"]) do
      stop = %{id: System.unique_integer([:positive]), world: world}
      {:noreply, update_route(socket, stops(socket) ++ [stop])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add-destiny", _params, socket), do: {:noreply, socket}

  def handle_event("remove-world", %{"id" => id}, socket) do
    remaining = Enum.reject(stops(socket), &(to_string(&1.id) == id))
    {:noreply, update_route(socket, remaining)}
  end

  def handle_event("calculate", %{"mission" => params}, socket) do
    params = Map.merge(socket.assigns.form.params, params)

    if (is_map_key(@actions, params["first_action"]) or params["first_action"] == "") and
         is_map_key(@actions, params["last_action"]) do
      route = stops(socket)
      socket = assign(socket, form: to_form(params, as: :mission))

      if params["first_action"] == "" do
        {:noreply, calculate(socket)}
      else
        {:noreply, update_route(socket, route)}
      end
    else
      {:noreply, socket}
    end
  end

  # The explicit maneuvers remain the source of truth. Stop IDs only group the
  # actions belonging to a selected world for the convenience of the builder.
  defp stops(socket) do
    socket.assigns.maneuvers
    |> Enum.uniq_by(& &1.stop_id)
    |> Enum.map(&%{id: &1.stop_id, world: &1.world})
  end

  defp update_route(socket, stops) do
    first_action = socket.assigns.form.params["first_action"]
    last_action = socket.assigns.form.params["last_action"]
    last_index = length(stops) - 1

    maneuvers =
      stops
      |> Enum.with_index()
      |> Enum.flat_map(fn {stop, index} ->
        actions =
          cond do
            last_index == 0 ->
              if first_action == last_action,
                do: [first_action],
                else: [first_action, last_action]

            index == 0 ->
              if first_action == "land", do: ["land", "launch"], else: ["launch"]

            index == last_index ->
              if last_action == "launch", do: ["land", "launch"], else: ["land"]

            true ->
              ["land", "launch"]
          end

        Enum.map(actions, fn action ->
          %{id: "#{stop.id}-#{action}", stop_id: stop.id, action: action, world: stop.world}
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
        Fuel.mission(mass, steps)
      else
        _ -> {:error, :invalid_mass}
      end

    case result do
      {:ok, fuel} ->
        cond do
          socket.assigns.form.params["first_action"] == "" ->
            assign(socket, placeholder: "Choose first action")

          steps == [] ->
            assign(socket, placeholder: "Add actions to your flight")

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
          <h2 id="planner-title" class="text-xl font-semibold">Mission planner</h2>
          <p class="mt-2 text-sm text-slate-400">
            Enter your spacecraft mass, then choose worlds in travel order.
          </p>
          <.form
            for={@form}
            id="mission-form"
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
              class="mission-input"
            />
            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={@form[:first_action]}
                type="select"
                label="First action"
                label_class="mb-1 block text-sm font-semibold"
                prompt="Choose action"
                options={[{"Launch", "launch"}, {"Land", "land"}]}
                class="mission-input"
              />
              <.input
                field={@form[:last_action]}
                type="select"
                label="Last action"
                label_class="mb-1 block text-sm font-semibold"
                prompt="Choose action"
                options={[{"Land", "land"}, {"Launch", "launch"}]}
                class="mission-input"
              />
            </div>
            <fieldset aria-describedby="world-help">
              <legend class="text-sm font-semibold">Add a world</legend>
              <p id="world-help" class="mt-2 text-sm leading-6 text-slate-400">
                Choose your starting world, then each destination. Departures between worlds are added automatically.
              </p>
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
            <section aria-labelledby="maneuvers-title">
              <h3 id="maneuvers-title" class="text-sm font-semibold">Actions</h3>
              <p
                :if={@maneuvers == []}
                id="maneuvers-empty"
                class="mt-3 rounded-xl border border-dashed border-slate-700 p-5 text-sm text-slate-400"
              >
                Your mission is empty. Choose a world above to get started.
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
                  data-stop-id={maneuver.stop_id}
                  class="rounded-xl border border-white/10 bg-slate-950/50 px-4 py-3 text-sm"
                >
                  <span class="ml-1 inline-flex items-center gap-2 text-slate-100">
                    <.icon
                      name={
                        if(maneuver.action == "launch", do: "hero-arrow-up", else: "hero-arrow-down")
                      }
                      class="size-4 text-lime-300"
                    />
                    {String.capitalize(maneuver.action)} {String.capitalize(maneuver.world)}
                  </span>
                  <button
                    id={"remove-world-#{maneuver.id}"}
                    type="button"
                    phx-click="remove-world"
                    phx-value-id={maneuver.stop_id}
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
              id="mission-error"
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
              <p class="mt-4 text-sm leading-6 text-slate-400">
                Calculate your mission to see the total fuel to load before launch.
              </p>
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
