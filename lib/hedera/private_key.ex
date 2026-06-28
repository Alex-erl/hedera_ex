defmodule Hedera.PrivateKey do
  @moduledoc """
  A Hedera private key — Ed25519 or ECDSA secp256k1.

  Signing follows Hedera's conventions: Ed25519 signs the message bytes directly;
  ECDSA secp256k1 signs the **Keccak-256** digest of the message and returns the
  canonical 64-byte `r ‖ s` (low-S) signature.
  """

  alias Hedera.Crypto.{Keccak, Secp256k1}
  alias Hedera.PublicKey

  @enforce_keys [:type, :bytes]
  defstruct [:type, :bytes]

  @type key_type :: :ed25519 | :ecdsa_secp256k1
  @type t :: %__MODULE__{type: key_type(), bytes: binary()}

  @doc "Generate a new Ed25519 private key."
  @spec generate_ed25519() :: t()
  def generate_ed25519 do
    {_pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    %__MODULE__{type: :ed25519, bytes: priv}
  end

  @doc "Generate a new ECDSA secp256k1 private key."
  @spec generate_ecdsa() :: t()
  def generate_ecdsa do
    {_pub, priv} = :crypto.generate_key(:ecdh, :secp256k1)
    %__MODULE__{type: :ecdsa_secp256k1, bytes: pad32(priv)}
  end

  @doc "Parse a 32-byte Ed25519 private key from a hex string (`0x` optional)."
  @spec from_string_ed25519(binary()) :: t()
  def from_string_ed25519(hex), do: %__MODULE__{type: :ed25519, bytes: decode_hex(hex)}

  @doc "Parse a 32-byte ECDSA secp256k1 private key from a hex string (`0x` optional)."
  @spec from_string_ecdsa(binary()) :: t()
  def from_string_ecdsa(hex), do: %__MODULE__{type: :ecdsa_secp256k1, bytes: decode_hex(hex)}

  @doc "Derive the corresponding public key."
  @spec public_key(t()) :: PublicKey.t()
  def public_key(%__MODULE__{type: :ed25519, bytes: priv}) do
    {pub, _} = :crypto.generate_key(:eddsa, :ed25519, priv)
    %PublicKey{type: :ed25519, point: pub}
  end

  def public_key(%__MODULE__{type: :ecdsa_secp256k1, bytes: priv}) do
    {pub, _} = :crypto.generate_key(:ecdh, :secp256k1, priv)
    %PublicKey{type: :ecdsa_secp256k1, point: pub}
  end

  @doc "Sign a message with Hedera's per-key-type convention."
  @spec sign(t(), binary()) :: binary()
  def sign(%__MODULE__{type: :ed25519, bytes: priv}, message) do
    :crypto.sign(:eddsa, :none, message, [priv, :ed25519])
  end

  def sign(%__MODULE__{type: :ecdsa_secp256k1, bytes: priv}, message) do
    digest = Keccak.hash256(message)
    der = :crypto.sign(:ecdsa, :sha256, {:digest, digest}, [priv, :secp256k1])
    Secp256k1.der_to_raw(der)
  end

  @doc "Lowercase hex (no `0x`) of the raw private key bytes."
  @spec to_string(t()) :: binary()
  def to_string(%__MODULE__{bytes: bytes}), do: Base.encode16(bytes, case: :lower)

  defp decode_hex(hex) do
    hex |> String.replace_prefix("0x", "") |> Base.decode16!(case: :mixed)
  end

  defp pad32(bytes) when byte_size(bytes) == 32, do: bytes
  defp pad32(bytes), do: :binary.copy(<<0>>, 32 - byte_size(bytes)) <> bytes
end
