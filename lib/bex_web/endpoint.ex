defmodule BexWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :bex

  socket "/mnode/socket", BexWeb.UserSocket,
    websocket: true,
    longpoll: false

  socket "/mnode/live", Phoenix.LiveView.Socket

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/mnode",
    from: :bex,
    gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt)

  plug Plug.Static, at: "/mnode", from: {:bex, "priv/avatars"}, gzip: false

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  @max_age 60 * 60 * 24 * 365 * 10
  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug Plug.Session,
    store: :cookie,
    key: "_bex_key",
    signing_salt: "vSmq27Cu",
    max_age: @max_age

  plug BexWeb.Router
end
