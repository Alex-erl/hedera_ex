defmodule Hedera.Proto do
  @moduledoc """
  Minimal protobuf (proto3) wire-format encoder — varints, tags, and
  length-delimited fields. Enough to build the small set of Hedera messages the
  SDK needs, with no codegen dependency. (A future milestone may switch to
  protoc-generated modules from the canonical Hedera `.proto` files.)
  """
  import Bitwise

  @doc "Encode a non-negative integer as a base-128 varint."
  @spec varint(non_neg_integer()) :: binary()
  def varint(n) when n >= 0 and n < 0x80, do: <<n>>
  def varint(n) when n >= 0, do: <<bor(0x80, band(n, 0x7F))>> <> varint(n >>> 7)

  @doc "Encode a field tag (field number + wire type)."
  @spec tag(non_neg_integer(), 0..5) :: binary()
  def tag(field, wire_type), do: varint(bor(field <<< 3, wire_type))

  @doc "Encode a varint (wire type 0) field."
  @spec varint_field(non_neg_integer(), non_neg_integer()) :: binary()
  def varint_field(field, value), do: tag(field, 0) <> varint(value)

  @doc "Encode a length-delimited (wire type 2) field: bytes, strings, or sub-messages."
  @spec bytes_field(non_neg_integer(), binary()) :: binary()
  def bytes_field(field, bytes), do: tag(field, 2) <> varint(byte_size(bytes)) <> bytes

  @doc "Like `bytes_field/2`, but emit nothing for `nil` (proto3 omits unset fields)."
  @spec maybe_bytes_field(non_neg_integer(), binary() | nil) :: binary()
  def maybe_bytes_field(_field, nil), do: <<>>
  def maybe_bytes_field(field, bytes), do: bytes_field(field, bytes)
end
