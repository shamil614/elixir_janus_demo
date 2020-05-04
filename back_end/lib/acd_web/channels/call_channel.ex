defmodule AcdWeb.CallChannel do
  require Logger

  use AcdWeb, :channel

  alias Acd.Janus.{
    HandlerSupervisor,
    Session,
    SessionService,
    SessionSupervisor,
    VideoRoomHandler,
    WebsocketSupervisor
  }

  def join("room_call:" <> _details, payload, socket) do
    %{"room_id" => room_id, "user_id" => user_id} = payload

    Logger.debug(fn ->
      "Call Room Channel PID ====> #{inspect(socket.channel_pid)}"
    end)

    room_id = String.to_integer(room_id)
    current_user_id = socket.assigns[:current_user_id]
    # verify user_id subscribing to the channel matches the authenticated user
    ^current_user_id = String.to_integer(user_id)

    socket =
      socket
      |> assign(:room_id, room_id)

    send(self(), :after_join)

    {:ok, socket}
  end

  # Logic to create session
  def handle_info(:after_join, socket) do
    %{topic: topic} = socket
    # begin the core work to start a call by creating session
    {:ok, janus_websocket_pid} = WebsocketSupervisor.find_or_start_child(topic)

    # call to Janus to create a session. session_id is returned async via WS to this channel
    SessionService.create_async(janus_websocket_pid, socket.channel_pid)

    {:noreply, socket}
  end

  @doc """
  Session created.
  Response from Janus after the session is created.
  Allows Channel to create a Session state by `session_id`.
  """
  def handle_info(%{response: %{"data" => %{"id" => session_id}, "janus" => "success"}, metadata: _}, socket) do
    Logger.debug(fn ->
      "CallChannel => Session Created"
    end)

    socket =
      socket
      |> assign(:session_id, session_id)

    %{current_user_id: user_id, room_id: room_id} = socket.assigns

    attrs = %{
      channel_topic: socket.topic,
      user_id: user_id,
      room_id: room_id,
      id: session_id
    }

    {:ok, session_pid} = SessionSupervisor.start_child(attrs)

    # now that session has an id, a plugin can be attached
    :ok =
      SessionService.attach_plugin_async(%{
        channel_topic: socket.topic,
        session_id: session_id,
        callback_pid: session_pid,
        opaque_id: "user:#{user_id}",
        plugin: :video_room,
        ptype: "publisher"
      })

    {:noreply, socket}
  end

  # TODO: dig into why there's a unknown call.
  # Looks like a bug https://github.com/benoitc/hackney/issues/464
  def handle_info(unknown, socket) do
    Logger.debug(fn ->
      "Call Channel Unknown handle_info ====> \n #{inspect(unknown)}"
    end)

    {:noreply, socket}
  end

  # Client created a PeerConnection and is sending the Offer JSEP
  def handle_in(
        "offer",
        %{
          "handle" => %{"id" => handle_id, "ptype" => "publisher"},
          "jsep" => jsep = %{"sdp" => _, "type" => _},
          "message" => message = %{"request" => _, "audio" => _, "video" => _}
        },
        socket
      ) do
    %Session{publisher_handle_id: publisher_handle_id} = get_session(socket)
    # verify the handles match
    ^publisher_handle_id = handle_id

    [{vr_publisher_handle_pid, _}] = HandlerSupervisor.find_child(publisher_handle_id)
    VideoRoomHandler.offer(vr_publisher_handle_pid, %{jsep: jsep, message: message})

    {:noreply, socket}
  end

  def handle_in(
        "start",
        %{"handle_id" => handle_id, "jsep" => jsep = %{"sdp" => _, "type" => "answer"}},
        socket
      ) do
    [{subscribed_handle_pid, _}] = HandlerSupervisor.find_child(handle_id)

    VideoRoomHandler.start(subscribed_handle_pid, %{jsep: jsep})
    {:noreply, socket}
  end

  def handle_in("trickle", %{"handle_id" => handle_id, "candidate" => candidate}, socket) do
    [{handle_pid, _}] = HandlerSupervisor.find_child(handle_id)
    VideoRoomHandler.trickle(handle_pid, %{candidate: candidate})

    if candidate == %{"completed" => true} || candidate == nil || candidate == "" do
      broadcast!(socket, "trickle_completed", %{})
    end

    {:noreply, socket}
  end

  def terminate(reason, socket) do
    Logger.debug(fn ->
      "Channel Terminating because #{inspect(reason)} \n" <>
        "#{inspect(socket)}"
    end)

    session_id = Map.get(socket.assigns, :session_id)

    if session_id do
      SessionSupervisor.terminate_child(%{id: session_id})
    end
  end

  # Helper function to get the Session
  defp get_session(socket) do
    %{session_id: session_id} = socket.assigns
    [{session_pid, _}] = SessionSupervisor.find_child(session_id)
    {:ok, session} = Session.get(session_pid)
    session
  end
end
