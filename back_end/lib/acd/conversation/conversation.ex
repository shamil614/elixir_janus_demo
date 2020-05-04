defmodule Acd.Conversation do
  require Logger

  alias Acd.Repo
  alias Acd.Conversation.Room
  alias Acd.Janus.{SessionService, VideoRoom}

  def list_rooms do
    Repo.all(Room)
  end

  def change_room(%Room{} = room) do
    Room.changeset(room, %{})
  end

  def create_room(attrs \\ %{}) do
    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
    |> create_janus_room()
  end

  def update_room(%Room{} = room, attrs) do
    room
    |> Room.changeset(attrs)
    |> Repo.update()
  end

  def delete_room(%Room{} = room) do
    Repo.delete(room)
  end

  def get_room!(id), do: Repo.get(Room, id)

  def create_janus_room({:ok, room = %Room{id: room_id}}) do
    # Create a temp admin session that is NOT kept alive.
    # Using synchronous api call to get session_id back immediately.
    {:ok, session_id} = SessionService.create()
    {:ok, handle_id} = SessionService.attach_plugin(session_id, :video_room)
    {:ok, _room_data} = VideoRoom.create(%{handle_id: handle_id, room_id: room_id, session_id: session_id})

    {:ok, room}
  end
end
