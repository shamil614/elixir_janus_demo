defmodule Acd.Janus.HandlerRegistry do
  def name(handler_id) do
    "handler_id:#{handler_id}"
  end

  def lookup(handler_id) do
    key = name(handler_id)
    Registry.lookup(__MODULE__, key)
  end
end
