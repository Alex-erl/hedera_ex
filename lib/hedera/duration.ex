defmodule Hedera.Duration do
  @moduledoc "A Hedera `Duration` in whole seconds (e.g. a transaction's valid window)."

  alias Hedera.Proto

  @enforce_keys [:seconds]
  defstruct [:seconds]

  @type t :: %__MODULE__{seconds: integer()}

  @doc "Encode as a Hedera `Duration` protobuf message (seconds = field 1)."
  @spec to_proto(t()) :: binary()
  def to_proto(%__MODULE__{seconds: s}), do: Proto.varint_field(1, s)
end
