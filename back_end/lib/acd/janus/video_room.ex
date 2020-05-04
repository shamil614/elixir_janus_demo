defmodule Acd.Janus.VideoRoom do
  alias Acd.Janus.RestClient

  # def get_session_events(session_id) do
  # end

  def create(%{handle_id: handler_id, room_id: room_id, session_id: session_id}) do
    # TODO tweak the Janus videoroom plugin to only allow requests with admin_key to create video rooms
    # https://janus.conf.meetecho.com/docs/videoroom

    data = %{
      audiocodec: "opus,pcmu",
      body: %{
        request: "create",
        room: format_room_id(room_id)
      },
      janus: "message",
      fir_freq: 10,
      publishers: 200,
      bitrate: 128_000,
      transaction: Ecto.UUID.generate(),
      videocode: "vp9,vp8,h264"
    }

    case RestClient.post("janus/#{session_id}/#{handler_id}", data) do
      {:ok, %{"janus" => "success", "plugindata" => %{"data" => data}}} ->
        {:ok, data}

      {:error, _} ->
        {:error, nil}
    end
  end

  def list_participants(%{handle_id: handler_id, room_id: room_id, session_id: session_id}) do
    # TODO tweak the Janus videoroom plugin to only allow requests with admin_key to create video rooms
    # https://janus.conf.meetecho.com/docs/videoroom

    data = %{
      body: %{
        request: "listparticipants",
        room: format_room_id(room_id)
      },
      janus: "message",
      transaction: Ecto.UUID.generate()
    }

    case RestClient.post("janus/#{session_id}/#{handler_id}", data) do
      {:ok, %{"janus" => "success", "plugindata" => %{"data" => data}}} ->
        {:ok, data}

      {:error, _} ->
        {:error, nil}
    end
  end

  defp format_room_id(room_id) when is_binary(room_id) do
    String.to_integer(room_id)
  end

  defp format_room_id(room_id) when is_integer(room_id) do
    room_id
  end
end
