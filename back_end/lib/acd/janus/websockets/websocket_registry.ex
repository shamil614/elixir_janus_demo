defmodule Acd.Janus.WebsocketRegistry do
  require Logger

  def name(channel_topic) do
    "ws:#{channel_topic}"
  end

  def lookup(channel_topic) do
    key = name(channel_topic)
    res = Registry.lookup(__MODULE__, key)

    Logger.debug(fn ->
      "Janus WS Registry found => #{inspect(res)}"
    end)

    res
  end
end
