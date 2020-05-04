defmodule Acd.Janus.RestClient do
  @moduledoc """
  Rest client for communicating with Janus
  """

  require Logger

  alias HTTPoison.Response
  alias HTTPoison.Error

  def get(path) do
    "#{config(:http_protocol)}://#{config(:host)}:#{config(:http_port)}/#{path}?apisecret=#{
      config(:api_secret)
    }"
    |> HTTPoison.get()
    |> process_response()
  end

  @spec post(path :: String.t(), data :: map) :: HTTPoison.Response.t()
  def post(path = "admin", data = %{}) do
    json =
      data
      |> Map.put(:admin_secret, config(:admin_secret))
      |> Map.put(:apisecret, config(:api_secret))
      |> Jason.encode!()

    "#{config(:http_protocol)}://#{config(:host)}:#{config(:admin_http_port)}/#{path}"
    |> HTTPoison.post(json)
    |> process_response()
  end

  def post(path = "janus", data = %{}) do
    json =
      data
      |> Map.put(:apisecret, config(:api_secret))
      |> Jason.encode!()

    "#{config(:http_protocol)}://#{config(:host)}:#{config(:http_port)}/#{path}"
    |> HTTPoison.post(json)
    |> process_response()
  end

  def post(path = "janus/" <> _sub_path, data = %{}) do
    json =
      data
      |> Map.put(:apisecret, config(:api_secret))
      |> Jason.encode!()

    "#{config(:http_protocol)}://#{config(:host)}:#{config(:http_port)}/#{path}"
    |> HTTPoison.post(json)
    |> process_response()
  end

  defp process_response({:ok, %Response{body: body}}) do
    Jason.decode(body)
  end

  defp process_response({:error, error = %Error{reason: reason}}) do
    Logger.debug(fn ->
      "Janus Rest Client Error => \n #{inspect(error)}"
    end)

    {:error, reason}
  end

  defp config(key) when is_atom(key) do
    :acd |> Application.get_env(:janus) |> Keyword.fetch!(key)
  end
end
