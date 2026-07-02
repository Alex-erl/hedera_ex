defmodule Hedera.Transaction do
  @moduledoc """
  Builds and signs Hedera transactions for the Consensus, Crypto, Token, File
  and Schedule services.

  The flow follows the Hedera HAPI: build a `TransactionBody`, encode it, sign
  the exact `bodyBytes` with the operator key (and any additional `:signers`),
  wrap them in a `SignedTransaction` (bodyBytes + signature map) and finally a
  `Transaction` (signedTransactionBytes). The signature is computed over the
  precise `bodyBytes` that are transmitted.

  The wire encoding is handled by the **protoc-generated `Hedera.Pb.*` modules**
  (see `priv/protos/hedera_min.proto`); this module maps the SDK's structs onto
  those messages. Field numbers therefore live in the `.proto`, validated
  end-to-end against a live node by the gRPC layer.
  """

  alias Hedera.{
    AccountId,
    ContractId,
    FileId,
    Pb,
    PrivateKey,
    PublicKey,
    ScheduleId,
    Timestamp,
    TokenId,
    TopicId,
    TransactionId
  }

  # default max fee: 2 ℏ in tinybars (token/contract create need a higher ceiling)
  @default_max_fee 200_000_000
  @default_token_create_fee 4_000_000_000
  @default_contract_fee 20_000_000_000
  @default_valid_seconds 120
  # token/file auto-renew/expiry default: ~90 days
  @default_auto_renew_seconds 7_776_000

  @type build_result :: %{transaction: binary(), transaction_id: TransactionId.t()}

  # --- Consensus Service ------------------------------------------------------

  @doc """
  Build + sign a `consensusSubmitMessage` transaction. Required opts:
  `:operator_id`, `:operator_key`, `:node_account_id`, `:topic_id`, `:message`.
  Optional: `:max_fee`, `:memo`.
  """
  @spec submit_message(keyword()) :: build_result()
  def submit_message(opts) do
    body = %Pb.ConsensusSubmitMessageTransactionBody{
      topicID: pb_topic(fetch!(opts, :topic_id)),
      message: fetch!(opts, :message)
    }

    build(opts, {:consensusSubmitMessage, body})
  end

  @doc "Build + sign a `consensusCreateTopic` transaction. Optional: `:memo`, `:max_fee`."
  @spec create_topic(keyword()) :: build_result()
  def create_topic(opts) do
    build(opts, {:consensusCreateTopic, %Pb.ConsensusCreateTopicTransactionBody{memo: opts[:memo] || ""}})
  end

  # --- Crypto Service ---------------------------------------------------------

  @doc """
  Build + sign a `cryptoTransfer` of HBAR and/or HTS tokens. Opts: `:transfers`
  (`{%AccountId{}, tinybars}` list), `:token_transfers`
  (`{%TokenId{}, [{%AccountId{}, amount}]}` list), `:nft_transfers`
  (`{%TokenId{}, [{sender, receiver, serial}]}` list). Amounts are `sint64`
  (ZigZag); each currency must net to zero. Optional: `:memo`, `:max_fee`.
  """
  @spec crypto_transfer(keyword()) :: build_result()
  def crypto_transfer(opts) do
    build(opts, {:cryptoTransfer, crypto_transfer_body(opts)})
  end

  # --- Token Service ----------------------------------------------------------

  @doc """
  Build + sign a `tokenCreation`. Required: `:treasury`. Common opts: `:name`,
  `:symbol`, `:decimals`, `:initial_supply`, `:token_type` (`:fungible` | `:nft`),
  `:supply_type` (`:infinite` | `:finite`), `:max_supply`, `:token_memo`,
  `:auto_renew_account`, `:auto_renew_period`, and key opts `:admin_key`,
  `:supply_key`, `:kyc_key`, `:freeze_key`, `:wipe_key`, `:pause_key`.
  """
  @spec token_create(keyword()) :: build_result()
  def token_create(opts) do
    treasury = fetch!(opts, :treasury)
    auto_renew = Keyword.get(opts, :auto_renew_account, treasury)
    renew_period = Keyword.get(opts, :auto_renew_period, @default_auto_renew_seconds)

    body = %Pb.TokenCreateTransactionBody{
      name: Keyword.get(opts, :name, ""),
      symbol: Keyword.get(opts, :symbol, ""),
      decimals: Keyword.get(opts, :decimals, 0),
      initialSupply: Keyword.get(opts, :initial_supply, 0),
      treasury: pb_account(treasury),
      adminKey: pb_key(opts[:admin_key]),
      kycKey: pb_key(opts[:kyc_key]),
      freezeKey: pb_key(opts[:freeze_key]),
      wipeKey: pb_key(opts[:wipe_key]),
      supplyKey: pb_key(opts[:supply_key]),
      pauseKey: pb_key(opts[:pause_key]),
      freezeDefault: Keyword.get(opts, :freeze_default, false),
      autoRenewAccount: pb_account(auto_renew),
      autoRenewPeriod: %Pb.Duration{seconds: renew_period},
      memo: opts[:token_memo] || "",
      tokenType: token_type(Keyword.get(opts, :token_type, :fungible)),
      supplyType: supply_type(Keyword.get(opts, :supply_type, :infinite)),
      maxSupply: Keyword.get(opts, :max_supply, 0)
    }

    fee = Keyword.get(opts, :max_fee, @default_token_create_fee)
    build(Keyword.put(opts, :max_fee, fee), {:tokenCreation, body})
  end

  @doc "Build + sign a `tokenMint`. Required: `:token`. Opts: `:amount` (fungible) or `:metadata` (NFT)."
  @spec token_mint(keyword()) :: build_result()
  def token_mint(opts) do
    body = %Pb.TokenMintTransactionBody{
      token: pb_token(fetch!(opts, :token)),
      amount: Keyword.get(opts, :amount, 0),
      metadata: Keyword.get(opts, :metadata, [])
    }

    build(opts, {:tokenMint, body})
  end

  @doc "Build + sign a `tokenBurn`. Required: `:token`, `:amount`."
  @spec token_burn(keyword()) :: build_result()
  def token_burn(opts) do
    body = %Pb.TokenBurnTransactionBody{
      token: pb_token(fetch!(opts, :token)),
      amount: Keyword.get(opts, :amount, 0)
    }

    build(opts, {:tokenBurn, body})
  end

  @doc "Build + sign a `tokenAssociate`. Required: `:account`, `:tokens` (list of `TokenId`)."
  @spec token_associate(keyword()) :: build_result()
  def token_associate(opts) do
    body = %Pb.TokenAssociateTransactionBody{
      account: pb_account(fetch!(opts, :account)),
      tokens: Enum.map(fetch!(opts, :tokens), &pb_token/1)
    }

    build(opts, {:tokenAssociate, body})
  end

  @doc "Build + sign a `tokenFreezeAccount`. Required: `:token`, `:account`. Needs the freeze key."
  @spec token_freeze(keyword()) :: build_result()
  def token_freeze(opts),
    do: build(opts, {:tokenFreeze, %Pb.TokenFreezeAccountTransactionBody{token: pb_token(fetch!(opts, :token)), account: pb_account(fetch!(opts, :account))}})

  @doc "Build + sign a `tokenUnfreezeAccount`. Required: `:token`, `:account`. Needs the freeze key."
  @spec token_unfreeze(keyword()) :: build_result()
  def token_unfreeze(opts),
    do: build(opts, {:tokenUnfreeze, %Pb.TokenUnfreezeAccountTransactionBody{token: pb_token(fetch!(opts, :token)), account: pb_account(fetch!(opts, :account))}})

  @doc "Build + sign a `tokenGrantKyc`. Required: `:token`, `:account`. Needs the KYC key."
  @spec token_grant_kyc(keyword()) :: build_result()
  def token_grant_kyc(opts),
    do: build(opts, {:tokenGrantKyc, %Pb.TokenGrantKycTransactionBody{token: pb_token(fetch!(opts, :token)), account: pb_account(fetch!(opts, :account))}})

  @doc "Build + sign a `tokenRevokeKyc`. Required: `:token`, `:account`. Needs the KYC key."
  @spec token_revoke_kyc(keyword()) :: build_result()
  def token_revoke_kyc(opts),
    do: build(opts, {:tokenRevokeKyc, %Pb.TokenRevokeKycTransactionBody{token: pb_token(fetch!(opts, :token)), account: pb_account(fetch!(opts, :account))}})

  @doc """
  Build + sign a `tokenWipeAccount`. Required: `:token`, `:account`. For fungible
  tokens pass `:amount`; for NFTs pass `:serials`. Needs the wipe key.
  """
  @spec token_wipe(keyword()) :: build_result()
  def token_wipe(opts) do
    body = %Pb.TokenWipeAccountTransactionBody{
      token: pb_token(fetch!(opts, :token)),
      account: pb_account(fetch!(opts, :account)),
      amount: Keyword.get(opts, :amount, 0),
      serialNumbers: Keyword.get(opts, :serials, [])
    }

    build(opts, {:tokenWipe, body})
  end

  @doc "Build + sign a `tokenPause`. Required: `:token`. Needs the pause key."
  @spec token_pause(keyword()) :: build_result()
  def token_pause(opts),
    do: build(opts, {:token_pause, %Pb.TokenPauseTransactionBody{token: pb_token(fetch!(opts, :token))}})

  @doc "Build + sign a `tokenUnpause`. Required: `:token`. Needs the pause key."
  @spec token_unpause(keyword()) :: build_result()
  def token_unpause(opts),
    do: build(opts, {:token_unpause, %Pb.TokenUnpauseTransactionBody{token: pb_token(fetch!(opts, :token))}})

  # --- File Service -----------------------------------------------------------

  @doc """
  Build + sign a `fileCreate`. Opts: `:contents`, `:keys` (a list of `PublicKey`s;
  defaults to the operator's key), `:expiration_seconds`, `:file_memo`.
  """
  @spec file_create(keyword()) :: build_result()
  def file_create(opts) do
    keys = opts[:keys] || [PrivateKey.public_key(fetch!(opts, :operator_key))]
    expiry = opts[:expiration_seconds] || unix_now() + @default_auto_renew_seconds

    body = %Pb.FileCreateTransactionBody{
      expirationTime: %Pb.Timestamp{seconds: expiry},
      keys: %Pb.KeyList{keys: Enum.map(keys, &pb_key/1)},
      contents: Keyword.get(opts, :contents, ""),
      memo: opts[:file_memo] || ""
    }

    build(opts, {:fileCreate, body})
  end

  @doc "Build + sign a `fileAppend`. Required: `:file`, `:contents`. Needs the file's key(s)."
  @spec file_append(keyword()) :: build_result()
  def file_append(opts) do
    body = %Pb.FileAppendTransactionBody{fileID: pb_file(fetch!(opts, :file)), contents: fetch!(opts, :contents)}
    build(opts, {:fileAppend, body})
  end

  @doc "Build + sign a `fileUpdate`. Required: `:file`. Optional: `:contents`, `:keys`, `:expiration_seconds`."
  @spec file_update(keyword()) :: build_result()
  def file_update(opts) do
    body = %Pb.FileUpdateTransactionBody{
      fileID: pb_file(fetch!(opts, :file)),
      expirationTime: opts[:expiration_seconds] && %Pb.Timestamp{seconds: opts[:expiration_seconds]},
      keys: opts[:keys] && %Pb.KeyList{keys: Enum.map(opts[:keys], &pb_key/1)},
      contents: opts[:contents] || ""
    }

    build(opts, {:fileUpdate, body})
  end

  @doc "Build + sign a `fileDelete`. Required: `:file`. Needs the file's key(s)."
  @spec file_delete(keyword()) :: build_result()
  def file_delete(opts),
    do: build(opts, {:fileDelete, %Pb.FileDeleteTransactionBody{fileID: pb_file(fetch!(opts, :file))}})

  # --- Schedule Service -------------------------------------------------------

  @doc """
  Build + sign a `scheduleCreate` wrapping an HBAR/token transfer (`:transfers`,
  `:token_transfers`, `:nft_transfers` describe the scheduled transaction).
  Optional: `:admin_key`, `:schedule_memo`.
  """
  @spec schedule_create(keyword()) :: build_result()
  def schedule_create(opts) do
    schedulable = %Pb.SchedulableTransactionBody{data: {:cryptoTransfer, crypto_transfer_body(opts)}}

    body = %Pb.ScheduleCreateTransactionBody{
      scheduledTransactionBody: schedulable,
      memo: opts[:schedule_memo] || "",
      adminKey: pb_key(opts[:admin_key])
    }

    build(opts, {:scheduleCreate, body})
  end

  @doc "Build + sign a `scheduleSign`. Required: `:schedule_id`."
  @spec schedule_sign(keyword()) :: build_result()
  def schedule_sign(opts),
    do: build(opts, {:scheduleSign, %Pb.ScheduleSignTransactionBody{scheduleID: pb_schedule(fetch!(opts, :schedule_id))}})

  # --- Smart Contract Service -------------------------------------------------

  @doc """
  Build + sign a `contractCreateInstance`. Provide the bytecode either inline via
  `:bytecode` (EVM init bytecode) or by `:file` (a `FileId` holding it). Opts:
  `:gas` (default 100 000), `:admin_key`, `:initial_balance`,
  `:constructor_parameters`, `:auto_renew_period`, `:contract_memo`. The new
  contract id is returned in the receipt.
  """
  @spec contract_create(keyword()) :: build_result()
  def contract_create(opts) do
    renew_period = Keyword.get(opts, :auto_renew_period, @default_auto_renew_seconds)

    body = %Pb.ContractCreateTransactionBody{
      initcodeSource: initcode_source(opts),
      adminKey: pb_key(opts[:admin_key]),
      gas: Keyword.get(opts, :gas, 100_000),
      initialBalance: Keyword.get(opts, :initial_balance, 0),
      autoRenewPeriod: %Pb.Duration{seconds: renew_period},
      constructorParameters: opts[:constructor_parameters] || "",
      memo: opts[:contract_memo] || ""
    }

    fee = Keyword.get(opts, :max_fee, @default_contract_fee)
    build(Keyword.put(opts, :max_fee, fee), {:contractCreateInstance, body})
  end

  @doc """
  Build + sign a `contractCall`. Required: `:contract` (a `ContractId`). Opts:
  `:gas` (default 50 000), `:amount` (tinybars to send), `:function_parameters`
  (ABI-encoded call data). The return value is in the record, not the receipt.
  """
  @spec contract_call(keyword()) :: build_result()
  def contract_call(opts) do
    body = %Pb.ContractCallTransactionBody{
      contractID: pb_contract(fetch!(opts, :contract)),
      gas: Keyword.get(opts, :gas, 50_000),
      amount: Keyword.get(opts, :amount, 0),
      functionParameters: opts[:function_parameters] || ""
    }

    fee = Keyword.get(opts, :max_fee, @default_contract_fee)
    build(Keyword.put(opts, :max_fee, fee), {:contractCall, body})
  end

  defp initcode_source(opts) do
    cond do
      opts[:bytecode] -> {:initcode, opts[:bytecode]}
      opts[:file] -> {:fileID, pb_file(opts[:file])}
      true -> raise ArgumentError, "contract_create needs :bytecode or :file"
    end
  end

  # --- Allowances (delegated spend) -------------------------------------------

  @doc """
  Build + sign a `cryptoApproveAllowance` — authorize a spender to move the
  owner's assets without the owner's key. Opts:

    * `:hbar_allowances` — `{owner, spender, amount}` (tinybars).
    * `:token_allowances` — `{token, owner, spender, amount}` (fungible units).
    * `:nft_allowances` — `{token, owner, spender, serials}` (a list of serials)
      or `{token, owner, spender, :all}` (approve for every serial of the token).

  Each owner must sign; pass their keys via `:signers` when they aren't the operator.
  """
  @spec approve_allowance(keyword()) :: build_result()
  def approve_allowance(opts) do
    body = %Pb.CryptoApproveAllowanceTransactionBody{
      cryptoAllowances:
        Enum.map(Keyword.get(opts, :hbar_allowances, []), fn {owner, spender, amount} ->
          %Pb.CryptoAllowance{owner: pb_account(owner), spender: pb_account(spender), amount: amount}
        end),
      tokenAllowances:
        Enum.map(Keyword.get(opts, :token_allowances, []), fn {token, owner, spender, amount} ->
          %Pb.TokenAllowance{
            tokenId: pb_token(token),
            owner: pb_account(owner),
            spender: pb_account(spender),
            amount: amount
          }
        end),
      nftAllowances: Enum.map(Keyword.get(opts, :nft_allowances, []), &nft_allowance/1)
    }

    build(opts, {:cryptoApproveAllowance, body})
  end

  @doc """
  Build + sign a `cryptoDeleteAllowance` — remove NFT-serial allowances. Opt
  `:nft_allowances` is a list of `{token, owner, serials}`. (HBAR/fungible
  allowances are removed by approving amount `0`.)
  """
  @spec delete_nft_allowance(keyword()) :: build_result()
  def delete_nft_allowance(opts) do
    body = %Pb.CryptoDeleteAllowanceTransactionBody{
      nftAllowances:
        Enum.map(Keyword.get(opts, :nft_allowances, []), fn {token, owner, serials} ->
          %Pb.NftRemoveAllowance{
            token_id: pb_token(token),
            owner: pb_account(owner),
            serial_numbers: serials
          }
        end)
    }

    build(opts, {:cryptoDeleteAllowance, body})
  end

  defp nft_allowance({token, owner, spender, :all}) do
    %Pb.NftAllowance{
      tokenId: pb_token(token),
      owner: pb_account(owner),
      spender: pb_account(spender),
      approved_for_all: %Pb.BoolValue{value: true}
    }
  end

  defp nft_allowance({token, owner, spender, serials}) when is_list(serials) do
    %Pb.NftAllowance{
      tokenId: pb_token(token),
      owner: pb_account(owner),
      spender: pb_account(spender),
      serial_numbers: serials
    }
  end

  # --- build / sign -----------------------------------------------------------

  defp build(opts, data) do
    operator_id = fetch!(opts, :operator_id)
    operator_key = fetch!(opts, :operator_key)
    node = fetch!(opts, :node_account_id)
    tx_id = Keyword.get(opts, :transaction_id) || TransactionId.generate(operator_id)
    fee = Keyword.get(opts, :max_fee, @default_max_fee)
    # the operator (fee payer) always signs; :signers adds any extra required keys
    signers = [operator_key | Keyword.get(opts, :signers, [])]

    body = %Pb.TransactionBody{
      transactionID: pb_txid(tx_id),
      nodeAccountID: pb_account(node),
      transactionFee: fee,
      transactionValidDuration: %Pb.Duration{seconds: @default_valid_seconds},
      memo: opts[:memo] || "",
      data: data
    }

    body_bytes = encode(Pb.TransactionBody, body)
    %{transaction: sign_and_wrap(body_bytes, signers), transaction_id: tx_id}
  end

  defp sign_and_wrap(body_bytes, signers) do
    sig_pairs =
      signers
      |> Enum.uniq_by(fn key -> PublicKey.to_bytes(PrivateKey.public_key(key)) end)
      |> Enum.map(fn %PrivateKey{} = key ->
        pub = PrivateKey.public_key(key)
        sig = PrivateKey.sign(key, body_bytes)
        %Pb.SignaturePair{pubKeyPrefix: PublicKey.to_bytes(pub), signature: signature_oneof(pub, sig)}
      end)

    signed = %Pb.SignedTransaction{bodyBytes: body_bytes, sigMap: %Pb.SignatureMap{sigPair: sig_pairs}}
    encode(Pb.Transaction, %Pb.Transaction{signedTransactionBytes: encode(Pb.SignedTransaction, signed)})
  end

  # SignaturePair.signature oneof
  defp signature_oneof(%PublicKey{type: :ed25519}, sig), do: {:ed25519, sig}
  defp signature_oneof(%PublicKey{type: :ecdsa_secp256k1}, sig), do: {:ECDSASecp256k1, sig}

  # --- CryptoTransferTransactionBody (reused by scheduling) -------------------

  defp crypto_transfer_body(opts) do
    hbar = Keyword.get(opts, :transfers, [])
    token_transfers = Keyword.get(opts, :token_transfers, [])
    nft_transfers = Keyword.get(opts, :nft_transfers, [])

    fungible =
      Enum.map(token_transfers, fn {%TokenId{} = token, moves} ->
        %Pb.TokenTransferList{token: pb_token(token), transfers: account_amounts(moves)}
      end)

    nfts =
      Enum.map(nft_transfers, fn {%TokenId{} = token, moves} ->
        %Pb.TokenTransferList{token: pb_token(token), nftTransfers: nft_transfer_list(moves)}
      end)

    %Pb.CryptoTransferTransactionBody{
      transfers: hbar != [] && %Pb.TransferList{accountAmounts: account_amounts(hbar)} || nil,
      tokenTransfers: fungible ++ nfts
    }
  end

  # `{account, amount}` or `{account, amount, is_approval}` — the latter marks an
  # approved (allowance-based) debit, where the spender (not the owner) signs.
  defp account_amounts(moves) do
    Enum.map(moves, fn
      {%AccountId{} = account, amount} ->
        %Pb.AccountAmount{accountID: pb_account(account), amount: amount}

      {%AccountId{} = account, amount, approval} ->
        %Pb.AccountAmount{accountID: pb_account(account), amount: amount, is_approval: !!approval}
    end)
  end

  # `{sender, receiver, serial}` or `{sender, receiver, serial, is_approval}`.
  defp nft_transfer_list(moves) do
    Enum.map(moves, fn
      {%AccountId{} = sender, %AccountId{} = receiver, serial} ->
        nft_transfer(sender, receiver, serial, false)

      {%AccountId{} = sender, %AccountId{} = receiver, serial, approval} ->
        nft_transfer(sender, receiver, serial, !!approval)
    end)
  end

  defp nft_transfer(sender, receiver, serial, approval) do
    %Pb.NftTransfer{
      senderAccountID: pb_account(sender),
      receiverAccountID: pb_account(receiver),
      serialNumber: serial,
      is_approval: approval
    }
  end

  # --- struct → Pb converters -------------------------------------------------

  defp pb_account(%AccountId{shard: s, realm: r, num: n}),
    do: %Pb.AccountID{shardNum: s, realmNum: r, accountNum: n}

  defp pb_topic(%TopicId{shard: s, realm: r, num: n}),
    do: %Pb.TopicID{shardNum: s, realmNum: r, topicNum: n}

  defp pb_token(%TokenId{shard: s, realm: r, num: n}),
    do: %Pb.TokenID{shardNum: s, realmNum: r, tokenNum: n}

  defp pb_file(%FileId{shard: s, realm: r, num: n}),
    do: %Pb.FileID{shardNum: s, realmNum: r, fileNum: n}

  defp pb_schedule(%ScheduleId{shard: s, realm: r, num: n}),
    do: %Pb.ScheduleID{shardNum: s, realmNum: r, scheduleNum: n}

  defp pb_contract(%ContractId{shard: s, realm: r, num: n}),
    do: %Pb.ContractID{shardNum: s, realmNum: r, contract: {:contractNum, n}}

  defp pb_txid(%TransactionId{account_id: account, valid_start: %Timestamp{seconds: s, nanos: n}}) do
    %Pb.TransactionID{
      transactionValidStart: %Pb.Timestamp{seconds: s, nanos: n},
      accountID: pb_account(account)
    }
  end

  # nil (omitted) or a Key sub-message
  defp pb_key(nil), do: nil
  defp pb_key(%PublicKey{type: :ed25519} = key), do: %Pb.Key{key: {:ed25519, PublicKey.to_bytes(key)}}
  defp pb_key(%PublicKey{type: :ecdsa_secp256k1} = key), do: %Pb.Key{key: {:ECDSASecp256k1, PublicKey.to_bytes(key)}}

  defp token_type(:fungible), do: :FUNGIBLE_COMMON
  defp token_type(:nft), do: :NON_FUNGIBLE_UNIQUE
  defp supply_type(:infinite), do: :INFINITE
  defp supply_type(:finite), do: :FINITE

  defp encode(mod, struct), do: struct |> mod.encode() |> IO.iodata_to_binary()

  defp unix_now, do: System.system_time(:second)

  defp fetch!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "missing required option #{inspect(key)}"
    end
  end
end
