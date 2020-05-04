defmodule AcdWeb.RoomController do
  use AcdWeb, :controller
  alias Acd.Conversation
  alias Acd.Conversation.Room
  alias Acd.Repo

  plug(:authenticate when action in [:new, :create, :show, :edit, :update, :destroy])

  def index(conn, _params) do
    rooms = Conversation.list_rooms()
    render(conn, "index.html", rooms: rooms)
  end

  def new(conn, _params) do
    changeset = Conversation.change_room(%Room{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"room" => room_params}) do
    case Conversation.create_room(room_params) do
      {:ok, _room} ->
        conn
        |> put_flash(:info, "Room created successfully.")
        |> redirect(to: Routes.room_path(conn, :index))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    room = Conversation.get_room!(id)
    # Attempt to recreate room in case Janus restarted
    Conversation.create_janus_room({:ok, room})
    render(conn, "show.html", room: room)
  end

  def edit(conn, %{"id" => id}) do
    room = Conversation.get_room!(id)
    changeset = Conversation.change_room(room)
    render(conn, "edit.html", room: room, changeset: changeset)
  end

  def update(conn, %{"id" => id, "room" => room_params}) do
    room = Conversation.get_room!(id)

    room
    |> Room.changeset(room_params)
    |> Repo.update()
    |> case do
      {:ok, room} ->
        conn
        |> put_flash(:info, "Room updated successfully.")
        |> redirect(to: Routes.room_path(conn, :show, room))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "edit.html", room: room, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    room = Conversation.get_room!(id)
    {:ok, _room} = Conversation.delete_room(room)

    conn
    |> put_flash(:info, "Room deleted successfully.")
    |> redirect(to: Routes.room_path(conn, :index))
  end

  defp authenticate(conn, _) do
    %{assigns: %{current_user: user}} = conn

    case user do
      nil ->
        conn
        |> put_flash(:error, "You must be logged in")
        |> redirect(to: "/")

      _ ->
        conn
    end
  end
end
