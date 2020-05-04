defmodule Acd.Janus.SessionSupervisor do
  use DynamicSupervisor
  alias Acd.Janus.{Session, SessionRegistry}

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def find_child(session_id) do
    SessionRegistry.lookup(session_id)
  end

  def find_or_start_child(session_attributes = %{}) do
    case start_child(session_attributes) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  def start_child(session_attributes = %{}) do
    key = SessionRegistry.name(session_attributes)
    term = {SessionRegistry, key}

    start =
      {Session, :start_link,
       [
         session_attributes,
         [name: {:via, Registry, term}]
       ]}

    spec = %{restart: :transient, id: Session, start: start}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def terminate_child(session_attributes = %{}) do
    case SessionRegistry.lookup(session_attributes) do
      [{pid, _}] ->
        Session.stop(pid)
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      _ ->
        nil
    end
  end
end
