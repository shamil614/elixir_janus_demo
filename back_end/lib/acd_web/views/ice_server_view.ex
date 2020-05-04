defmodule AcdWeb.IceServerView do
  use AcdWeb, :view

  def render("index.json", %{servers: nil}) do
    []
  end

  def render("index.json", %{servers: %{"s" => "ok", "v" => %{"iceServers" => servers}}}) do
    base = []

    Enum.reduce(servers, base, fn server, acc ->
      url = Map.get(server, "url", "")

      if String.contains?(url, "stun") || String.contains?(url, ":3478?") do
        [server | acc]
      else
        acc
      end
    end)
  end
end
