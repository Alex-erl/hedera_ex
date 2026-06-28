defmodule Hedera.Crypto.Secp256k1 do
  @moduledoc """
  secp256k1 helpers for Hedera's ECDSA signature convention: signatures are the
  64-byte raw `r ‖ s` form with `s` normalized to the lower half of the curve
  order (low-S, as required by Hedera/Ethereum), and public keys are the 33-byte
  compressed form on the wire. OpenSSL (via OTP `:crypto`) produces DER
  signatures and uncompressed points, which these functions convert.
  """

  # secp256k1 group order n, and n/2 for the low-S check.
  @n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @half div(@n, 2)

  @doc "Convert a DER ECDSA signature to canonical 64-byte `r ‖ s` (low-S)."
  @spec der_to_raw(binary()) :: binary()
  def der_to_raw(<<0x30, _len, 0x02, rlen, rest::binary>>) do
    <<r::binary-size(^rlen), 0x02, slen, s::binary-size(slen)>> = rest
    r_int = :binary.decode_unsigned(r)
    s_int = low_s(:binary.decode_unsigned(s))
    pad32(r_int) <> pad32(s_int)
  end

  @doc "Convert a canonical 64-byte `r ‖ s` signature to DER."
  @spec raw_to_der(binary()) :: binary()
  def raw_to_der(<<r::binary-size(32), s::binary-size(32)>>) do
    r_der = der_integer(r)
    s_der = der_integer(s)
    body = r_der <> s_der
    <<0x30, byte_size(body)>> <> body
  end

  @doc "Compress an uncompressed secp256k1 point (0x04 ‖ X ‖ Y) to 33 bytes."
  @spec compress(binary()) :: binary()
  def compress(<<0x04, x::binary-size(32), y::binary-size(32)>>) do
    prefix = if rem(:binary.decode_unsigned(y), 2) == 0, do: 0x02, else: 0x03
    <<prefix>> <> x
  end

  def compress(<<prefix, _::binary-size(32)>> = compressed) when prefix in [0x02, 0x03],
    do: compressed

  defp low_s(s) when s > @half, do: @n - s
  defp low_s(s), do: s

  defp pad32(int) do
    bytes = :binary.encode_unsigned(int)
    :binary.copy(<<0>>, 32 - byte_size(bytes)) <> bytes
  end

  # DER INTEGER: big-endian, minimal, with a 0x00 sign byte when the MSB is set.
  defp der_integer(bytes) do
    trimmed = trim_leading_zeros(bytes)

    value =
      case trimmed do
        <<msb, _::binary>> when msb >= 0x80 -> <<0x00>> <> trimmed
        _ -> trimmed
      end

    <<0x02, byte_size(value)>> <> value
  end

  defp trim_leading_zeros(<<0, rest::binary>>) when byte_size(rest) > 0,
    do: trim_leading_zeros(rest)

  defp trim_leading_zeros(bytes), do: bytes
end
