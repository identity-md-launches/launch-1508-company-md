# Company.MD (COMD)

An immutable ERC-20 token. The constructor mints the entire supply once to its immediate caller (`msg.sender`).

| Parameter | Value |
| --- | --- |
| Solidity contract | `CompanyToken` |
| Source | `src/CompanyToken.sol` |
| Token name | `Company.MD` |
| Token symbol | `COMD` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | Immediate deployer; the factory in the IMD launch |
| Launch chain | Ethereum, chain ID `1` |

## Design and assumptions

`CompanyToken` inherits the vendored OpenZeppelin Contracts v5.1.0 ERC-20 implementation and adds only a supply constant and the constructor mint. All transfers deliver the exact requested amount. There are no fees, rebases, transfer restrictions, external calls, or receiver callbacks. The contract has no owner, mint entry point, burn entry point, pause, blacklist, seizure, upgrade, or initializer. The constructor performs no external calls and needs no pre-existing contracts.

Transfers and approvals return `true` on success and revert with OpenZeppelin's ERC-6093 custom errors on failure. Transfers to the zero address and approvals to a zero spender revert. Zero amount transfers between valid addresses succeed and emit `Transfer`; self-transfers preserve the balance. A finite allowance decreases on `transferFrom`; `type(uint256).max` is treated as unlimited. `approve` replaces the allowance and emits `Approval`; spending an allowance does not emit an additional `Approval` event in this OpenZeppelin version.

The requested token is interpreted as a standard ERC-20 without optional permit, governance, taxes, or burn extensions. The deploying factory receives every token, without any constructor allocation to another wallet. There are no external addresses or services to configure in this contract.

## Build and check

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, Cancun, optimizer enabled with 200 runs, and `bytecode_hash = "none"`. FFI and filesystem permissions are not enabled. Dependencies are ordinary source files under `lib/`; no install command, submodule, RPC endpoint, API key, environment configuration, or network is needed once the compiler and Foundry are installed. Dependency versions, exact upstream commits, file hashes, and licenses are recorded alongside each vendored dependency.

The tests cover constructor metadata, a single mint event, direct and CREATE2 factory deployment, exact launch allocation/claim transfers, token movements into and out of a pool custodian, events, zero/self/full-balance transfers, allowances, revocation, infinite approvals, unauthorized spending, revert rollback, unavailable administrative entry points, and forbidden runtime opcodes. Four fuzz tests exercise valid and invalid balance/allowance boundaries. Two stateful invariants compare balances and allowances against an independent accounting model over randomized sequences (128 runs of 64 calls each; fuzz tests use 512 cases each).

The pool custodian test checks ERC-20 movements only. It does not implement or claim to validate Uniswap pool initialization, liquidity accounting, or price behavior. The supplied protected launch harness depends on the network's factory support sources, v4 dependencies, and manifest-derived environment inputs; that integration check is performed by the independent launch verifier. Local tests are self-contained and do not depend on the supplied read files.

## Deployment parameters and responsibilities

Deploy the `CompanyToken` artifact directly from `out/CompanyToken.sol/CompanyToken.json` with no appended constructor arguments and no ETH. Its bytecode has no linked-library placeholders. Do not deploy it through a proxy or a helper that is expected to forward tokens automatically: the immediate contract performing CREATE or CREATE2 receives the full supply. A direct wallet deployment instead credits that wallet. For this launch, the IMD factory is the intended immediate deployer.

The network's separate manifest and deployment steps select the factory and record the deployed address. This repository supplies the token only, with no application contracts or launch manifest. The factory is responsible for distributing the supply according to the provided launch economics: 10% to the swarm distributor, 80% to seed the pool, and the remaining 10% to the requester's designated recipient. These transfers are external to the token and are not administrative rights over it.

### After launch

- No token setters, initialization, ownership transfer, operator, or scheduled maintenance are required.
- The launch operator must verify the source/compiler settings, metadata, exact supply, initial factory credit, and subsequent distribution; then publish the actual token address and verify its source on the chain explorer.
- The launch operator handles pool setup and distribution under the supplied launch policy. The token does not configure or operate a pool or distributor.
- Holders control their balances and spending approvals. Use limited allowances where possible. To replace an existing nonzero allowance safely, submit and confirm a zero allowance before granting the replacement; the standard ERC-20 approval transaction ordering risk remains.
- Tokens sent to a contract that cannot return them, including `CompanyToken` itself, have no administrative recovery path. The token has no payable receive or fallback function.

The implementation was reviewed against the supplied security reference for access control, exact accounting, external calls, arithmetic, and immutable supply. Foundry unit, fuzz, invariant, and runtime-bytecode checks provide local evidence; they are not an independent security audit. Slither and Mythril are not part of this project's checks. Independent adversarial review and deployment verification remain the launch operator's release responsibilities. This assignment does not broadcast transactions or access signing keys.
