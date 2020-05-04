defmodule Acd.Janus.IceServerCache do
  require Logger

  use GenServer

  alias Acd.Janus.IceServer

  @refresh_interval 25_000

  def start_link(_, opts \\ []) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, [], opts)
  end

  def init(_) do
    Process.send_after(self(), :refresh, @refresh_interval)
    servers = IceServer.get()
    {:ok, servers}
  end

  def get do
    GenServer.call(__MODULE__, :get)
  end

  def handle_call(:get, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_info(:refresh, state) do
    Logger.info(fn ->
      "Refreshing IceServer cache"
    end)

    servers = IceServer.get()

    case servers do
      nil ->
        Logger.info(fn ->
          "Ice Servers not found attempting refresh shortly"
        end)

        Process.send_after(self(), :refresh, 500)
        {:noreply, state}

      _ ->
        Process.send_after(self(), :refresh, @refresh_interval)
        {:noreply, servers}
    end
  end

  # TODO: dig into why there's a unknown call.
  # Looks like a bug https://github.com/benoitc/hackney/issues/464
  def handle_info(_unknown, state) do
    {:noreply, state}
  end
end
