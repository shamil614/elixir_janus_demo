defmodule AcdWeb.PageController do
  use AcdWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
