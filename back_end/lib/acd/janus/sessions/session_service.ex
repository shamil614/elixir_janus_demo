defmodule Acd.Janus.SessionService do
  require Logger

  import Acd.Janus.Utility

  alias Acd.Janus.{RestClient, WebsocketClient, WebsocketRegistry, VideoRoomHandler}
  alias Acd.Janus.WebsocketClient.Message

  def create_async(janus_websocket_pid, callback_pid) do
    data = %{janus: "create", transaction: transaction("create_session")}
    msg = %Message{caller_pid: callback_pid, data: data}

    :ok = WebsocketClient.send_message(janus_websocket_pid, msg)
  end

  def create do
    data = %{janus: "create", transaction: transaction()}

    case RestClient.post("janus", data) do
      {:ok, %{"data" => %{"id" => session_id}, "janus" => "success", "transaction" => _}} ->
        {:ok, session_id}

      _ ->
        {:error, nil}
    end
  end

  @doc """
  API call to Janus to create a handler for the plugin.
  """
  def attach_plugin(session_id, :video_room) when is_integer(session_id) do
    data = %{janus: "attach", transaction: transaction(), plugin: VideoRoomHandler.plugin_name()}

    case RestClient.post("janus/#{session_id}", data) do
      {:ok, %{"data" => %{"id" => handle_id}, "janus" => "success", "session_id" => ^session_id}} ->
        {:ok, handle_id}

      {:error, _} ->
        {:error, nil}
    end
  end

  def attach_plugin_async(%{
        channel_topic: channel_topic,
        session_id: session_id,
        callback_pid: callback_pid,
        plugin: :video_room,
        ptype: ptype
      }) do
    Logger.debug(fn ->
      "Attaching Plugin to Session #{session_id}"
    end)

    data = %{
      janus: "attach",
      transaction: transaction("attach_plugin"),
      plugin: VideoRoomHandler.plugin_name(),
      session_id: session_id
    }

    msg = %Message{caller_pid: callback_pid, data: data, metadata: %{ptype: ptype}}

    [{janus_websocket_pid, _}] = WebsocketRegistry.lookup(channel_topic)

    :ok = WebsocketClient.send_message(janus_websocket_pid, msg)
  end
end
