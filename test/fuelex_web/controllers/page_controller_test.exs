defmodule FuelexWeb.PageControllerTest do
  use FuelexWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert conn
           |> html_response(200)
           |> LazyHTML.from_document()
           |> LazyHTML.query("#mission-form")
           |> Enum.any?()
  end
end
