defmodule FuelexWeb.FlightComponents do
  @moduledoc """
  Stateless function components for the flight planner.
  """
  use FuelexWeb, :html

  @world_styles %{
    "earth" => {"hero-globe-americas", "text-sky-700"},
    "moon" => {"hero-moon", "text-neutral-600"},
    "mars" => {"hero-globe-alt", "text-orange-700"}
  }

  embed_templates "flight/*"

  @doc "Renders a world's visual identity, optionally including its name."
  attr :world, :string, required: true, values: ["earth", "moon", "mars"]
  attr :show_name, :boolean, default: true

  attr :layout, :atom,
    default: :inline,
    values: [:stacked, :compact, :inline],
    doc: "Stacked colored name, compact icon/name pair, or inline route-sized icon/name"

  def world(assigns)

  @doc "Renders one route point from its group of actions."
  attr :actions, :list, required: true, doc: "The ordered actions belonging to one route point"
  def route_point(assigns)

  defp world_style(world), do: Map.fetch!(@world_styles, world)
end
