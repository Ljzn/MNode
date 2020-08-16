defmodule BexLib.NaiveSignature do
  @moduledoc """
  The signature algorithm be used to do signing on-chain.
  """
  import BexLib.Crypto, only: [sha256: 1, verify: 3]
  alias BexLib.DERSig
  alias BexLib.Key

  def hash(x) do
    sha256(x) |> :binary.decode_unsigned()
  end

  @doc """
  m: msg binary
  s1: privkey integer
  """
  def onchain_sign(m, s1) do
    gx = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
    # gy = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
    n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

    # p1x = gx * s1
    # p1y = gy * s1

    # r = k * gx
    r = gx

    s = rem(hash(m) + s1 * r, n)

    # m
    # |> hash()
    # s1
    # |> *(r)
    # +
    # n
    # rem

    DERSig.encode(r, s)
  end

  def test() do
    # k = 1
    m = "hello"
    s1 = 0x9060D325C176786A222D63E77D209269009C07C1A588FBEDD8C744204016C834

    priv = s1 |> :binary.encode_unsigned()
    pub = priv |> Key.private_key_to_public_key()

    signature = onchain_sign(m, s1)

    verify(signature, m, pub)
  end
end
