# Demo Guide — Remix IDE

## Setup

1. Open [Remix IDE](https://remix.ethereum.org)
2. Create a new file `ReverseAuction.sol` and paste the contract code
3. Compile with Solidity ^0.8.24
4. In "Deploy & Run", select **Injected Provider - MetaMask** and connect to **Sepolia**
5. Deploy with constructor args, e.g.: `300, 300` (5 min commit, 5 min reveal)

## Happy Path Demo

### Step 1: Grant challenge access
Using the owner account (the deployer):
```
grantChallenge(<Bidder1_address>)
grantChallenge(<Bidder2_address>)
```

### Step 2: Bidders compute their hashes
In Remix, call the **read-only** helper with each bidder's values:
```
computeHash(100, 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef)
→ returns 0x...

computeHash(200, 0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd)
→ returns 0x...
```
Note: the `secret` is a `bytes32` value — any 32-byte hex string.

### Step 3: Commit bids
Switch to Bidder1's account in MetaMask:
- Set **Value** to `0.001 ether` (deposit — must be ≥ actual bid)
- Call `commitBid(<hash_from_step_2>)`

Repeat for Bidder2 with their hash.

### Step 4: Advance to Reveal phase
As owner (or anyone after deadline): call `advancePhase()`

### Step 5: Reveal bids
Switch to Bidder1:
```
revealBid(100, 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef)
```
Switch to Bidder2:
```
revealBid(200, 0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd)
```

### Step 6: Settle
Call `advancePhase()` → contract settles automatically.

Check: `winner()` → Bidder1's address (lowest unique bid: 100 < 200)
Check: `winningBid()` → 100

## Edge Case Demos

### Bad reveal (tampered bid)
A bidder tries to reveal a different amount than committed:
```
revealBid(50, 0x1234...)  // committed with amount=100
→ Reverts: "Hash mismatch — bid tampered or wrong secret"
```

### No challenge access
An un-whitelisted address tries to commit:
```
commitBid(0x...)
→ Reverts: "Challenge not passed"
```

### Non-revealer penalty
Bidder3 commits but never reveals. After settlement:
- Bidder3's deposit is forfeited (shown in `DepositForfeited` event)
- Owner can call `withdrawForfeited()` to claim it

## Deployment Checklist
- [ ] Contract deployed to Sepolia
- [ ] Contract address recorded: `_______________`
- [ ] Etherscan verification (optional): paste source code at etherscan.io/verifyContract
