defmodule Acd.Janus.WebsocketSupervisor do
  require Logger

  use DynamicSupervisor

  alias Acd.Janus.{Session, WebsocketClient, WebsocketRegistry}

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def find_or_start_child(%Session{channel_topic: channel_topic}) do
    find_or_start_child(channel_topic)
  end

  def find_or_start_child(channel_topic) do
    case start_child(channel_topic) do
      {:ok, pid} ->
        Logger.debug(fn ->
          "Starting new Janus WS => #{inspect(pid)} for channel topic #{channel_topic}"
        end)

        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug(fn ->
          "Starting new Janus WS => #{inspect(pid)} for channel topic #{channel_topic}"
        end)

        {:ok, pid}

      error ->
        error
    end
  end

  def start_child(channel_topic) do
    key = WebsocketRegistry.name(channel_topic)
    term = {WebsocketRegistry, key}

    start =
      {WebsocketClient, :start_link,
       [
         channel_topic,
         [name: {:via, Registry, term}]
       ]}

    spec = %{restart: :transient, id: WebsocketClient, start: start}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
