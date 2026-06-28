defmodule Hedera.Crypto.Keccak do
  @moduledoc """
  Pure-Elixir Keccak-256 (the pre-NIST padding used by Ethereum and Hedera for
  ECDSA secp256k1 signing — distinct from SHA3-256, which uses a different
  domain-separation byte). No NIF, no external dependency.
  """
  import Bitwise

  @mask 0xFFFFFFFFFFFFFFFF
  @rate 136

  @rc {
    0x0000000000000001,
    0x0000000000008082,
    0x800000000000808A,
    0x8000000080008000,
    0x000000000000808B,
    0x0000000080000001,
    0x8000000080008081,
    0x8000000000008009,
    0x000000000000008A,
    0x0000000000000088,
    0x0000000080008009,
    0x000000008000000A,
    0x000000008000808B,
    0x800000000000008B,
    0x8000000000008089,
    0x8000000000008003,
    0x8000000000008002,
    0x8000000000000080,
    0x000000000000800A,
    0x800000008000000A,
    0x8000000080008081,
    0x8000000000008080,
    0x0000000080000001,
    0x8000000080008008
  }

  @rotc {1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20,
         44}
  @piln {10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1}

  @doc "Keccak-256 digest (32 bytes) of a binary."
  @spec hash256(binary()) :: binary()
  def hash256(data) when is_binary(data) do
    data
    |> pad()
    |> absorb(Tuple.duplicate(0, 25))
    |> squeeze()
  end

  defp pad(data) do
    q = @rate - rem(byte_size(data), @rate)

    padding =
      case q do
        1 -> <<0x81>>
        _ -> <<0x01>> <> <<0::size((q - 2) * 8)>> <> <<0x80>>
      end

    data <> padding
  end

  defp absorb(<<>>, state), do: state

  defp absorb(<<block::binary-size(@rate), rest::binary>>, state) do
    state =
      Enum.reduce(0..16, state, fn k, st ->
        <<lane::little-unsigned-64>> = binary_part(block, k * 8, 8)
        put_elem(st, k, bxor(elem(st, k), lane))
      end)
      |> permute()

    absorb(rest, state)
  end

  defp squeeze(state) do
    for k <- 0..3, into: <<>>, do: <<elem(state, k)::little-unsigned-64>>
  end

  defp permute(state), do: Enum.reduce(0..23, state, &round_f(&2, elem(@rc, &1)))

  defp round_f(a, rc) do
    a |> theta() |> rho_pi() |> chi() |> iota(rc)
  end

  defp theta(a) do
    bc =
      for i <- 0..4 do
        elem(a, i)
        |> bxor(elem(a, i + 5))
        |> bxor(elem(a, i + 10))
        |> bxor(elem(a, i + 15))
        |> bxor(elem(a, i + 20))
      end

    Enum.reduce(0..4, a, fn x, a ->
      t = bxor(Enum.at(bc, rem(x + 4, 5)), rotl(Enum.at(bc, rem(x + 1, 5)), 1))
      Enum.reduce(0..4, a, fn y, a -> put_elem(a, x + 5 * y, bxor(elem(a, x + 5 * y), t)) end)
    end)
  end

  defp rho_pi(a) do
    {a, _t} =
      Enum.reduce(0..23, {a, elem(a, 1)}, fn i, {a, t} ->
        j = elem(@piln, i)
        prev = elem(a, j)
        {put_elem(a, j, rotl(t, elem(@rotc, i))), prev}
      end)

    a
  end

  defp chi(a) do
    Enum.reduce(0..4, a, fn row, a ->
      j = row * 5
      bc = {elem(a, j), elem(a, j + 1), elem(a, j + 2), elem(a, j + 3), elem(a, j + 4)}

      Enum.reduce(0..4, a, fn i, a ->
        v = bxor(elem(bc, i), band(bnot(elem(bc, rem(i + 1, 5))), elem(bc, rem(i + 2, 5))))
        put_elem(a, j + i, band(v, @mask))
      end)
    end)
  end

  defp iota(a, rc), do: put_elem(a, 0, bxor(elem(a, 0), rc))

  defp rotl(v, n), do: band(bor(v <<< n, v >>> (64 - n)), @mask)
end
