defmodule Hedera.Pb.TokenType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "hedera.pb.TokenType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :FUNGIBLE_COMMON, 0
  field :NON_FUNGIBLE_UNIQUE, 1
end

defmodule Hedera.Pb.TokenSupplyType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "hedera.pb.TokenSupplyType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :INFINITE, 0
  field :FINITE, 1
end

defmodule Hedera.Pb.ResponseType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "hedera.pb.ResponseType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :ANSWER_ONLY, 0
  field :ANSWER_STATE_PROOF, 1
  field :COST_ANSWER, 2
  field :COST_ANSWER_STATE_PROOF, 3
end

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

defmodule Hedera.Pb.FileID do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.FileID",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :shardNum, 1, type: :int64
  field :realmNum, 2, type: :int64
  field :fileNum, 3, type: :int64
end

defmodule Hedera.Pb.ScheduleID do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.ScheduleID",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :shardNum, 1, type: :int64
  field :realmNum, 2, type: :int64
  field :scheduleNum, 3, type: :int64
end

defmodule Hedera.Pb.ContractID do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.ContractID",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :contract, 0

  field :shardNum, 1, type: :int64
  field :realmNum, 2, type: :int64
  field :contractNum, 3, type: :int64, oneof: 0
  field :evm_address, 4, type: :bytes, json_name: "evmAddress", oneof: 0
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

defmodule Hedera.Pb.Key do
  @moduledoc false

  use Protobuf, full_name: "hedera.pb.Key", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof :key, 0

  field :ed25519, 2, type: :bytes, oneof: 0
  field :ECDSASecp256k1, 7, type: :bytes, oneof: 0
end

defmodule Hedera.Pb.KeyList do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.KeyList",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :keys, 1, repeated: true, type: Hedera.Pb.Key
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

defmodule Hedera.Pb.NftTransfer do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.NftTransfer",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :senderAccountID, 1, type: Hedera.Pb.AccountID
  field :receiverAccountID, 2, type: Hedera.Pb.AccountID
  field :serialNumber, 3, type: :int64
end

defmodule Hedera.Pb.TokenTransferList do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenTransferList",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :token, 1, type: Hedera.Pb.TokenID
  field :transfers, 2, repeated: true, type: Hedera.Pb.AccountAmount
  field :nftTransfers, 3, repeated: true, type: Hedera.Pb.NftTransfer
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

defmodule Hedera.Pb.ConsensusCreateTopicTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.ConsensusCreateTopicTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :memo, 1, type: :string
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

defmodule Hedera.Pb.TokenCreateTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenCreateTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :symbol, 2, type: :string
  field :decimals, 3, type: :uint32
  field :initialSupply, 4, type: :uint64
  field :treasury, 5, type: Hedera.Pb.AccountID
  field :adminKey, 6, type: Hedera.Pb.Key
  field :kycKey, 7, type: Hedera.Pb.Key
  field :freezeKey, 8, type: Hedera.Pb.Key
  field :wipeKey, 9, type: Hedera.Pb.Key
  field :supplyKey, 10, type: Hedera.Pb.Key
  field :freezeDefault, 11, type: :bool
  field :autoRenewAccount, 14, type: Hedera.Pb.AccountID
  field :autoRenewPeriod, 15, type: Hedera.Pb.Duration
  field :memo, 16, type: :string
  field :tokenType, 17, type: Hedera.Pb.TokenType, enum: true
  field :supplyType, 18, type: Hedera.Pb.TokenSupplyType, enum: true
  field :maxSupply, 19, type: :int64
  field :pauseKey, 22, type: Hedera.Pb.Key
end

defmodule Hedera.Pb.TokenMintTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenMintTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :token, 1, type: Hedera.Pb.TokenID
  field :amount, 2, type: :uint64
  field :metadata, 3, repeated: true, type: :bytes
end

defmodule Hedera.Pb.TokenBurnTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenBurnTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :token, 1, type: Hedera.Pb.TokenID
  field :amount, 2, type: :uint64
  field :serialNumbers, 3, repeated: true, type: :int64
end

defmodule Hedera.Pb.TokenAssociateTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenAssociateTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :account, 1, type: Hedera.Pb.AccountID
  field :tokens, 2, repeated: true, type: Hedera.Pb.TokenID
end

defmodule Hedera.Pb.TokenFreezeAccountTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenFreezeAccountTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :token, 1, type: Hedera.Pb.TokenID
  field :account, 2, type: Hedera.Pb.AccountID
end

defmodule Hedera.Pb.TokenUnfreezeAccountTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenUnfreezeAccountTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :token, 1, type: Hedera.Pb.TokenID
  field :account, 2, type: Hedera.Pb.AccountID
end

defmodule Hedera.Pb.TokenGrantKycTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenGrantKycTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :token, 1, type: Hedera.Pb.TokenID
  field :account, 2, type: Hedera.Pb.AccountID
end

defmodule Hedera.Pb.TokenRevokeKycTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenRevokeKycTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :token, 1, type: Hedera.Pb.TokenID
  field :account, 2, type: Hedera.Pb.AccountID
end

defmodule Hedera.Pb.TokenWipeAccountTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenWipeAccountTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :token, 1, type: Hedera.Pb.TokenID
  field :account, 2, type: Hedera.Pb.AccountID
  field :amount, 3, type: :uint64
  field :serialNumbers, 4, repeated: true, type: :int64
end

defmodule Hedera.Pb.TokenPauseTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenPauseTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :token, 1, type: Hedera.Pb.TokenID
end

defmodule Hedera.Pb.TokenUnpauseTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TokenUnpauseTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :token, 1, type: Hedera.Pb.TokenID
end

defmodule Hedera.Pb.FileCreateTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.FileCreateTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :expirationTime, 2, type: Hedera.Pb.Timestamp
  field :keys, 3, type: Hedera.Pb.KeyList
  field :contents, 4, type: :bytes
  field :memo, 8, type: :string
end

defmodule Hedera.Pb.FileAppendTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.FileAppendTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :fileID, 2, type: Hedera.Pb.FileID
  field :contents, 4, type: :bytes
end

defmodule Hedera.Pb.FileUpdateTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.FileUpdateTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :fileID, 1, type: Hedera.Pb.FileID
  field :expirationTime, 2, type: Hedera.Pb.Timestamp
  field :keys, 3, type: Hedera.Pb.KeyList
  field :contents, 4, type: :bytes
end

defmodule Hedera.Pb.FileDeleteTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.FileDeleteTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :fileID, 2, type: Hedera.Pb.FileID
end

defmodule Hedera.Pb.SchedulableTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.SchedulableTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :data, 0

  field :transactionFee, 1, type: :uint64
  field :memo, 2, type: :string
  field :cryptoTransfer, 9, type: Hedera.Pb.CryptoTransferTransactionBody, oneof: 0
end

defmodule Hedera.Pb.ScheduleCreateTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.ScheduleCreateTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :scheduledTransactionBody, 1, type: Hedera.Pb.SchedulableTransactionBody
  field :memo, 2, type: :string
  field :adminKey, 3, type: Hedera.Pb.Key
  field :payerAccountID, 4, type: Hedera.Pb.AccountID
end

defmodule Hedera.Pb.ScheduleSignTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.ScheduleSignTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :scheduleID, 1, type: Hedera.Pb.ScheduleID
end

defmodule Hedera.Pb.ContractCreateTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.ContractCreateTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :initcodeSource, 0

  field :fileID, 1, type: Hedera.Pb.FileID, oneof: 0
  field :initcode, 16, type: :bytes, oneof: 0
  field :adminKey, 3, type: Hedera.Pb.Key
  field :gas, 4, type: :int64
  field :initialBalance, 5, type: :int64
  field :autoRenewPeriod, 8, type: Hedera.Pb.Duration
  field :constructorParameters, 9, type: :bytes
  field :memo, 13, type: :string
end

defmodule Hedera.Pb.ContractCallTransactionBody do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.ContractCallTransactionBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :contractID, 1, type: Hedera.Pb.ContractID
  field :gas, 2, type: :int64
  field :amount, 3, type: :int64
  field :functionParameters, 4, type: :bytes
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
  field :contractCall, 7, type: Hedera.Pb.ContractCallTransactionBody, oneof: 0
  field :contractCreateInstance, 8, type: Hedera.Pb.ContractCreateTransactionBody, oneof: 0
  field :fileAppend, 16, type: Hedera.Pb.FileAppendTransactionBody, oneof: 0
  field :fileCreate, 17, type: Hedera.Pb.FileCreateTransactionBody, oneof: 0
  field :fileDelete, 18, type: Hedera.Pb.FileDeleteTransactionBody, oneof: 0
  field :fileUpdate, 19, type: Hedera.Pb.FileUpdateTransactionBody, oneof: 0
  field :cryptoTransfer, 14, type: Hedera.Pb.CryptoTransferTransactionBody, oneof: 0
  field :consensusCreateTopic, 24, type: Hedera.Pb.ConsensusCreateTopicTransactionBody, oneof: 0

  field :consensusSubmitMessage, 27,
    type: Hedera.Pb.ConsensusSubmitMessageTransactionBody,
    oneof: 0

  field :tokenCreation, 29, type: Hedera.Pb.TokenCreateTransactionBody, oneof: 0
  field :tokenFreeze, 31, type: Hedera.Pb.TokenFreezeAccountTransactionBody, oneof: 0
  field :tokenUnfreeze, 32, type: Hedera.Pb.TokenUnfreezeAccountTransactionBody, oneof: 0
  field :tokenGrantKyc, 33, type: Hedera.Pb.TokenGrantKycTransactionBody, oneof: 0
  field :tokenRevokeKyc, 34, type: Hedera.Pb.TokenRevokeKycTransactionBody, oneof: 0
  field :tokenMint, 37, type: Hedera.Pb.TokenMintTransactionBody, oneof: 0
  field :tokenBurn, 38, type: Hedera.Pb.TokenBurnTransactionBody, oneof: 0
  field :tokenWipe, 39, type: Hedera.Pb.TokenWipeAccountTransactionBody, oneof: 0
  field :tokenAssociate, 40, type: Hedera.Pb.TokenAssociateTransactionBody, oneof: 0
  field :scheduleCreate, 42, type: Hedera.Pb.ScheduleCreateTransactionBody, oneof: 0
  field :scheduleSign, 44, type: Hedera.Pb.ScheduleSignTransactionBody, oneof: 0

  field :token_pause, 46,
    type: Hedera.Pb.TokenPauseTransactionBody,
    json_name: "tokenPause",
    oneof: 0

  field :token_unpause, 47,
    type: Hedera.Pb.TokenUnpauseTransactionBody,
    json_name: "tokenUnpause",
    oneof: 0
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
  field :contractID, 4, type: Hedera.Pb.ContractID
  field :fileID, 3, type: Hedera.Pb.FileID
  field :topicID, 6, type: Hedera.Pb.TopicID
  field :topicSequenceNumber, 7, type: :uint64
  field :topicRunningHash, 8, type: :bytes
  field :tokenID, 10, type: Hedera.Pb.TokenID
  field :newTotalSupply, 11, type: :uint64
  field :scheduleID, 12, type: Hedera.Pb.ScheduleID
  field :serialNumbers, 14, repeated: true, type: :int64
end

defmodule Hedera.Pb.TransactionResponse do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TransactionResponse",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :nodeTransactionPrecheckCode, 1, type: :int32
  field :cost, 2, type: :uint64
end

defmodule Hedera.Pb.QueryHeader do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.QueryHeader",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :payment, 1, type: Hedera.Pb.Transaction
  field :responseType, 2, type: Hedera.Pb.ResponseType, enum: true
end

defmodule Hedera.Pb.ResponseHeader do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.ResponseHeader",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :nodeTransactionPrecheckCode, 1, type: :int32
  field :responseType, 2, type: Hedera.Pb.ResponseType, enum: true
  field :cost, 3, type: :uint64
end

defmodule Hedera.Pb.TransactionGetReceiptQuery do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TransactionGetReceiptQuery",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :header, 1, type: Hedera.Pb.QueryHeader
  field :transactionID, 2, type: Hedera.Pb.TransactionID
end

defmodule Hedera.Pb.TransactionGetReceiptResponse do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.TransactionGetReceiptResponse",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :header, 1, type: Hedera.Pb.ResponseHeader
  field :receipt, 2, type: Hedera.Pb.TransactionReceipt
end

defmodule Hedera.Pb.Query do
  @moduledoc false

  use Protobuf, full_name: "hedera.pb.Query", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof :query, 0

  field :transactionGetReceipt, 14, type: Hedera.Pb.TransactionGetReceiptQuery, oneof: 0
end

defmodule Hedera.Pb.Response do
  @moduledoc false

  use Protobuf,
    full_name: "hedera.pb.Response",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  oneof :response, 0

  field :transactionGetReceipt, 14, type: Hedera.Pb.TransactionGetReceiptResponse, oneof: 0
end
