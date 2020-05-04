defmodule Acd.Repo do
  use Ecto.Repo,
    otp_app: :acd,
    adapter: Ecto.Adapters.Postgres
end
