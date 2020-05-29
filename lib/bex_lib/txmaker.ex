defmodule BexLib.Txmaker do
  # alias BexLib.Base58Check
  alias BexLib.Types.VarInteger
  alias BexLib.Types.VarString
  alias BexLib.Key
  alias BexLib.Crypto
  alias Bex.Wallet.Utxo
  alias Bex.Repo
  require Logger

  use Bitwise

  @sat_per_byte Decimal.cast(0.5)

  @doc """
  hex raw tx -> txid(hex string)
  """
  def get_txid_from_hex_tx(hex) do
    Crypto.double_sha256(Binary.from_hex(hex)) |> Binary.reverse() |> Binary.to_hex()
  end

  defp get_fee(n_in, n_out, opreturn) do
    estimate_tx_fee(n_in, n_out, true, opreturn)
  end

  defp len(x) when is_binary(x), do: byte_size(x)
  defp len(x) when is_list(x), do: length(x)

  defp to_bytes(x, size, endian) when is_integer(x) do
    s = 8 * size

    case endian do
      :big ->
        <<x::size(s)-big>>

      :little ->
        <<x::size(s)-little>>
    end
  end

  defp int_to_varint(x) do
    VarInteger.serialize(x)
  end

  defp hex_to_bytes(hex) do
    Binary.from_hex(hex)
  end

  defp double_sha256(x) do
    x |> sha256() |> sha256()
  end

  defp sha256(x), do: :crypto.hash(:sha256, x)

  defp join(list), do: IO.iodata_to_binary(list)

  defp construct_input_block(inputs) do
    for txin <- inputs do
      join([
        txin.txid,
        txin.txindex,
        txin.script_len,
        txin.script,
        txin.sequence
      ])
    end
    |> join()
  end

  defp construct_output_block(outputs) do
    Enum.map(outputs, fn output ->
      serialize_output(output)
    end)
    |> join()
  end

  defp serialize_output(output) do
    script =
      case output do
        %Utxo{lock_script: s} ->
          s

        {dest, _amount} ->
          [
            0x76,
            0xA9,
            0x14,
            Key.address_to_public_key_hash(dest),
            0x88,
            0xAC
          ]
          |> join()

        ## what is "safe" type: https://blog.moneybutton.com/2019/08/02/money-button-now-supports-safe-on-chain-data/
        %{type: "safe", data: data} ->
          safe_type_pkscript(data)

        %{type: "script", script: script} ->
          script
      end

    amount =
      case output do
        %Utxo{value: v} ->
          Decimal.to_integer(v)

        %{type: "safe"} ->
          0

        %{type: "script"} ->
          0
      end

    [
      amount |> to_bytes(8, :little),
      int_to_varint(len(script)),
      script
    ]
  end

  defp safe_type_pkscript(data) do
    data = if is_list(data), do: data, else: [data]

    [
      0,
      106,
      for(x <- data, do: [byte_size(x) |> op_push(), x])
    ]
    |> join()
  end

  defp op_push(size) when size <= 75, do: size

  defp op_push(size) do
    bytes = :binary.encode_unsigned(size, :little)

    case byte_size(bytes) do
      1 -> [0x4C, bytes]
      2 -> [0x4D, bytes]
      _ -> [0x4E, Binary.pad_trailing(bytes, 4)]
    end
  end

  defp newTxIn(script, script_len, txid, txindex, amount, pkbn) do
    %{
      script: script,
      script_len: script_len,
      txid: txid,
      txindex: txindex,
      amount: amount,
      private_key: pkbn
    }
  end

  defp sequence(n \\ 0xFFFFFFFF)
  defp sequence(nil), do: sequence()
  defp sequence(-1), do: sequence()

  defp sequence(n) when is_integer(n) and n >= 0 and n <= 0xFFFFFFFF,
    do: n |> to_bytes(4, :little)

  @doc """
  Params: utxos of input and output
  Return: 3 types of change.
  """
  def get_change(inputs, outputs, reserve_utxos \\ []) do
    opreturn =
      case Enum.find(outputs, fn x -> x.type == :data end) do
        nil -> false
        u -> u.lock_script
      end

    input_count = length(inputs)
    output_count = length(outputs)

    fee_with_change = get_fee(input_count, output_count + 1, opreturn)

    Logger.debug("fee: #{fee_with_change}")
    sum_of_inputs = Utxo.sum_of_value(inputs)
    sum_of_outputs = Utxo.sum_of_value(outputs)

    cond do
      Decimal.cmp(sum_of_inputs, Decimal.add(fee_with_change, sum_of_outputs)) == :lt ->
        if reserve_utxos == [] do
          :insufficient
        else
          get_change(
            hd(reserve_utxos) ++ inputs,
            outputs,
            tl(reserve_utxos)
          )
        end

      true ->
        change = Decimal.sub(sum_of_inputs, Decimal.add(fee_with_change, sum_of_outputs))

        if Decimal.cmp(change, 546) == :gt do
          {:change, change, inputs, outputs}
        else
          {:no_change, inputs, outputs}
        end
    end
  end

  ### Copied from libitx/bsv-ex https://github.com/libitx/bsv-ex/blob/master/lib/bsv/transaction/signature.ex
  @sighash_all 0x01
  @sighash_none 0x02
  @sighash_single 0x03
  @sighash_forkid 0x40
  @sighash_anyonecanpay 0x80

  @default_sighash @sighash_all ||| @sighash_forkid

  defguard sighash_all?(sighash_type)
           when (sighash_type &&& 31) == @sighash_all

  defguard sighash_none?(sighash_type)
           when (sighash_type &&& 31) == @sighash_none

  defguard sighash_single?(sighash_type)
           when (sighash_type &&& 31) == @sighash_single

  defguard sighash_forkid?(sighash_type)
           when (sighash_type &&& @sighash_forkid) != 0

  defguard sighash_anyone_can_pay?(sighash_type)
           when (sighash_type &&& @sighash_anyonecanpay) != 0

  @doc """
  params:
    - list of utxos
    - list of outputs:
      - {address, amount(Decimal satoshis)}
      - %{type: "safe", data: binary or list of binary}
      - %{type: "script", script: binary script}

  options:
    - sequence: integer
    - locktime: integer
    - sighash_types: [integer]

    if all inputs in a transaction have sequence equal to UINT_MAX,
    then locktime is ignored.

    if locktime < 500_000_000, the integer is interpreted
    as the block height after which this transaction can be accepted.
    Otherwise the integer is interpreted as the UNIX timestamp after which
    this transaction can be included in a block.
  """
  def create_p2pkh_transaction(inputs, outputs, opts \\ [])
      when is_list(inputs) and is_list(outputs) do
    sighash_types = opts[:sighash_types] || for _ <- inputs, do: @default_sighash

    version = 0x01 |> to_bytes(4, :little)

    lock_time = opts[:locktime] || 0x00

    ## FIXME every input has own sequence
    sequence = sequence(opts[:sequence])

    lock_time = lock_time |> to_bytes(4, :little)

    input_count = int_to_varint(len(inputs))
    output_count = int_to_varint(len(outputs))

    output_block = construct_output_block(outputs)

    inputs_indexes = Enum.with_index(inputs)

    inputs =
      for {%Utxo{} = input, index} <- inputs_indexes do
        private_key_bn = Repo.preload(input, :private_key).private_key.bn
        script = input.lock_script
        script_len = int_to_varint(len(script))
        txid = hex_to_bytes(input.txid) |> Binary.reverse()
        txindex = input.index |> to_bytes(4, :little)
        amount = input.value |> Decimal.to_integer() |> to_bytes(8, :little)

        sighash = Enum.at(sighash_types, index)

        txin = newTxIn(script, script_len, txid, txindex, amount, private_key_bn)

        hashPrevouts = get_prevouts_hash(inputs, sighash)
        hashSequence = get_sequence_hash(inputs, sighash, sequence)
        hashOutputs = get_outputs_hash(outputs, index, sighash)

        private_key = txin.private_key
        public_key = Key.private_key_to_public_key(private_key)
        public_key_len = len(public_key) |> to_bytes(1, :little)

        to_be_hashed =
          join([
            version,
            hashPrevouts,
            hashSequence,
            txin.txid,
            txin.txindex,
            txin.script_len,
            txin.script,
            txin.amount,
            sequence,
            hashOutputs,
            lock_time,
            sighash |> to_bytes(4, :little)
          ])

        hashed = sha256(to_be_hashed)

        option_secret = opts[:secret_for_k]

        signature =
          if option_secret do
            BexLib.Secp256k1.sign_with_secret_for_r(private_key, hashed, option_secret)
          else
            Crypto.sign(private_key, hashed)
          end <> <<sighash>>

        script_sig =
          join([
            len(signature) |> to_bytes(1, :little),
            signature,
            public_key_len,
            public_key
          ])

        %{
          txin
          | script: script_sig,
            script_len: int_to_varint(len(script_sig))
        }
        |> Map.put(:sequence, sequence)
      end

    join([
      version,
      input_count,
      construct_input_block(inputs),
      output_count,
      output_block,
      lock_time
    ])
  end

  defp get_prevouts_hash(_inputs, sighash_type)
       when sighash_anyone_can_pay?(sighash_type),
       do: :binary.copy(<<0>>, 32)

  defp get_prevouts_hash(inputs, _sighash_type) do
    double_sha256(join(for i <- inputs, do: [hex_to_bytes(i.txid) |> Binary.reverse(), i.index |> to_bytes(4, :little)] ))
  end

  defp get_sequence_hash(_inputs, sighash_type, _)
       when sighash_anyone_can_pay?(sighash_type) or
              sighash_single?(sighash_type) or
              sighash_none?(sighash_type),
       do: :binary.copy(<<0>>, 32)

  defp get_sequence_hash(inputs, _sighash_type, sequence) do
    double_sha256(join(for _i <- inputs, do: sequence))
  end

  defp get_outputs_hash(outputs, index, sighash_type)
       when sighash_single?(sighash_type) and
              index < length(outputs) do
    outputs
    |> Enum.at(index)
    |> serialize_output()
    |> double_sha256()
  end

  defp get_outputs_hash(outputs, _index, sighash_type)
       when not sighash_none?(sighash_type) do
    output_block = construct_output_block(outputs)
    double_sha256(output_block)
  end

  defp get_outputs_hash(_outputs, _index, _sighash_type),
    do: :binary.copy(<<0>>, 32)

  @doc """
  n_out will including opreturn output for falut tolerance.
  """
  def estimate_tx_fee(n_in, n_out, compressed, op_return) do
    outputs_size =
      if op_return == false do
        n_out * 34
      else
        # p2pkh outputs
        # value
        (n_out - 1) * 34 +
          8 +
          byte_size(VarString.serialize(op_return))
      end

    # version
    # input count length
    # output count length
    # grand total size of op_return outputs(s) and related field(s)
    # time lock
    estimated_size =
      4 +
        n_in * if(compressed, do: 148, else: 180) +
        len(int_to_varint(n_in)) +
        outputs_size +
        len(int_to_varint(n_out)) +
        4

    get_fee_from_size(estimated_size)
  end

  def get_fee_from_size(size) do
    size =
      if is_float(size) do
        Decimal.from_float(size)
      else
        Decimal.cast(size)
      end

    # 体积乘以费率得到估计的手续费
    Decimal.mult(size, @sat_per_byte) |> Decimal.round(0, :up)
  end

  def get_txid_from_binary_tx(bn) do
    Crypto.double_sha256(bn) |> Binary.reverse() |> Binary.to_hex()
  end
end
