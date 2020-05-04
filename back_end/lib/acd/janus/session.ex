defmodule Acd.Janus.Session do
  use GenServer

  import Acd.Janus.Utility

  alias AcdWeb.Endpoint

  alias Acd.Janus.{
    HandlerRegistry,
    IceServerCache,
    VideoRoomHandler,
    HandlerSupervisor,
    WebsocketClient,
    WebsocketRegistry
  }

  alias Acd.Janus.WebsocketClient.Message

  require Logger

  defstruct [
    :channel_topic,
    :id,
    :keepalive,
    # Handle for the User's published feed
    :publisher_handle_id,
    :room_id,
    :user_id,
    # List of all published feeds
    published_feeds: [],
    # Track the handles for subscribed feeds
    subscribed_handles: []
  ]

  @keepalive_interval 50_000

  def start_link(attrs = %{channel_topic: _, id: _, room_id: _, user_id: _}, opts \\ []) do
    attrs =
      attrs
      |> Map.put_new(:keepalive, true)
      |> Map.put(:subscribed_handles, [])

    state = struct(__MODULE__, attrs)
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    if state.keepalive do
      Process.send_after(self(), :keepalive, @keepalive_interval)
    end

    {:ok, state}
  end

  def get(pid) do
    GenServer.call(pid, :get)
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  def update(pid, data = %{}) do
    GenServer.call(pid, {:update, data})
  end

  def update_published_feeds(pid, published_feeds) do
    GenServer.cast(pid, {:update_published_feeds, published_feeds})
  end

  def terminate(reason, state) do
    Logger.debug(fn ->
      "Terminating Session => #{inspect(reason)}"
    end)

    # Session may not have a WS
    case WebsocketRegistry.lookup(state.channel_topic) do
      [{janus_socket_pid, _}] ->
        WebsocketClient.stop(janus_socket_pid)

      _ ->
        nil
    end

    # TODO comeback and revisit the shutdown
    all_handles = [state.publisher_handle_id | state.subscribed_handles]

    for handler_id <- all_handles do
      case HandlerRegistry.lookup(handler_id) do
        [{handler_pid, _}] ->
          VideoRoomHandler.stop(handler_pid)

        _ ->
          nil
      end
    end
  end

  def handle_call(:get, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:update, data = %{}}, state) do
    state = Map.merge(state, data) |> IO.inspect(label: "Session Update")
    {:reply, {:ok, state}, state}
  end

  def handle_cast({:update_published_feeds, published_feeds}, state) do
    updated_published_feeds = published_feeds ++ state.published_feeds
    state = Map.put(state, :published_feeds, updated_published_feeds)

    {:noreply, state}
  end

  def handle_cast({event, unknown}, state) do
    Logger.debug(fn ->
      "Session handle_cast unknown event #{event} and ===> \n #{inspect(unknown)}"
    end)

    {:noreply, state}
  end

  def handle_info(
        :keepalive,
        state = %__MODULE__{id: session_id, keepalive: keepalive, channel_topic: channel_topic}
      ) do
    data = %{janus: "keepalive", transaction: transaction(), session_id: session_id}
    msg = %Message{caller_pid: self(), data: data, track_transaction: false}

    [{janus_websocket_pid, _}] = WebsocketRegistry.lookup(channel_topic)

    WebsocketClient.send_message(janus_websocket_pid, msg)

    if keepalive do
      Process.send_after(self(), :keepalive, @keepalive_interval)
    end

    {:noreply, state}
  end

  @doc """
  Plugin Attached / Handle Created
  Callback response after the Plugin Handle is attached.
  Allows Channel to create a Handle by the Janus `handle_id`.
  """
  def handle_info(
        %{
          response: %{"data" => %{"id" => handle_id}, "janus" => "success", "session_id" => alt_session_id},
          metadata: %{ptype: ptype}
        },
        state
      ) do
    %{id: session_id, channel_topic: channel_topic} = state

    # make sure the session ids match
    ^session_id = alt_session_id

    state = join_and_update_state(handle_id, ptype, state)
    {:ok, ice_servers} = IceServerCache.get()

    # Send the handle_id back to the client
    msg = %{handle_id: handle_id, ptype: ptype, ice_servers: ice_servers}
    Endpoint.broadcast!(channel_topic, "handle_created", msg)

    Logger.debug(fn ->
      "State of Session after :plugin_attached => #{inspect(state)}"
    end)

    {:noreply, state}
  end

  def join_and_update_state(handle_id, ptype = "publisher", session) do
    Logger.debug(fn ->
      "Publisher Handle Created for Session #{session.id}"
    end)

    %{
      channel_topic: channel_topic,
      room_id: room_id,
      id: session_id,
      user_id: user_id
    } = session

    attrs = %{
      channel_topic: channel_topic,
      id: handle_id,
      room_id: room_id,
      ptype: ptype,
      session_id: session_id,
      user_id: user_id
    }

    {:ok, publisher_handle_pid} = HandlerSupervisor.find_or_start_child(attrs)
    # TODO set the current_user's user_name
    :ok = VideoRoomHandler.join(publisher_handle_pid, %{user_name: "Foo bar", ptype: ptype})

    Map.put(session, :publisher_handle_id, handle_id)
  end

  def join_and_update_state(handle_id, ptype = "subscriber", session) do
    Logger.debug(fn ->
      "Subscriber Handle Created for Session #{session.id} \n" <>
        "Session state join_and_update_state(subscriber) => \n #{inspect(session)}"
    end)

    %{
      channel_topic: channel_topic,
      room_id: room_id,
      id: session_id,
      published_feeds: feeds,
      publisher_handle_id: publisher_handle_id,
      subscribed_handles: subscribed_handles,
      user_id: user_id
    } = session

    # Need to get the private_id from the publisher handle
    # TODO maybe refactor to track private_id in the session too
    [{vr_publisher_handle_pid, _}] = HandlerSupervisor.find_child(publisher_handle_id)
    {:ok, %VideoRoomHandler{private_id: private_id}} = VideoRoomHandler.get(vr_publisher_handle_pid)

    attrs = %{
      channel_topic: channel_topic,
      id: handle_id,
      room_id: room_id,
      session_id: session_id,
      ptype: ptype,
      user_id: user_id
    }

    {:ok, subscribed_handle_pid} = HandlerSupervisor.find_or_start_child(attrs)

    # other fields to match and update the handler ===> "audio_codec, display, video_codec"
    [feed | updated_feeds] = feeds
    # %{"id" => feed_id, "display" => user_name}

    if feed do
      %{"id" => feed_id, "display" => user_name} = feed

      :ok =
        VideoRoomHandler.join(subscribed_handle_pid, %{
          user_name: user_name,
          ptype: ptype,
          feed: feed_id,
          private_id: private_id
        })
    else
      Logger.debug(fn ->
        "FEED IS EMPTY!!!!!!"
      end)
    end

    updated_subscribed_handles = [handle_id | subscribed_handles]

    session
    |> Map.put(:subscribed_handles, updated_subscribed_handles)
    |> Map.put(:published_feeds, updated_feeds)
  end
end
