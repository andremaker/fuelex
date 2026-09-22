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
       form: to_form(%{}, as: :flight),
       actions: [],
       result: nil,
       placeholder: "Insert flight data",
       error: nil
     )
     |> stream(:actions, [])}
  end

  @impl true
  def handle_event("start-flight", %{"action" => action, "world" => world}, socket)
      when is_map_key(@actions, action) and is_map_key(@worlds, world) do
    if socket.assigns.actions == [] do
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

  def handle_event("add-destiny", %{"world" => world}, socket) when is_map_key(@worlds, world) do
    if socket.assigns.actions != [] and
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

  def handle_event("reorder-route", %{"from" => from, "to" => to}, socket) do
    route = visits(socket)
    from_index = Enum.find_index(route, &(to_string(&1.id) == from))
    to_index = Enum.find_index(route, &(to_string(&1.id) == to))

    if from_index != nil and to_index != nil and from_index != to_index do
      {visit, route} = List.pop_at(route, from_index)
      {:noreply, update_route(socket, List.insert_at(route, to_index, visit))}
    else
      {:noreply, socket}
    end
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

  # The explicit actions remain the source of truth. Visit IDs only group the
  # actions belonging to a selected world for the convenience of the builder.
  defp visits(socket) do
    socket.assigns.actions
    |> Enum.uniq_by(& &1.visit_id)
    |> Enum.map(&%{id: &1.visit_id, world: &1.world})
  end

  defp update_route(socket, visits) do
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
    last_index = length(visits) - 1

    actions =
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
    |> assign(actions: actions)
    |> stream(:actions, actions, reset: true)
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="flight-content" class="w-full sm:px-[2%]">
        <div class="mb-8 sm:mb-10">
          <h1 class="text-4xl font-semibold tracking-tight text-lime-300 sm:text-5xl 2xl:text-6xl">
            Space Travel Fuel Calculator
          </h1>
          <p class="mt-4 text-base leading-relaxed sm:text-lg text-slate-400">
            Build an interplanetary itinerary and calculate the fuel you need on board before liftoff.
          </p>
        </div>

        <div
          id="flight-workspace"
          class="grid w-full min-w-0 items-start gap-10 sm:px-[2%] xl:grid-cols-[minmax(0,1.08fr)_minmax(370px,1fr)_minmax(0,0.76fr)]"
        >
          <section
            id="flight-planner"
            class="min-w-0 rounded-2xl border border-slate-700/50 bg-linear-to-br from-slate-900/60 to-slate-900/30 p-5 sm:p-6"
          >
            <.form for={@form} id="flight-form" phx-change="calculate" class="space-y-6">
              <.input
                field={@form[:mass]}
                type="number"
                label="Spacecraft mass (kg)"
                placeholder="e.g. 10,000"
                label_class="mb-3 block text-xl font-semibold"
                step="any"
                required
                class="flight-input text-lg"
              />

              <%= if @actions == [] do %>
                <fieldset id="first-visit">
                  <legend class="text-xl font-semibold">First action</legend>

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
                      <div class={[
                        "flex flex-col items-center gap-2 py-3 text-base font-semibold",
                        color
                      ]}>
                        <.icon name={icon} class="size-6" />
                        {String.capitalize(world)}
                      </div>

                      <div class="mt-2 space-y-2">
                        <button
                          :for={
                            {action, icon} <- [
                              {"launch", "hero-arrow-up"},
                              {"land", "hero-arrow-down"}
                            ]
                          }
                          id={"start-#{action}-#{world}"}
                          type="button"
                          phx-click="start-flight"
                          phx-value-action={action}
                          phx-value-world={world}
                          aria-label={"#{String.capitalize(action)} on #{String.capitalize(world)}"}
                          class={[
                            "flex min-h-11 w-full items-center justify-center gap-1 rounded-lg border px-2 py-2 text-base font-medium transition focus-visible:outline-2 focus-visible:outline-offset-2 active:scale-95 sm:gap-2",
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
                <div class="flight-planner-controls">
                  <div
                    id="action-controls"
                    class="flight-action-controls grid min-w-0 content-start gap-4"
                  >
                    <fieldset
                      :for={
                        {field, label} <- [
                          {:first_action, "First action"},
                          {:last_action, "Last action"}
                        ]
                      }
                      id={"flight_#{field}"}
                    >
                      <legend class="text-xl font-semibold">{label}</legend>

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
                          label_class="flex min-h-11 cursor-pointer items-center justify-center gap-2 rounded-xl border border-white/10 bg-slate-950/50 px-2 py-3 text-base font-medium transition hover:border-lime-300/50 has-checked:border-lime-300/50 has-checked:bg-lime-300/10 has-checked:text-lime-200"
                          class="size-4 shrink-0 cursor-pointer accent-lime-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lime-300"
                        />
                      </div>
                    </fieldset>
                  </div>

                  <fieldset class="flight-visit-controls min-w-0">
                    <legend class="text-xl font-semibold">Add a route point</legend>

                    <div id="world-controls" class="flight-world-controls mt-3">
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
                          "flight-world-button flex min-h-24 min-w-0 items-center justify-center gap-3 rounded-xl border border-white/10 bg-slate-950/50 p-2 text-base font-semibold transition hover:border-lime-300/50 hover:bg-lime-300/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lime-300 active:scale-95 disabled:cursor-not-allowed disabled:opacity-40",
                          color
                        ]}
                      >
                        <span aria-hidden="true" class="text-2xl font-bold leading-none">+</span>

                        <div class="flex flex-col items-center gap-2">
                          <.icon name={icon} class="size-6" />
                          <span>{String.capitalize(world)}</span>
                        </div>
                      </button>
                    </div>
                  </fieldset>
                </div>
              <% end %>

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

          <section
            class="min-w-0 rounded-2xl border border-slate-700/50 bg-linear-to-br from-slate-900/60 to-slate-900/30 p-4 sm:p-5"
            aria-labelledby="actions-title"
          >
            <h2 id="actions-title" class="text-xl font-semibold">Route</h2>

            <p
              :if={@actions == []}
              id="actions-empty"
              class="mt-4 rounded-xl border border-dashed border-slate-700 p-5 text-sm text-slate-400"
            >
              Choose a world to get started.
            </p>

            <ol
              :if={@actions != []}
              id="actions"
              phx-hook=".Sortable"
              class="mt-4 max-h-[60vh] space-y-2 overflow-y-auto pr-2"
            >
              <%= for actions <- Enum.chunk_by(@actions, & &1.visit_id) do %>
                <% route_point = hd(actions) %>

                <li
                  id={"route-point-#{route_point.visit_id}"}
                  data-visit-id={route_point.visit_id}
                  draggable="true"
                  class={[
                    "flex min-w-0 cursor-grab items-center gap-2.5 rounded-xl border px-3 py-2.5 transition-colors active:cursor-grabbing",
                    if(rem(route_point.visit_index, 2) == 0,
                      do: "border-lime-300/40 bg-lime-300/10",
                      else: "border-sky-400/40 bg-sky-400/10"
                    )
                  ]}
                >
                  <div class="flex shrink-0 items-center gap-2 text-sm font-medium text-slate-100">
                    <span class="w-4 tabular-nums">{route_point.visit_index + 1}.</span>
                    <.icon
                      name={
                        case route_point.world do
                          "earth" -> "hero-globe-americas"
                          "moon" -> "hero-moon"
                          "mars" -> "hero-globe-alt"
                        end
                      }
                      class={[
                        "size-5 shrink-0",
                        case route_point.world do
                          "earth" -> "text-sky-300"
                          "moon" -> "text-slate-300"
                          "mars" -> "text-orange-300"
                        end
                      ]}
                    />
                    <span class="w-10">{String.capitalize(route_point.world)}</span>
                  </div>

                  <div class="flex shrink-0 items-center gap-1.5">
                    <div
                      :for={action <- actions}
                      id={"action-#{action.id}"}
                      data-action={action.action}
                      data-world={action.world}
                      class={[
                        "flex shrink-0 items-center gap-1.5 rounded-lg border px-2.5 py-1.5 text-sm",
                        if(rem(route_point.visit_index, 2) == 0,
                          do: "border-lime-300/25 bg-slate-950/40 text-lime-300",
                          else: "border-sky-400/40 bg-slate-950/40 text-sky-300"
                        )
                      ]}
                    >
                      <.icon
                        name={
                          if(action.action == "launch", do: "hero-arrow-up", else: "hero-arrow-down")
                        }
                        class="size-4"
                      />
                      {String.capitalize(action.action)}
                    </div>
                  </div>

                  <button
                    id={"remove-world-#{route_point.visit_id}"}
                    type="button"
                    phx-click="remove-world"
                    phx-value-id={route_point.visit_id}
                    aria-label={"Remove #{String.capitalize(route_point.world)} route point"}
                    class="ml-auto shrink-0 rounded-lg p-1.5 text-slate-400 transition hover:bg-rose-400/10 hover:text-rose-300 focus-visible:outline-2 focus-visible:outline-lime-300"
                  >
                    <.icon name="hero-x-mark" class="size-5" />
                  </button>
                </li>
              <% end %>
            </ol>
          </section>

          <aside class="min-w-0">
            <section
              class="min-w-0 rounded-2xl border border-lime-300/25 bg-linear-to-br from-lime-300/3 to-slate-900/20 p-5"
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
                  class="mt-4 text-4xl font-semibold tracking-tight [overflow-wrap:anywhere] 2xl:text-5xl"
                >
                  {format_fuel(@result)} <span class="text-xl text-slate-400">kg</span>
                </p>
                <p class="mt-3 text-sm leading-6 text-slate-400">
                  Includes fuel for every action and the additional fuel needed to carry it.
                </p>
              <% else %>
                <p id="fuel-placeholder" class="mt-4 text-2xl font-medium [overflow-wrap:anywhere]">
                  {@placeholder}
                </p>
              <% end %>
            </section>
          </aside>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Sortable">
        export default {
          mounted() {
            this.draggedId = null

            this.el.addEventListener("dragstart", event => {
              const item = event.target.closest("[data-visit-id]")
              if (!item) return
              this.draggedId = item.dataset.visitId
              event.dataTransfer.effectAllowed = "move"
              item.classList.add("opacity-50")
            })

            this.el.addEventListener("dragend", event => {
              event.target.closest("[data-visit-id]")?.classList.remove("opacity-50")
              this.draggedId = null
            })

            this.el.addEventListener("dragover", event => {
              if (event.target.closest("[data-visit-id]")) event.preventDefault()
            })

            this.el.addEventListener("drop", event => {
              const item = event.target.closest("[data-visit-id]")
              if (!item || !this.draggedId) return
              event.preventDefault()
              this.pushEvent("reorder-route", {from: this.draggedId, to: item.dataset.visitId})
            })
          }
        }
      </script>
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
