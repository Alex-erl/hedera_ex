#!/usr/bin/env bash
# Regenerate the Elixir protobuf modules (lib/hedera/pb/*.pb.ex) from the
# vendored .proto files.
#
# Requires:
#   - protoc          (brew install protobuf)
#   - protoc-gen-elixir plugin:  mix escript.install hex protobuf
#
# Run from anywhere:  priv/protos/generate.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

# protoc-gen-elixir is an Erlang escript: it needs `escript`/`erl` and the plugin
# on PATH. Prepend the mix escripts dir and (on this machine) the Homebrew bin
# that carries the matching OTP; adjust for other setups.
export PATH="${HOME}/.mix/escripts:/opt/homebrew/bin:${PATH}"

protoc \
  --plugin=protoc-gen-elixir="${HOME}/.mix/escripts/protoc-gen-elixir" \
  --elixir_out=lib \
  --proto_path=priv/protos \
  priv/protos/hedera_min.proto

echo "Generated lib/hedera/pb/hedera_min.pb.ex"
