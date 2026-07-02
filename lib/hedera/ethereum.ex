defmodule Hedera.Ethereum do
  @moduledoc """
  EIP-1559 (type-2) Ethereum transaction assembly + signing, for Hedera's
  `EthereumTransaction` (Hedera runs the EVM; a signed Ethereum tx is relayed and
  executed against its EVM address).

  `sign_eip1559/2` RLP-encodes the transaction, signs `keccak256` of it with a
  secp256k1 key (the Hedera ECDSA path is exactly Ethereum's), recovers the
  `yParity`, and returns the complete signed `ethereum_data` — the bytes that go
  into `Hedera.Transaction.ethereum/1` / `Hedera.Client.send_ethereum_transaction/3`.

  Chain id defaults to Hedera testnet (`296`; mainnet is `295`).
  """

  alias Hedera.{PrivateKey, PublicKey, Rlp}
  alias Hedera.Crypto.{Keccak, Secp256k1}

  @type_2 <<0x02>>
  @default_chain_id 296

  @doc """
  Build + sign an EIP-1559 transaction, returning the `ethereum_data` bytes
  (`0x02 ‖ rlp([...])`). Params (a map): `:chain_id` (default #{@default_chain_id}),
  `:nonce`, `:max_priority_fee_per_gas`, `:max_fee_per_gas`, `:gas_limit`, `:to`
  (a 20-byte address, `"0x…"` hex, or `nil`/absent for contract creation),
  `:value`, `:data` (call data, bytes or `"0x…"`). Access lists are empty.

  Raises `ArgumentError` when a required gas field is missing/negative or a `:to`
  address / `:data` hex string is malformed.
  """
  @spec sign_eip1559(map(), PrivateKey.t()) :: binary()
  def sign_eip1559(params, %PrivateKey{type: :ecdsa_secp256k1} = key) do
    fields = base_fields(params)
    unsigned = @type_2 <> Rlp.encode(fields)

    <<r::binary-size(32), s::binary-size(32)>> = sig = PrivateKey.sign(key, unsigned)
    z = Keccak.hash256(unsigned)
    pub = PublicKey.to_bytes(PrivateKey.public_key(key))
    y_parity = Secp256k1.recovery_id(sig, z, pub)

    signed = fields ++ [y_parity, :binary.decode_unsigned(r), :binary.decode_unsigned(s)]
    @type_2 <> Rlp.encode(signed)
  end

  # The 9 signable fields, in EIP-1559 order.
  defp base_fields(p) do
    [
      Map.get(p, :chain_id, @default_chain_id),
      Map.get(p, :nonce, 0),
      fetch_int(p, :max_priority_fee_per_gas),
      fetch_int(p, :max_fee_per_gas),
      fetch_int(p, :gas_limit),
      address(Map.get(p, :to)),
      Map.get(p, :value, 0),
      bytes(Map.get(p, :data, <<>>)),
      []
    ]
  end

  defp fetch_int(p, key) do
    case Map.fetch(p, key) do
      {:ok, v} when is_integer(v) and v >= 0 -> v
      _ -> raise ArgumentError, "EIP-1559 requires a non-negative integer #{inspect(key)}"
    end
  end

  # A recipient address: a 20-byte binary, a "0x…"-hex string, or nil (→ empty,
  # meaning contract creation).
  defp address(nil), do: <<>>
  defp address(<<addr::binary-size(20)>>), do: addr
  defp address("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
  defp address(hex) when is_binary(hex), do: Base.decode16!(hex, case: :mixed)

  defp bytes(nil), do: <<>>
  defp bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
  defp bytes(bin) when is_binary(bin), do: bin
end
