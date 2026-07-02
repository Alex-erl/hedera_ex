# Examples

Runnable scripts. Network examples read the operator from the environment:

```bash
export OPERATOR_ID=0.0.xxxxxxx
export OPERATOR_KEY=0x...            # ECDSA secp256k1 hex

mix run examples/hcs.exs
mix run examples/token_lifecycle.exs
mix run examples/queries.exs
```

`eip1559_offline.exs` needs no network or credentials:

```bash
mix run examples/eip1559_offline.exs
```
