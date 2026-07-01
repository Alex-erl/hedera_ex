defmodule Hedera.Pb.Timestamp do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.Timestamp",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :seconds, 1, type: :int64
  field :nanos, 2, type: :int32
end

defmodule Hedera.Pb.Duration do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.Duration",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :seconds, 1, type: :int64
end

defmodule Hedera.Pb.AccountID do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.AccountID",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :shardNum, 1, type: :int64
  field :realmNum, 2, type: :int64
  field :accountNum, 3, type: :int64
end

defmodule Hedera.Pb.TopicID do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TopicID",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :shardNum, 1, type: :int64
  field :realmNum, 2, type: :int64
  field :topicNum, 3, type: :int64
end

defmodule Hedera.Pb.TokenID do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenID",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :shardNum, 1, type: :int64
  field :realmNum, 2, type: :int64
  field :tokenNum, 3, type: :int64
end

defmodule Hedera.Pb.TransactionID do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TransactionID",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :transactionValidStart, 1, type: Hedera.Pb.Timestamp
  field :accountID, 2, type: Hedera.Pb.AccountID
end

defmodule Hedera.Pb.AccountAmount do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.AccountAmount",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :accountID, 1, type: Hedera.Pb.AccountID
  field :amount, 2, type: :sint64
  field :is_approval, 3, type: :bool, json_name: "isApproval"
end

defmodule Hedera.Pb.TransferList do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TransferList",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :accountAmounts, 1, repeated: true, type: Hedera.Pb.AccountAmount
end

defmodule Hedera.Pb.TokenTransferList do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenTransferList",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :token, 1, type: Hedera.Pb.TokenID
  field :transfers, 2, repeated: true, type: Hedera.Pb.AccountAmount
end

defmodule Hedera.Pb.CryptoTransferTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.CryptoTransferTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :transfers, 1, type: Hedera.Pb.TransferList
  field :tokenTransfers, 2, repeated: true, type: Hedera.Pb.TokenTransferList
end

defmodule Hedera.Pb.ConsensusSubmitMessageTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.ConsensusSubmitMessageTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :topicID, 1, type: Hedera.Pb.TopicID
  field :message, 2, type: :bytes
end

defmodule Hedera.Pb.TransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :data, 0

  field :transactionID, 1, type: Hedera.Pb.TransactionID
  field :nodeAccountID, 2, type: Hedera.Pb.AccountID
  field :transactionFee, 3, type: :uint64
  field :transactionValidDuration, 4, type: Hedera.Pb.Duration
  field :memo, 6, type: :string
  field :cryptoTransfer, 14, type: Hedera.Pb.CryptoTransferTransactionBody, oneof: 0

  field :consensusSubmitMessage, 27,
    type: Hedera.Pb.ConsensusSubmitMessageTransactionBody,
    oneof: 0
end

defmodule Hedera.Pb.Key do
  @moduledoc false

  use Protobuf, full_name: "hedera.pb.Key", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof :key, 0

  field :ed25519, 2, type: :bytes, oneof: 0
  field :ECDSASecp256k1, 7, type: :bytes, oneof: 0
end

defmodule Hedera.Pb.SignaturePair do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.SignaturePair",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :signature, 0

  field :pubKeyPrefix, 1, type: :bytes
  field :ed25519, 3, type: :bytes, oneof: 0
  field :ECDSASecp256k1, 6, type: :bytes, oneof: 0
end

defmodule Hedera.Pb.SignatureMap do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.SignatureMap",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :sigPair, 1, repeated: true, type: Hedera.Pb.SignaturePair
end

defmodule Hedera.Pb.SignedTransaction do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.SignedTransaction",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :bodyBytes, 1, type: :bytes
  field :sigMap, 2, type: Hedera.Pb.SignatureMap
end

defmodule Hedera.Pb.Transaction do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.Transaction",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :signedTransactionBytes, 5, type: :bytes
end

defmodule Hedera.Pb.TransactionReceipt do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TransactionReceipt",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :status, 1, type: :int32
  field :topicID, 6, type: Hedera.Pb.TopicID
  field :topicSequenceNumber, 7, type: :uint64
  field :topicRunningHash, 8, type: :bytes
  field :tokenID, 10, type: Hedera.Pb.TokenID
  field :newTotalSupply, 11, type: :uint64
  field :serialNumbers, 14, repeated: true, type: :int64
end
