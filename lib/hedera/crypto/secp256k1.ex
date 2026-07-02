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

  # Field prime p (p ≡ 3 mod 4, so a square root is a^((p+1)/4)), curve b (a = 0),
  # and the generator G — for public-key recovery (there is no ecrecover in OTP).
  @p 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
  @b 7
  @gx 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
  @gy 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8

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

  @doc """
  The EIP-1559 recovery id (`yParity`, 0 or 1) for a signature `<<r::256, s::256>>`
  over the 32-byte message hash `z`, given the signer's public key (33-byte
  compressed or 65-byte uncompressed). Recovers the public key for each candidate
  parity and returns the one that reproduces the signer — or `:error`.
  """
  @spec recovery_id(binary(), binary(), binary()) :: 0 | 1 | :error
  def recovery_id(<<r::binary-size(32), s::binary-size(32)>>, z, public_key) when byte_size(z) == 32 do
    want = compress(public_key)
    ri = :binary.decode_unsigned(r)
    si = :binary.decode_unsigned(s)
    zi = :binary.decode_unsigned(z)

    Enum.find(0..1, :error, fn recid ->
      case recover(ri, si, zi, recid) do
        {x, y} -> compress(<<0x04>> <> pad32(x) <> pad32(y)) == want
        :error -> false
      end
    end)
  end

  @doc "Recover the public key point `{x, y}` from `(r, s, z, recid)`, or `:error`."
  @spec recover(integer(), integer(), integer(), 0 | 1) :: {integer(), integer()} | :error
  def recover(r, s, z, recid) when r > 0 and r < @n and s > 0 and s < @n do
    ysq = mod(r * r * r + @b, @p)
    beta = pow_mod(ysq, div(@p + 1, 4), @p)
    # is beta a valid square root (point on curve)? if not, r is not a valid R.x
    if mod(beta * beta, @p) != ysq do
      :error
    else
      y = if rem(beta, 2) == recid, do: beta, else: @p - beta
      big_r = {r, y}
      r_inv = pow_mod(r, @n - 2, @n)
      # Q = r⁻¹ · (s·R − z·G)
      s_r = mul(s, big_r)
      z_g = mul(mod(z, @n), {@gx, @gy})
      diff = add(s_r, negate(z_g))
      mul(r_inv, diff)
    end
  end

  def recover(_r, _s, _z, _recid), do: :error

  # --- secp256k1 point arithmetic over F_p (affine; :infinity is the identity) --

  defp negate(:infinity), do: :infinity
  defp negate({x, y}), do: {x, mod(-y, @p)}

  defp add(:infinity, q), do: q
  defp add(p, :infinity), do: p

  defp add({x1, y1}, {x2, y2}) do
    cond do
      x1 == x2 and mod(y1 + y2, @p) == 0 -> :infinity
      x1 == x2 and y1 == y2 -> double({x1, y1})
      true ->
        lam = mod((y2 - y1) * pow_mod(mod(x2 - x1, @p), @p - 2, @p), @p)
        x3 = mod(lam * lam - x1 - x2, @p)
        {x3, mod(lam * (x1 - x3) - y1, @p)}
    end
  end

  defp double({_x, 0}), do: :infinity

  defp double({x, y}) do
    lam = mod(3 * x * x * pow_mod(mod(2 * y, @p), @p - 2, @p), @p)
    x3 = mod(lam * lam - 2 * x, @p)
    {x3, mod(lam * (x - x3) - y, @p)}
  end

  defp mul(0, _point), do: :infinity
  defp mul(_k, :infinity), do: :infinity

  defp mul(k, point) when k > 0, do: mul(k, point, :infinity)

  defp mul(0, _point, acc), do: acc

  defp mul(k, point, acc) do
    acc = if rem(k, 2) == 1, do: add(acc, point), else: acc
    mul(div(k, 2), double(point), acc)
  end

  defp mod(a, m), do: rem(rem(a, m) + m, m)

  # modular exponentiation (also used for inverses via Fermat: a^(m-2) mod m)
  defp pow_mod(_base, 0, _m), do: 1

  defp pow_mod(base, exp, m) do
    b = mod(base, m)
    if rem(exp, 2) == 1,
      do: mod(b * pow_mod(mod(b * b, m), div(exp, 2), m), m),
      else: pow_mod(mod(b * b, m), div(exp, 2), m)
  end

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
