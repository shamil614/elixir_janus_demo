# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :acd,
  ecto_repos: [Acd.Repo]

# Configures the endpoint
config :acd, AcdWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "IHcQX+YutRegKj4DxzrV2YaSzYu/UOhe1RT9KQGOs7O+gdo1hvDl907Pn014h0w2",
  render_errors: [view: AcdWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Acd.PubSub, adapter: Phoenix.PubSub.PG2]

janus_admin_secret = System.get_env("JANUS_ADMIN_SECRET")
janus_admin_http_port = "JANUS_ADMIN_HTTP_PORT" |> System.get_env()
janus_api_secret = System.get_env("JANUS_API_SECRET")
janus_http_port = "JANUS_HTTP_PORT" |> System.get_env()
janus_host = System.get_env("JANUS_HOST")
janus_http_protocol = System.get_env("JANUS_HTTP_PROTOCOL")
janus_ws_port = "JANUS_WS_PORT" |> System.get_env()
janus_ws_protocol = System.get_env("JANUS_WS_PROTOCOL")

config :acd, :janus,
  admin_secret: janus_admin_secret,
  admin_http_port: janus_admin_http_port,
  admin_path: "/admin",
  api_secret: janus_api_secret,
  host: janus_host,
  http_port: janus_http_port,
  http_protocol: janus_http_protocol || "http",
  path: "/janus",
  ws_port: janus_ws_port,
  ws_protocol: janus_ws_protocol

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

defmodule Acd.Utility do
  def to_bool("true"), do: true
  def to_bool("false"), do: false
  def to_bool(""), do: false
  def to_bool(nil), do: false
end

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
