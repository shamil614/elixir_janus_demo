import Config

defmodule Acd.Utility do
  def to_bool("true"), do: true
  def to_bool("false"), do: false
  def to_bool(""), do: false
  def to_bool(nil), do: false
end

http_port = "PORT" |> System.get_env() |> String.to_integer()
db_pool_size = "DB_POOL_SIZE" |> System.get_env() |> String.to_integer()
db_port = "DB_PORT" |> System.get_env() |> String.to_integer()
db_ssl = "DB_SSL" |> System.get_env() |> Acd.Utility.to_bool()

keyfile = System.get_env("KEYFILE")
cacertfile = System.get_env("CACERTFILE")
certfile = System.get_env("CERTFILE")

config :acd, AcdWeb.Endpoint,
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  url: [host: System.get_env("HOSTNAME"), port: 443],
  cache_static_manifest: "priv/static/cache_manifest.json",
  force_ssl: [hsts: true],
  https: [otp_app: :acd, port: 443, keyfile: keyfile, cacertfile: cacertfile, certfile: certfile]

# Configure your database
config :acd, Acd.Repo,
  username: System.get_env("DB_USER"),
  password: System.get_env("DB_PW"),
  database: System.get_env("DB_NAME"),
  hostname: System.get_env("DB_HOST"),
  pool_size: db_pool_size,
  port: db_port,
  ssl: db_ssl

# Do not print debug messages in production
config :logger, level: :debug

config :acd, :ice_api, url: System.get_env("ICE_API_URL"), creds: System.get_env("ICE_API_CREDS")

janus_admin_secret = System.get_env("JANUS_ADMIN_SECRET")
janus_admin_http_port = "JANUS_ADMIN_HTTP_PORT" |> System.get_env() |> String.to_integer()
janus_api_secret = System.get_env("JANUS_API_SECRET")
janus_http_port = "JANUS_HTTP_PORT" |> System.get_env() |> String.to_integer()
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
