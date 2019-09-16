defmodule BexWeb.ApiController do
  use BexWeb, :controller

  alias Bex.Wallet
  alias Bex.Wallet.Utxo
  alias BexLib.Bitindex
  alias Bex.CoinManager
  alias Bex.Util
  require Logger

  plug :find_private_key

  @doc """
  Create a metanet directory or file.
  The private key is association with the APP_KEY in the header.

  params:
    dir: "a/b/c"
    file: %Plug.Upload{}

  if only dir, create a dir; if path and file, creat the file.
  Can not create dir or file under unexisted dir.
  """
  def create(conn, %{"parent" => false, "name" => c_dir} = params) do
    c_dir = to_string(c_dir)
    base_key = conn.assigns.private_key
    content = deal_with_content(params)
    {:ok, txid, hex_tx} = CoinManager.create_mnode(base_key.id, false, c_dir, content)
    respond(conn, params, hex_tx, txid)
  end

  # It's a bit confusing, cause the different view of nodes.
  # In old code, we see the "parent" node as self node, and
  # "id" node as child node.
  def create(conn, %{"parent" => s_dir, "name" => c_dir} = params) do
    s_dir = to_string(s_dir)
    c_dir = to_string(c_dir)
    base_key = conn.assigns.private_key
    content = deal_with_content(params)
    # use parent id and self id as dir, and need the root dir
    case CoinManager.create_mnode(base_key.id, s_dir, c_dir, content) do
      {:ok, txid, hex_tx} ->
        respond(conn, params, hex_tx, txid)

      {:error, _} ->
        json(conn, %{code: 1, error: "mnode: #{s_dir}: No such file or directory"})
    end
  end

  def create(conn, %{"path" => path} = params) do
    {parent, name} = Util.path_to_name(path)
    create(conn, Map.merge(params, %{"parent" => parent, "name" => name}))
  end

  def create(conn, _) do
    json(conn, %{error: "`parent` or `name` didn't set"})
  end

  defp respond(conn, _params, hex_tx, txid) do
    json(conn, %{code: 0, raw_tx: hex_tx, txid: txid})
  end

  defp deal_with_content(params) do
    case params["content"] do
      b when is_binary(b) ->
        [b]

      m when is_map(m) ->
        m
        |> Enum.map(fn {k, v} ->
          i = String.to_integer(k)
          {i, v}
        end)
        |> Enum.sort()
        |> Enum.map(fn {_, v} -> v end)

      l when is_list(l) ->
        l

      _ ->
        []
    end
  end

  def find(conn, %{"name" => dir}) do
    base_key = conn.assigns.private_key

    case Wallet.find_txids_with_dir(base_key, dir) do
      {:ok, txids} ->
        json(conn, %{code: 0, txids: txids})

      {:error, _} ->
        json(conn, %{code: 1, error: "mnode: #{dir}: No such file or directory"})
    end
  end

  def find(conn, %{"path" => dir} = params) do
    find(conn, Map.put(params, "name", dir))
  end

  defp dir_type(dir) do
    case String.contains?(dir, "/") do
      true -> :noroot
      false -> :root
    end
  end

  # {:error, msg} or {:ok, private_key}
  defp find_private_key(conn, _options) do
    case get_req_header(conn, "app_key") do
      [] ->
        conn
        |> json(%{error: "no app_key in headers"})
        |> halt()

      [app_key] ->
        case Wallet.find_private_key_by_app_key(app_key) do
          nil ->
            conn
            |> json(%{error: "app_key not exists"})
            |> halt()

          pk ->
            conn
            |> assign(:private_key, pk)
        end

      other ->
        conn
        |> json(%{error: "invalid APP_KEY: #{inspect(other)}"})
        |> halt()
    end
  end
end
