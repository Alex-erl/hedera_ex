defmodule Hedera.Rlp do
  @moduledoc """
  Minimal RLP (Recursive Length Prefix) encoder — Ethereum's serialization, used
  here to assemble EIP-1559 (type-2) transactions for Hedera's `EthereumTransaction`.

  Items are integers (encoded as their minimal big-endian byte string; `0` → the
  empty string), binaries (raw byte strings), or (nested) lists of items.
  """

  @doc """
  RLP-encode an item: an integer, a binary, or a (nested) list.

  ## Examples

      iex> Hedera.Rlp.encode("dog")
      <<0x83, ?d, ?o, ?g>>

      iex> Hedera.Rlp.encode(1024)
      <<0x82, 0x04, 0x00>>

      iex> Hedera.Rlp.encode(0)
      <<0x80>>

      iex> Hedera.Rlp.encode(["cat", "dog"])
      <<0xC8, 0x83, ?c, ?a, ?t, 0x83, ?d, ?o, ?g>>
  """
  @spec encode(integer() | binary() | list()) :: binary()
  def encode(item) when is_integer(item) and item >= 0, do: encode(int_to_bin(item))

  def encode(item) when is_binary(item), do: encode_bytes(item)

  def encode(items) when is_list(items) do
    payload = items |> Enum.map(&encode/1) |> IO.iodata_to_binary()
    encode_length(byte_size(payload), 0xC0) <> payload
  end

  # A single byte below 0x80 is its own encoding; otherwise a length prefix.
  defp encode_bytes(<<b>>) when b < 0x80, do: <<b>>
  defp encode_bytes(bytes), do: encode_length(byte_size(bytes), 0x80) <> bytes

  defp encode_length(len, offset) when len <= 55, do: <<offset + len>>

  defp encode_length(len, offset) do
    len_bytes = int_to_bin(len)
    <<offset + 55 + byte_size(len_bytes)>> <> len_bytes
  end

  @doc "The minimal big-endian byte string of a non-negative integer (`0` → `<<>>`)."
  @spec int_to_bin(non_neg_integer()) :: binary()
  def int_to_bin(0), do: <<>>
  def int_to_bin(n) when n > 0, do: :binary.encode_unsigned(n)
end
