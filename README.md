# Smart Contract Interaction Commands

## Deploy Token
```bash
cast send --rpc-url https://rpc.api.moonbase.moonbeam.network \
    --private-key fa2e32adf2dbf5b3679b1e89b1772fbbc34df4d0afd331f34b133072dc52a432 \
    --legacy \
    --value 10000000000000000 \
    0x3c94fadc6e34bc0a3bf3dc71dac00380d07638c9 \
    "deployERC20Token(string,string)" \
    '"MyToken"' \
    '"MTK"'
```

## Approve Token
```bash
cast send --rpc-url https://rpc.api.moonbase.moonbeam.network \
    --private-key fa2e32adf2dbf5b3679b1e89b1772fbbc34df4d0afd331f34b133072dc52a432 \
    --legacy \
    0x5fa9afadcb439daa5039c3e0a07acabd4e22060c \
    "approve(address,uint256)" \
    "0x4fe8ea21679b3ee10457a097c38452a94edab33b" \
    "1000000000000000000000000000"
```

## Buy Token
```bash
cast send --rpc-url https://rpc.api.moonbase.moonbeam.network \
    --private-key fa2e32adf2dbf5b3679b1e89b1772fbbc34df4d0afd331f34b133072dc52a432 \
    --legacy \
    --value 10000000000000000 \
    0x4fe8ea21679b3ee10457a097c38452a94edab33b \
    "buy(address,uint256,uint256)" \
    "0x5fa9afadcb439daa5039c3e0a07acabd4e22060c" \
    "10000000000000000" \
    "10000000000000000"
```

## Get All Tokens
```bash
cast call --rpc-url https://rpc.api.moonbase.moonbeam.network \
    0x4fe8ea21679b3ee10457a097c38452a94edab33b \
    "getAllTokens()(address[])"
```
Example response:
```
[0x5fA9AFadCb439dAA5039C3E0a07ACaBd4e22060C]
```