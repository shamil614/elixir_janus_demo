defmodule AcdWeb.RoomChannel do
  require Logger

  use AcdWeb, :channel

  alias Acd.Repo
  alias Acd.Auth.User
  alias AcdWeb.Presence

  def join("room:" <> room_id, _params, socket) do
    send(self(), :after_join)

    socket =
      socket
      |> assign(:room_id, room_id)

    {:ok, %{channel: "room:#{room_id}"}, socket}
  end

  def handle_in("message:add", %{"message" => content}, socket) do
    room_id = socket.assigns[:room_id]
    user = Repo.get(User, socket.assigns[:current_user_id])
    message = %{content: content, user: %{username: user.username}}

    broadcast!(socket, "room:#{room_id}:new_message", message)
    {:reply, :ok, socket}
  end

  def handle_in(event, data, socket) do
    Logger.debug(fn ->
      "Room Channel In => #{event} => #{inspect(data)}"
    end)

    {:reply, :ok, socket}
  end

  def handle_info(:after_join, socket) do
    push(socket, "presence_state", Presence.list(socket))

    user = Repo.get(User, socket.assigns[:current_user_id])

    {:ok, _} =
      Presence.track(socket, "user:#{user.id}", %{
        user_id: user.id,
        username: user.username
      })

    {:noreply, socket}
  end

  def handle_info(event, socket) do
    Logger.debug(fn ->
      "Room Channel Info => #{event}"
    end)

    {:noreply, socket}
  end

  def terminate(reason, _socket) do
    Logger.debug(fn ->
      "Channel Terminating because #{inspect(reason)}"
    end)
  end
end
