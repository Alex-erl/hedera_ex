defmodule Hedera.Proto do
  @moduledoc """
  Minimal protobuf (proto3) wire-format encoder — varints, tags, and
  length-delimited fields. Enough to build the small set of Hedera messages the
  SDK needs, with no codegen dependency. (A future milestone may switch to
  protoc-generated modules from the canonical Hedera `.proto` files.)
  """
  import Bitwise

  @doc """
  Encode a non-negative integer as a base-128 varint.

  ## Examples

      iex> Hedera.Proto.varint(300)
      <<0xAC, 0x02>>

      iex> Hedera.Proto.varint(0)
      <<0x00>>
  """
  @spec varint(non_neg_integer()) :: binary()
  def varint(n) when n >= 0 and n < 0x80, do: <<n>>
  def varint(n) when n >= 0, do: <<bor(0x80, band(n, 0x7F))>> <> varint(n >>> 7)

  @doc "Encode a field tag (field number + wire type)."
  @spec tag(non_neg_integer(), 0..5) :: binary()
  def tag(field, wire_type), do: varint(bor(field <<< 3, wire_type))

  @doc "Encode a varint (wire type 0) field."
  @spec varint_field(non_neg_integer(), non_neg_integer()) :: binary()
  def varint_field(field, value), do: tag(field, 0) <> varint(value)

  @doc """
  Encode a signed `sint64` (ZigZag) field — used e.g. for transfer amounts.

  ## Examples

      iex> Hedera.Proto.sint64_field(2, -1)
      <<0x10, 0x01>>

      iex> Hedera.Proto.sint64_field(2, 1)
      <<0x10, 0x02>>
  """
  @spec sint64_field(non_neg_integer(), integer()) :: binary()
  def sint64_field(field, value), do: tag(field, 0) <> varint(zigzag(value))

  defp zigzag(n) when n >= 0, do: n * 2
  defp zigzag(n), do: -n * 2 - 1

  @doc "Encode a length-delimited (wire type 2) field: bytes, strings, or sub-messages."
  @spec bytes_field(non_neg_integer(), binary()) :: binary()
  def bytes_field(field, bytes), do: tag(field, 2) <> varint(byte_size(bytes)) <> bytes

  @doc "Like `bytes_field/2`, but emit nothing for `nil` (proto3 omits unset fields)."
  @spec maybe_bytes_field(non_neg_integer(), binary() | nil) :: binary()
  def maybe_bytes_field(_field, nil), do: <<>>
  def maybe_bytes_field(field, bytes), do: bytes_field(field, bytes)

  @doc """
  Decode a protobuf message into a list of `{field_number, wire_type, value}` —
  varint values as integers, length-delimited values as binaries. Supports the
  wire types this SDK emits (0 and 2) plus 64/32-bit (1 and 5).
  """
  @spec decode(binary()) :: [{non_neg_integer(), 0..5, integer() | binary()}]
  def decode(bin), do: decode(bin, [])

  @doc "First value of `field` in a decoded message, or `nil`."
  @spec field([{non_neg_integer(), 0..5, term()}], non_neg_integer()) ::
          integer() | binary() | nil
  def field(decoded, field) do
    # decoded values are always integers or binaries (both truthy, incl. 0 and
    # ""), so find_value's falsy-skip can't swallow a real value here.
    Enum.find_value(decoded, fn
      {^field, _wire, value} -> value
      _ -> false
    end)
  end

  @doc "Decode a packed run of varints (e.g. a proto3 `repeated int64` field body)."
  @spec decode_varints(binary()) :: [non_neg_integer()]
  def decode_varints(bin) when is_binary(bin), do: decode_varints(bin, [])

  defp decode_varints(<<>>, acc), do: Enum.reverse(acc)

  defp decode_varints(bin, acc) do
    {value, rest} = take_varint(bin)
    decode_varints(rest, [value | acc])
  end

  defp decode(<<>>, acc), do: Enum.reverse(acc)

  defp decode(bin, acc) do
    {tag, rest} = take_varint(bin)
    field = tag >>> 3
    wire = band(tag, 0x07)

    {value, rest2} =
      case wire do
        0 -> take_varint(rest)
        2 -> take_bytes(rest)
        1 -> take_fixed(rest, 8)
        5 -> take_fixed(rest, 4)
        # wire types 3/4 are deprecated groups the SDK never emits; a corrupt
        # tag lands here too. Fail loudly rather than mis-parse the rest.
        other -> raise ArgumentError, "unsupported protobuf wire type #{other} at field #{field}"
      end

    decode(rest2, [{field, wire, value} | acc])
  end

  defp take_varint(bin), do: take_varint(bin, 0, 0)

  defp take_varint(<<1::1, chunk::7, rest::binary>>, shift, acc),
    do: take_varint(rest, shift + 7, bor(acc, chunk <<< shift))

  defp take_varint(<<0::1, chunk::7, rest::binary>>, shift, acc),
    do: {bor(acc, chunk <<< shift), rest}

  defp take_bytes(bin) do
    {len, rest} = take_varint(bin)
    <<value::binary-size(^len), tail::binary>> = rest
    {value, tail}
  end

  defp take_fixed(bin, n) do
    <<value::binary-size(^n), tail::binary>> = bin
    {value, tail}
  end
end
