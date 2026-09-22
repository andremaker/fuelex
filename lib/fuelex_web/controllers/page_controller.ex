defmodule FuelexWeb.PageController do
  use FuelexWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
