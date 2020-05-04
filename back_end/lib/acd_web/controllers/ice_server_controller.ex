defmodule AcdWeb.IceServerController do
  use AcdWeb, :controller
  alias HTTPoison.Response

  @url "https://global.xirsys.net/_turn/Janus-Dev"
  @creds "shamil614:4e10a758-5228-11e9-a123-0242ac110003"
  @encoded_creds @creds |> Base.encode64() |> String.replace("\n", "")
  @auth "Basic " <> @encoded_creds

  # TODO protect this action
  def index(conn, _params) do
    options = [ssl: [{:versions, [:"tlsv1.2"]}]]
    headers = [Authorization: @auth, "Content-Type": nil]
    data = %{format: "urls"}
    json = Jason.encode!(data)
    res = HTTPoison.put(@url, json, headers, options)

    servers =
      case res do
        {:ok, %Response{body: body}} ->
          Jason.decode!(body)

        _ ->
          nil
      end

    render(conn, "index.json", servers: servers)
  end
end
