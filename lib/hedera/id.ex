defmodule Hedera.Id do
  @moduledoc """
  Shared implementation for Hedera entity identifiers of the form
  `shard.realm.num` — `Hedera.AccountId`, `ContractId`, `FileId`, `ScheduleId`,
  `TokenId`, and `TopicId`.

  `use Hedera.Id` injects the struct (`shard`/`realm`/`num`, `num` required), its
  `@type t`, and the `parse/1`, `to_string/1`, and `to_proto/1` functions — all
  identical across the entity types (the wire encoding is `shard`=1, `realm`=2,
  `num`=3 for every one).
  """

  alias Hedera.Proto

  @doc false
  defmacro __using__(_opts) do
    quote do
      @enforce_keys [:num]
      defstruct shard: 0, realm: 0, num: nil

      @type t :: %__MODULE__{
              shard: non_neg_integer(),
              realm: non_neg_integer(),
              num: non_neg_integer()
            }

      @doc """
      Parse `"shard.realm.num"` (e.g. `"0.0.1001"`) into a struct. Raises
      `ArgumentError` on a malformed id — call this with known-format ids; for
      untrusted input, guard with a `rescue` or validate first.
      """
      @spec parse(binary()) :: t()
      def parse(string) when is_binary(string), do: Hedera.Id.parse!(__MODULE__, string)

      @doc ~S(Format as `"shard.realm.num"`.)
      @spec to_string(t()) :: binary()
      def to_string(%__MODULE__{shard: s, realm: r, num: n}), do: "#{s}.#{r}.#{n}"

      @doc "Encode as the entity's protobuf message (`shard`=1, `realm`=2, `num`=3)."
      @spec to_proto(t()) :: binary()
      def to_proto(%__MODULE__{shard: s, realm: r, num: n}) do
        Proto.varint_field(1, s) <> Proto.varint_field(2, r) <> Proto.varint_field(3, n)
      end
    end
  end

  @doc """
  Parse `"shard.realm.num"` into `struct(mod, …)`, or raise `ArgumentError` with a
  clear message. Shared by every identifier module's `parse/1`.
  """
  @spec parse!(module(), binary()) :: struct()
  def parse!(mod, string) do
    with [s, r, n] <- String.split(string, "."),
         {shard, ""} when shard >= 0 <- Integer.parse(s),
         {realm, ""} when realm >= 0 <- Integer.parse(r),
         {num, ""} when num >= 0 <- Integer.parse(n) do
      struct(mod, shard: shard, realm: realm, num: num)
    else
      _ -> raise ArgumentError, ~s(invalid id #{inspect(string)}: expected "shard.realm.num" of non-negative integers)
    end
  end
end
