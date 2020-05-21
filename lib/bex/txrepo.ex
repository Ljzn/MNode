defmodule Bex.Txrepo do
  @moduledoc """
  #FIXME should use PSQL to persistant the txs.
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(
      __MODULE__,
      %{
        queue: :queue.new(),
        status: :off
      },
      name: __MODULE__
    )
  end

  def add(txid, hex_tx) when is_binary(hex_tx) and is_binary(txid) do
    Bex.KV.save_tx(hex_tx)
    GenServer.cast(__MODULE__, {:pending, {txid, hex_tx, nil}})
    turn_on()
  end

  def broadcast(txid, tx) do
    spawn_link(fn ->
      try_broadcast(txid, tx)
    end)
  end

  def pending({_tx, _, "the transaction was rejected by network rules." <> _}) do
    nil
  end

  def pending(info) do
    GenServer.cast(__MODULE__, {:pending, info})
  end

  defp try_broadcast(txid, tx) do
    Logger.debug("#{__MODULE__} broadcasting #{txid}: #{tx}")
    r = send_via_merchant_api(tx)

    r
    |> inspect()
    |> Logger.debug()

    case r do
      {:ok, %{"return_result" => "success"}} ->
        :ok

      {:ok, any} ->
        pending({txid, tx, inspect(any)})

      {:error, msg} ->
        pending({txid, tx, msg})
    end
  end

  def send_via_merchant_api(tx) do
    miner = mempool()
    Manic.TX.push(miner, tx)
  end

  defp mempool(), do: Manic.miner :mempool, headers: [{"token", "561b756d12572020ea9a104c3441b71790acbbce95a6ddbf7e0630971af9424b"}]

  def tx_status(txid) do
    miner = mempool()
    Manic.TX.status!(miner, txid)
  end

  def turn_on() do
    GenServer.cast(__MODULE__, :turn_on)
  end

  def turn_off() do
    GenServer.cast(__MODULE__, :turn_off)
  end

  @doc """
  get a list of pending txs.
  """
  def list() do
    GenServer.call(__MODULE__, :list)
  end

  def init(state) do
    {:ok, state}
  end

  def handle_call(:list, _from, state = %{queue: q}) do
    {:reply, :queue.to_list(q), state}
  end

  def handle_cast({:pending, info}, state = %{queue: q}) do
    {:noreply, %{state | queue: :queue.in(info, q)}}
  end

  def handle_cast(:turn_on, state = %{status: :on}) do
    {:noreply, state}
  end

  def handle_cast(:turn_on, state = %{status: :off}) do
    send(self(), :broadcast)
    {:noreply, %{state | status: :on}}
  end

  def handle_cast(:turn_off, state) do
    {:noreply, %{state | status: :off}}
  end

  def handle_info(:broadcast, state = %{queue: q, status: :on}) do
    case :queue.out(q) do
      {{:value, {txid, hex_tx, _msg}}, q1} ->
        broadcast(txid, hex_tx)
        # IO.inspect :erlang.now()
        :timer.send_after(1_000, :broadcast)
        {:noreply, %{state | queue: q1}}

      _ ->
        {:noreply, %{state | status: :off}}
    end
  end

  def handle_info(:broadcast, state) do
    Logger.info("TxRepo is off.")
    {:noreply, state}
  end

  def handle_info(other, state) do
    Logger.error(inspect(other))
    {:noreply, state}
  end
end
