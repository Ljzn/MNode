defmodule Bex.Broadcaster do
  @moduledoc """
  send rawtx into mempool via p2p network(aka. tcp connection with bsvnode)
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(
      __MODULE__,
      %{
        nodes: []
      },
      name: __MODULE__
    )
  end

  @doc """
  send raw tx (hex) to all nodes we known.
  """
  def send_all(tx) do
    GenServer.cast(__MODULE__, {:send_all, tx})
  end

  @doc """
  get a list of pending txs.
  """
  def list_nodes() do
    GenServer.call(__MODULE__, :list_nodes)
  end

  @interval 1000

  def init(state) do
    {:ok, state, {:continue, :get_nodes} }
  end


  def handle_continue(:get_nodes, state) do
    pids = reconnect()
    {:noreply, %{ state | nodes: pids} }
  end

  # # reconnect all nodes every 30 seconds
  # def handle_info(:reconnect, state) do
  #   Logger.info "reconnect"
  #   pids = reconnect()
  #   {:noreply, %{ state | nodes: pids} }
  # end

  def handle_call(:list_nodes, _from, state = %{nodes: nodes}) do
    {:reply, nodes, state}
  end

  def handle_cast({:send_all, tx}, state = %{nodes: nodes}) do
    binary_tx = tx |> Binary.from_hex()
    for pid <- nodes do
      send pid, {:tx, binary_tx}
    end
    # spawn_link(fn -> check_tx(tx) end)
    {:noreply, state }
  end

  ## helpers

  # get pids
  defp reconnect() do
    nodes = :sv_peer.get_addrs_ipv4_dns()
    for host <- nodes do
      :sv_peer.connect(host)
    end
  end

  defp check_tx(tx) do
    :timer.sleep(5000)
    txid = BexLib.Txmaker.get_txid_from_hex_tx(tx)
    Logger.info "check tx:" <> inspect(SvApi.transaction(txid))
  end


end