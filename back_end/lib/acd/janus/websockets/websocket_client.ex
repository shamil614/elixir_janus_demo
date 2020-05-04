defmodule Acd.Janus.WebsocketClient do
  require Logger

  use WebSockex

  alias Acd.Janus.{HandlerSupervisor, SessionSupervisor}

  defstruct [
    :transactions
  ]

  defmodule Message do
    defstruct [
      # Used to track the caller so a response can be sent
      # back to the caller.
      :caller_pid,
      # Payload of data to be sent in the WS frame.
      :data,
      metadata: %{},
      # Optional flag to disable the tracking of transactions.
      # Some events like `keepalive` don't need to be tracked.
      track_transaction: true
    ]
  end

  def start_link(_, opts \\ []) do
    state = %__MODULE__{transactions: %{}}

    header = {"Sec-WebSocket-Protocol", "janus-protocol"}
    opts = [extra_headers: [header]] ++ opts

    opts =
      with {:ok, config} <- Application.fetch_env(:acd, :janus),
           {:ok, debug} <- Keyword.fetch(config, :ws_debug) do
        debug ++ opts
      else
        _ ->
          opts
      end

    WebSockex.start_link(
      "#{config(:ws_protocol)}://#{config(:host)}:#{config(:ws_port)}#{config(:path)}",
      __MODULE__,
      state,
      opts
    )
  end

  def init(state) do
    Logger.debug(fn ->
      "Starting Janus WS => #{inspect(state)}"
    end)

    {:ok, state}
  end

  def send_message(pid, msg = %Message{}) do
    WebSockex.cast(pid, {:send, msg})
  end

  def stop(pid) do
    WebSockex.cast(pid, {:text, "stop"})
  end

  ## handle_cast

  def handle_cast({:text, "stop"}, state) do
    {:close, state}
  end

  def handle_cast(
        {:send,
         %Message{
           caller_pid: caller_pid,
           data: data = %{transaction: transaction},
           metadata: metadata,
           track_transaction: track_transaction
         }},
        state
      ) do
    Logger.debug(fn ->
      "Janus WS Client #{inspect(self())} state before => #{inspect(state)}"
    end)

    json =
      data
      |> Map.put(:apisecret, config(:api_secret))
      |> Jason.encode!()

    # Don't track keepalive transactions, or ones that are explicitly opted out.
    transactions =
      if Map.get(data, :janus) == "keepalive" || track_transaction == false do
        state.transactions
      else
        Map.put_new(state.transactions, transaction, %{caller_pid: caller_pid, metadata: metadata})
      end

    state = state |> Map.put(:transactions, transactions)

    Logger.debug(fn ->
      "Janus WS Client state after => #{inspect(state)}"
    end)

    {:reply, {:text, json}, state}
  end

  def handle_cast(frame, state) do
    Logger.debug(fn ->
      "*********** Janus WS Client received unknown cast *********" <>
        "\n #{inspect(frame)}"
    end)

    {:ok, state}
  end

  ## WS Client specific handles

  def handle_connect(_conn, state) do
    {:ok, state}
  end

  def handle_disconnect(connection_status, state) do
    Logger.debug(fn ->
      "Handling WS disconnect | status => #{connection_status}"
    end)

    {:ok, state}
  end

  ## handle_frame

  def handle_frame({:text, msg}, state) do
    %__MODULE__{transactions: transactions} = state
    data = Jason.decode!(msg)

    # keepalive and ack transactions are not tracked
    # don't attempt to send ack back to caller
    state =
      if Map.get(data, "janus") == "ack" do
        state
      else
        # find the pid of the caller from the tracked transactions
        {tranaction_data, pending_transactions} = Map.pop(transactions, data["transaction"])
        # update state with reduced transaction list
        state = Map.put(state, :transactions, pending_transactions)
        # send the received data to another process
        dispatch_event(data, tranaction_data)

        state
      end

    {:ok, state}
  end

  def handle_frame(frame, state) do
    Logger.debug(fn ->
      "*********** Janus WS Client received unknown frame *********" <>
        "\n #{inspect(frame)}"
    end)

    {:ok, state}
  end

  ## Other functions

  @doc """
  Logic to determine where to send the response to.
  """
  def dispatch_event(%{"janus" => "timeout", "session_id" => session_id}, _) do
    # TODO attempt to cleanup state
    SessionSupervisor.terminate_child(%{id: session_id})
  end

  # pid is associated to the transaction
  def dispatch_event(response = %{}, %{caller_pid: pid, metadata: metadata}) when is_pid(pid) do
    send(pid, %{response: response, metadata: metadata})
  end

  # no additional data is in the response (no pid, no metadata)
  def dispatch_event(response = %{"sender" => _, "session_id" => _session_id}, nil) do
    dispatch_event(response, %{caller_pid: nil, metadata: %{}})
  end

  # handle sent the event. send to the handle pid
  def dispatch_event(response = %{"sender" => handle_id, "session_id" => _session_id}, %{
        caller_pid: nil,
        metadata: metadata
      }) do
    [{handle_pid, _}] = HandlerSupervisor.find_child(handle_id)

    send(handle_pid, %{response: response, metadata: metadata})
  end

  def dispatch_event(response = [%{"error" => _} | _tail], pid) when is_pid(pid) do
    Logger.info(fn ->
      inspect(response)
    end)
  end

  def dispatch_event(response, _) do
    Logger.info(fn ->
      "Unhandled Event from WS => #{inspect(response)}"
    end)
  end

  def terminate(reason, state) do
    Logger.debug(fn ->
      "\nSocket Terminating:\n#{inspect(reason)}\n\n#{inspect(state)}\n"
    end)
  end

  defp config(key) when is_atom(key) do
    :acd |> Application.get_env(:janus) |> Keyword.fetch!(key)
  end
end
