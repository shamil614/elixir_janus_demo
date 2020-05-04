defmodule Acd.Janus.Utility do
  @doc """
  Helper function to build a transaction id.
  """
  def transaction(prefix) do
    uuid = Ecto.UUID.generate()

    "#{prefix}:#{uuid}"
  end

  def transaction do
    Ecto.UUID.generate()
  end
end
