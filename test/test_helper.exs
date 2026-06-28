# Tests tagged :network reach the live Hedera testnet and require operator
# credentials in OPERATOR_ID / OPERATOR_KEY. Excluded by default; run with:
#
#     OPERATOR_ID=0.0.x OPERATOR_KEY=0x... mix test --include network
ExUnit.start(exclude: [:network])
