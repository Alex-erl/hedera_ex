defmodule Hedera.QueryTest do
  @moduledoc "Offline wire-contract checks for the paid/free crypto queries."
  use ExUnit.Case, async: true

  alias Hedera.{Pb, Proto}

  test "CryptoGetAccountBalanceQuery sits at Query oneof field 7, accountID at field 2" do
    q = %Pb.Query{
      query:
        {:cryptogetAccountBalance,
         %Pb.CryptoGetAccountBalanceQuery{
           header: %Pb.QueryHeader{responseType: :ANSWER_ONLY},
           balanceSource: {:accountID, %Pb.AccountID{shardNum: 0, realmNum: 0, accountNum: 1234}}
         }}
    }

    bytes = Pb.Query.encode(q) |> IO.iodata_to_binary()

    # raw wire: Query field 7 -> CryptoGetAccountBalanceQuery, accountID = field 2
    inner = Proto.decode(Proto.field(Proto.decode(bytes), 7))
    assert Proto.field(Proto.decode(Proto.field(inner, 2)), 3) == 1234

    # and it round-trips through the generated decoder
    assert {:cryptogetAccountBalance, sub} = Pb.Query.decode(bytes).query
    assert sub.balanceSource == {:accountID, %Pb.AccountID{shardNum: 0, realmNum: 0, accountNum: 1234}}
  end

  test "CryptoGetInfoQuery sits at Query oneof field 9 with accountID" do
    q = %Pb.Query{
      query:
        {:cryptoGetInfo,
         %Pb.CryptoGetInfoQuery{
           header: %Pb.QueryHeader{responseType: :ANSWER_ONLY},
           accountID: %Pb.AccountID{shardNum: 0, realmNum: 0, accountNum: 55}
         }}
    }

    bytes = Pb.Query.encode(q) |> IO.iodata_to_binary()
    assert is_binary(Proto.field(Proto.decode(bytes), 9))
    assert {:cryptoGetInfo, sub} = Pb.Query.decode(bytes).query
    assert sub.accountID.accountNum == 55
  end

  test "balance response carries hbar + token balances (field 7)" do
    resp = %Pb.Response{
      response:
        {:cryptogetAccountBalance,
         %Pb.CryptoGetAccountBalanceResponse{
           balance: 4200,
           tokenBalances: [%Pb.TokenBalance{tokenId: %Pb.TokenID{shardNum: 0, realmNum: 0, tokenNum: 7}, balance: 9, decimals: 2}]
         }}
    }

    bytes = Pb.Response.encode(resp) |> IO.iodata_to_binary()
    assert {:cryptogetAccountBalance, r} = Pb.Response.decode(bytes).response
    assert r.balance == 4200
    assert [tb] = r.tokenBalances
    assert {tb.tokenId.tokenNum, tb.balance, tb.decimals} == {7, 9, 2}
  end

  test "account-info response carries the AccountInfo (field 9)" do
    resp = %Pb.Response{
      response:
        {:cryptoGetInfo,
         %Pb.CryptoGetInfoResponse{
           accountInfo: %Pb.AccountInfo{
             accountID: %Pb.AccountID{shardNum: 0, realmNum: 0, accountNum: 1001},
             balance: 500,
             memo: "hi",
             ownedNfts: 3,
             deleted: false
           }
         }}
    }

    bytes = Pb.Response.encode(resp) |> IO.iodata_to_binary()
    assert {:cryptoGetInfo, r} = Pb.Response.decode(bytes).response
    assert r.accountInfo.accountID.accountNum == 1001
    assert r.accountInfo.balance == 500
    assert r.accountInfo.memo == "hi"
    assert r.accountInfo.ownedNfts == 3
  end
end
