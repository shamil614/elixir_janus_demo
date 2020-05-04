defmodule Acd.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms) do
      add :name, :string
      add :description, :string
      add :topic, :string

      timestamps()
    end

  end
end
