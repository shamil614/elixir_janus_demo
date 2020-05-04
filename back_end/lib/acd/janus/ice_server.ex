defmodule Acd.Janus.IceServer do
  require Logger

  alias HTTPoison.Response

  def get do
    options = [ssl: [{:versions, [:"tlsv1.2"]}]]
    headers = [Authorization: auth(), "Content-Type": nil]
    data = %{format: "urls"}
    json = Jason.encode!(data)
    res = HTTPoison.put(url(), json, headers, options)

    servers =
      case res do
        {:ok, %Response{body: body}} ->
          Jason.decode!(body)

        _ ->
          nil
      end

    format(servers)
  end

  def format(nil), do: nil

  def format(%{"s" => "ok", "v" => %{"iceServers" => servers}}) do
    base = []

    Enum.reduce(servers, base, fn server, acc ->
      url = Map.get(server, "url", "")

      if (String.contains?(url, "turn") && String.contains?(url, "udp")) || String.contains?(url, "tcp") do
        updated_server =
          server
          |> Map.put_new("urls", url)
          |> Map.delete("url")

        [updated_server | acc]
      else
        acc
      end
    end)
  end

  defp auth do
    encoded = creds() |> Base.encode64() |> String.replace("\n", "")
    "Basic " <> encoded
  end

  defp creds do
    :acd |> Application.get_env(:ice_api) |> Keyword.get(:creds)
  end

  defp url do
    :acd |> Application.get_env(:ice_api) |> Keyword.get(:url)
  end
end
