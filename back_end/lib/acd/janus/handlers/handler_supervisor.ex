defmodule Acd.Janus.HandlerSupervisor do
  use DynamicSupervisor
  alias Acd.Janus.{HandlerRegistry, VideoRoomHandler}

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def find_child(handle_id) do
    HandlerRegistry.lookup(handle_id)
  end

  def find_or_start_child(attrs = %{}) do
    case start_child(attrs) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  def start_child(attrs = %{id: handle_id}) do
    key = HandlerRegistry.name(handle_id)
    term = {HandlerRegistry, key}

    start =
      {VideoRoomHandler, :start_link,
       [
         attrs,
         [name: {:via, Registry, term}]
       ]}

    spec = %{restart: :transient, id: VideoRoomHandler, start: start}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def terminate_child(handle_id) do
    [{pid, _}] = HandlerRegistry.lookup(handle_id)
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
