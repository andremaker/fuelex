defmodule FuelexWeb.FlightComponentsTest do
  use FuelexWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FuelexWeb.FlightComponents

  test "world defaults to its inline icon and displayed name" do
    html = render_component(&FlightComponents.world/1, world: "earth")
    document = LazyHTML.from_fragment(html)

    assert Enum.count(LazyHTML.query(document, ".hero-globe-americas.text-sky-700.size-5")) == 1
    assert document |> LazyHTML.query("span.w-10") |> LazyHTML.text() == "Earth"
  end

  test "world can hide its name without removing its icon in every layout" do
    for world <- ~w(earth moon mars), layout <- [:stacked, :compact, :inline] do
      html =
        render_component(&FlightComponents.world/1,
          world: world,
          layout: layout,
          show_name: false
        )

      document = LazyHTML.from_fragment(html)
      assert Enum.count(LazyHTML.query(document, "span")) == 1
      assert document |> LazyHTML.text() |> String.trim() == ""
    end
  end
end
