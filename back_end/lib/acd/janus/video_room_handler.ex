defmodule Acd.Janus.VideoRoomHandler do
  use GenServer

  import Acd.Janus.Utility

  alias Acd.Janus.{
    IceServerCache,
    Session,
    SessionService,
    SessionSupervisor,
    WebsocketClient,
    WebsocketRegistry
  }

  alias Acd.Janus.WebsocketClient.Message
  alias AcdWeb.{Endpoint}

  require Logger

  defstruct [
    :channel_topic,
    :feed_id,
    :id,
    :room_id,
    :private_id,
    :session_id,
    :ptype,
    :user_id
  ]

  @plugin "janus.plugin.videoroom"

  def start_link(
        attrs = %{channel_topic: _, id: _, session_id: _, room_id: _, user_id: _, ptype: _},
        opts \\ []
      ) do
    state = struct(__MODULE__, attrs)
    # Create a handler for the plugin
    GenServer.start_link(__MODULE__, state, opts)
  end

  def init(state) do
    {:ok, state}
  end

  def plugin_name do
    @plugin
  end

  def join(pid, attrs = %{user_name: _, ptype: _}) do
    GenServer.cast(pid, {:join, attrs})
  end

  def get(pid) do
    GenServer.call(pid, :get)
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  def offer(pid, data = %{jsep: _, message: %{"request" => _, "audio" => _, "video" => _}}) do
    GenServer.cast(pid, {:offer, data})
  end

  # Called after creating an answer for a remote peer
  def start(pid, data = %{jsep: _}) do
    GenServer.cast(pid, {:start, data})
  end

  def trickle(pid, trickle = %{candidate: _candidate}) do
    GenServer.cast(pid, {:trickle, trickle})
  end

  def terminate(reason, state) do
    Logger.debug(fn ->
      "Terminating VideoRoomHandler id: #{state.id} | reason: #{inspect(reason)}"
    end)
  end

  def handle_call(:get, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_cast(
        {:trickle, %{candidate: candidate}},
        state = %__MODULE__{
          channel_topic: channel_topic,
          id: handle_id,
          session_id: session_id
        }
      ) do
    data = %{
      candidate: candidate,
      janus: "trickle",
      handle_id: handle_id,
      session_id: session_id,
      transaction: transaction("trickle")
    }

    # Trickle Messages don't get `ack` or any other later corresponding event.
    msg = %Message{data: data, track_transaction: false}
    [{janus_websocket_pid, _}] = WebsocketRegistry.lookup(channel_topic)
    WebsocketClient.send_message(janus_websocket_pid, msg)

    {:noreply, state}
  end

  def handle_cast(
        {:offer, %{jsep: jsep, message: message}},
        state = %__MODULE__{
          channel_topic: channel_topic,
          id: handle_id,
          session_id: session_id
        }
      ) do
    data = %{
      body: message,
      janus: "message",
      jsep: jsep,
      handle_id: handle_id,
      session_id: session_id,
      transaction: transaction("offer")
    }

    # No need to track the transaction as the SDP Answer should have the sender's handle_id
    msg = %Message{data: data, track_transaction: false}
    [{janus_websocket_pid, _}] = WebsocketRegistry.lookup(channel_topic)
    WebsocketClient.send_message(janus_websocket_pid, msg)

    {:noreply, state}
  end

  @doc """
  Client is attempting to join the video call.
  Janus needs to know the handle, session and ptype (publisher or subscriber).
  """
  def handle_cast(
        {:join, %{ptype: ptype = "publisher", user_name: user_name}},
        state = %__MODULE__{
          channel_topic: channel_topic,
          id: handle_id,
          room_id: room_id,
          session_id: session_id
        }
      ) do
    Logger.debug(fn ->
      "VideoRoomHandler joining => room: #{room_id} | ptype: #{ptype} | session_id: #{session_id} | handle_id: #{
        handle_id
      }"
    end)

    [{janus_websocket_pid, _}] = WebsocketRegistry.lookup(channel_topic)

    register = %{
      body: %{
        request: "join",
        room: room_id,
        ptype: ptype,
        display: user_name
      },
      janus: "message",
      handle_id: handle_id,
      session_id: session_id,
      transaction: transaction("publisher_join_room")
    }

    msg = %Message{data: register, caller_pid: self(), metadata: %{ptype: ptype}}
    WebsocketClient.send_message(janus_websocket_pid, msg)

    {:noreply, state}
  end

  def handle_cast(
        {:join, %{ptype: ptype = "subscriber", feed: feed_id, private_id: private_id, user_name: user_name}},
        state = %__MODULE__{
          channel_topic: channel_topic,
          feed_id: feed_id,
          id: handle_id,
          room_id: room_id,
          session_id: session_id
        }
      ) do
    Logger.debug(fn ->
      "VideoRoomHandler joining => room: #{room_id} | ptype: #{ptype} | session_id: #{session_id} | " <>
        "handle_id: #{handle_id} | feed_id: #{feed_id}"
    end)

    [{janus_websocket_pid, _}] = WebsocketRegistry.lookup(channel_topic)

    register = %{
      body: %{
        display: user_name,
        feed: feed_id,
        request: "join",
        room: room_id,
        ptype: ptype,
        private_id: private_id
      },
      janus: "message",
      handle_id: handle_id,
      session_id: session_id,
      transaction: transaction("subscriber_join_room")
    }

    msg = %Message{data: register, caller_pid: self(), metadata: %{ptype: ptype}}
    WebsocketClient.send_message(janus_websocket_pid, msg)

    {:noreply, state}
  end

  def handle_cast({:start, %{jsep: jsep}}, state) do
    Logger.debug(fn ->
      "VideoRoomHandler received start event"
    end)

    %__MODULE__{channel_topic: channel_topic, id: handle_id, session_id: session_id, room_id: room_id} = state

    data = %{
      body: %{
        request: "start",
        room: room_id
      },
      janus: "message",
      jsep: jsep,
      handle_id: handle_id,
      session_id: session_id,
      transaction: transaction("start:#{handle_id}")
    }

    msg = %Message{data: data}

    [{janus_websocket_pid, _}] = WebsocketRegistry.lookup(channel_topic)
    WebsocketClient.send_message(janus_websocket_pid, msg)

    {:noreply, state}
  end

  def handle_cast({event, unknown}, state) do
    Logger.debug(fn ->
      "VideoRoomHandler handle_cast unknown event #{event} and ===> \n #{inspect(unknown)}"
    end)

    {:noreply, state}
  end

  def handle_info(
        %{
          metadata: %{},
          response: %{
            "janus" => "media",
            "receiving" => true,
            "sender" => _,
            "session_id" => _,
            "type" => "audio"
          }
        },
        state
      ) do
    {:noreply, state}
  end

  # Videoroom joined event
  # track private_id
  # private_id used later when subscribing to remote video feeds
  def handle_info(
        %{
          response: %{
            "janus" => "event",
            "plugindata" => %{
              "data" => %{
                "private_id" => private_id,
                "publishers" => published_feeds,
                "videoroom" => "joined"
              }
            }
          }
        },
        state
      ) do
    call_data = %{private_id: private_id, published_feeds: published_feeds}
    %{channel_topic: channel_topic, session_id: session_id} = state

    Logger.debug(fn ->
      "VideoRoomHandler joined => private_id: #{private_id} | published_feeds: #{inspect(published_feeds)}"
    end)

    [{session_pid, _}] = SessionSupervisor.find_child(session_id)
    :ok = Session.update_published_feeds(session_pid, published_feeds)

    for _published_feed <- published_feeds do
      SessionService.attach_plugin_async(%{
        channel_topic: channel_topic,
        callback_pid: session_pid,
        plugin: :video_room,
        session_id: session_id,
        ptype: "subscriber"
      })
    end

    call_data = add_handle_data(call_data, state)

    state =
      state
      |> Map.put(:private_id, private_id)

    # After joining the room it's possible that people are already publishing video feeds
    Endpoint.broadcast!(channel_topic, "joined", call_data)

    {:noreply, state}
  end

  # SDP Answer for the Client's Publisher PeerConnection
  # sender should match the handle_id
  # session should match the session_id
  def handle_info(
        %{
          response: %{
            "janus" => "event",
            "jsep" => jsep = %{"sdp" => _, "type" => "answer"},
            "plugindata" => %{
              "data" => %{"configured" => "ok", "room" => _, "videoroom" => "event"}
            },
            "sender" => handle_id,
            "session_id" => alt_session_id
          }
        },
        %__MODULE__{ptype: "publisher", id: id, session_id: session_id} = state
      ) do
    ^id = handle_id
    ^session_id = alt_session_id
    data = add_handle_data(%{jsep: jsep}, state)

    Endpoint.broadcast!(state.channel_topic, "answer", data)

    {:noreply, state}
  end

  # published feeds changed event - publisher joined
  def handle_info(
        %{
          response: %{
            "janus" => "event",
            "plugindata" => %{
              "data" => %{"publishers" => published_feeds, "videoroom" => "event"},
              "plugin" => "janus.plugin.videoroom"
            },
            "sender" => handle_id,
            "session_id" => alt_session_id
          }
        },
        state = %{id: id, channel_topic: channel_topic, session_id: session_id}
      ) do
    ^id = handle_id
    ^session_id = alt_session_id
    [{session_pid, _}] = SessionSupervisor.find_child(session_id)

    :ok = Session.update_published_feeds(session_pid, published_feeds)

    for _published_feed <- published_feeds do
      SessionService.attach_plugin_async(%{
        channel_topic: channel_topic,
        callback_pid: session_pid,
        plugin: :video_room,
        session_id: session_id,
        ptype: "subscriber"
      })
    end

    {:noreply, state}
  end

  # SDP Offer after subscribing to a published remote feed
  # sender should match the handle_id
  # session should match the session_id
  def handle_info(
        %{
          response: %{
            "janus" => "event",
            "jsep" => jsep = %{"sdp" => _, "type" => "offer"},
            "plugindata" => %{"data" => %{"display" => _, "id" => _, "room" => _, "videoroom" => "attached"}},
            "sender" => handle_id,
            "session_id" => alt_session_id
          }
        },
        %{id: id, session_id: session_id} = state
      ) do
    # Make sure the received handle and session ids match the ids in the state
    ^id = handle_id
    ^session_id = alt_session_id

    Logger.debug(fn ->
      "VideoRoomHandler received offer from published remote feed \n" <>
        "#{inspect(state)}"
    end)

    {:ok, ice_servers} = IceServerCache.get()

    data =
      %{jsep: jsep, ice_servers: ice_servers}
      |> add_handle_data(state)

    Endpoint.broadcast!(state.channel_topic, "offer", data)

    {:noreply, state}
  end

  def handle_info(
        %{
          metadata: _,
          response: %{
            "janus" => "event",
            "plugindata" => %{
              "data" => %{"room" => _, "unpublished" => alt_feed_id, "videoroom" => "event"},
              "plugin" => "janus.plugin.videoroom"
            },
            "sender" => handle_id,
            "session_id" => alt_session_id
          }
        },
    %{id: id, session_id: session_id} = state
      ) do
    # Make sure the received handle and session ids match the ids in the state
    ^id = handle_id
    ^session_id = alt_session_id

    Logger.debug(fn ->
      "VideoRoomHandler received unpublished event for feed_id: #{alt_feed_id} \n" <>
      "#{inspect(state)}"
    end)

    {:noreply, state}
  end

  # known events that don't need to be sent to client
  def handle_info(unknown, state) do
    Logger.debug(fn ->
      "VideoRoomHandler \n #{inspect(state)} \n received unhandled data => \n #{inspect(unknown)}"
    end)

    {:noreply, state}
  end

  # helper function to add data to payload sent to client
  def add_handle_data(data, %__MODULE__{id: id, ptype: ptype}) do
    handle_data = %{id: id, ptype: ptype}
    Map.put_new(data, :handle, handle_data)
  end
end
