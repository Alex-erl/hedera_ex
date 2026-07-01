defmodule Hedera.PublicKey do
  @moduledoc """
  A Hedera public key — Ed25519 (32-byte point) or ECDSA secp256k1 (stored as
  the uncompressed point for crypto operations, serialized as the 33-byte
  compressed form for the Hedera wire protocol).
  """

  alias Hedera.Crypto.{Keccak, Secp256k1}
  alias Hedera.Proto

  @enforce_keys [:type, :point]
  defstruct [:type, :point]

  @type t :: %__MODULE__{type: Hedera.PrivateKey.key_type(), point: binary()}

  @doc "Verify a signature produced by the matching private key."
  @spec verify(t(), binary(), binary()) :: boolean()
  def verify(%__MODULE__{type: :ed25519, point: pub}, message, signature) do
    :crypto.verify(:eddsa, :none, message, signature, [pub, :ed25519])
  end

  def verify(%__MODULE__{type: :ecdsa_secp256k1, point: pub}, message, signature)
      when byte_size(signature) == 64 do
    digest = Keccak.hash256(message)
    der = Secp256k1.raw_to_der(signature)
    :crypto.verify(:ecdsa, :sha256, {:digest, digest}, der, [pub, :secp256k1])
  rescue
    _ -> false
  end

  @doc """
  Raw public-key bytes in Hedera wire form: Ed25519 → 32 bytes; ECDSA → 33-byte
  compressed point.
  """
  @spec to_bytes(t()) :: binary()
  def to_bytes(%__MODULE__{type: :ed25519, point: point}), do: point
  def to_bytes(%__MODULE__{type: :ecdsa_secp256k1, point: point}), do: Secp256k1.compress(point)

  @doc "Lowercase hex of the wire-form public key."
  @spec to_string(t()) :: binary()
  def to_string(%__MODULE__{} = key), do: key |> to_bytes() |> Base.encode16(case: :lower)

  @doc """
  Encode as a Hedera `Key` protobuf message: Ed25519 in field 2, ECDSA
  secp256k1 (compressed) in field 7. Used wherever a transaction body expects a
  `Key` (admin/supply/kyc/freeze/wipe keys, etc.).
  """
  @spec to_key_proto(t()) :: binary()
  def to_key_proto(%__MODULE__{type: :ed25519} = key), do: Proto.bytes_field(2, to_bytes(key))

  def to_key_proto(%__MODULE__{type: :ecdsa_secp256k1} = key),
    do: Proto.bytes_field(7, to_bytes(key))
end
