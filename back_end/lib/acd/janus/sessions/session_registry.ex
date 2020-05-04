defmodule Acd.Janus.SessionRegistry do
  alias Acd.Janus.Session

  # User can not be in the same room more than once.
  def name(%{id: session_id}) do
    name(session_id)
  end

  # User can not be in the same room more than once.
  def name(%Session{id: session_id}) do
    name(session_id)
  end

  def name(session_id) do
    "session_id:#{session_id}"
  end

  def lookup(%Session{id: session_id}) do
    lookup(session_id)
  end

  def lookup(%{id: session_id}) do
    lookup(session_id)
  end

  def lookup(session_id) do
    key = name(session_id)
    Registry.lookup(__MODULE__, key)
  end
end
