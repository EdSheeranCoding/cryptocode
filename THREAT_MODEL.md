# Threat Model

## Overview

This document analyses the security threats against the Hidden Reverse Auction and how the design mitigates each one.

---

## 1. Front-Running Attack

**Threat:** A miner, validator, or MEV bot observes a pending bid transaction in the mempool and submits a lower bid to win the auction.

**Mitigation:** The commit-reveal scheme ensures bids are hidden during the commit phase. Only `keccak256` hashes are visible on-chain — they reveal nothing about the bid amount (pre-image resistance). The deposit can be larger than the actual bid, so even the ETH value of the transaction does not leak bid information. By the time bids are revealed in the reveal phase, no new commits are accepted.

**Residual risk:** If a bidder reveals early in the reveal phase, later revealers can see that bid. This is acceptable because they cannot submit new commits — they can only reveal bids they already locked in.

---

## 2. Replay / Bid Duplication Attack

**Threat:** An attacker copies another bidder's commit hash and submits it as their own, hoping to duplicate a winning bid.

**Mitigation:** Each address can only commit once (`require(commits[msg.sender].hash == bytes32(0))`). Even if an attacker copies a hash, they cannot reveal it without knowing the original `(amount, secret)` pair — the secret is never published on-chain during the commit phase. Without a valid reveal, the attacker's deposit is forfeited.

---

## 3. Non-Reveal Griefing

**Threat:** A bidder commits many bids (via multiple addresses) with no intention of revealing, to pollute the auction or waste other bidders' gas.

**Mitigation:** Every commit requires a non-zero ETH deposit. Non-revealers **forfeit their entire deposit** to the auctioneer. This makes griefing economically costly. The more addresses the attacker uses, the more ETH they lose.

**Residual risk:** A well-funded attacker could still grief by forfeiting large deposits. Future work could add a minimum deposit requirement proportional to expected bid values.

---

## 4. Auctioneer Manipulation

**Threat:** The contract owner (auctioneer) could:
- Advance phases prematurely to cut off legitimate bidders
- Place their own bid with knowledge of other bids
- Refuse to advance to the reveal phase

**Mitigations:**
- **Time-based deadlines**: Phase transitions are enforced by `block.timestamp` — anyone can call `advancePhase()` once the deadline passes, not just the owner.
- **Owner bidding**: The owner could theoretically bid from a separate address. However, during the commit phase all bids are hidden, so the owner has no informational advantage over other bidders.
- **Stalling**: If the owner refuses to advance phases, any user can call `advancePhase()` once the deadline is reached.

**Residual risk:** The owner controls the `grantChallenge()` whitelist and could selectively exclude bidders. In production, challenge verification should be replaced with an on-chain proof system (e.g., ZK proofs) to remove this trust requirement.

---

## 5. Hash Collision / Pre-Image Attack

**Threat:** An attacker finds a different `(amount', secret')` pair that produces the same hash as their original commit, allowing them to change their bid.

**Mitigation:** Keccak-256 has 256-bit output. Finding a collision requires ~2^128 operations (birthday bound), and finding a pre-image requires ~2^256 operations. Both are computationally infeasible with current and foreseeable technology.

---

## 6. Deposit Snooping (Bid Amount Inference)

**Threat:** An observer infers the bid amount from the deposit sent with `commitBid`, since `deposit >= bid_amount`.

**Mitigation:** Bidders are instructed to send a deposit **larger** than their actual bid (the excess is refunded on reveal). This breaks the direct correlation between deposit and bid amount. For example, all bidders could send 1 ETH regardless of their actual bid.

**Residual risk:** If all bidders send exactly their bid amount as deposit, bids are effectively public. Bidder education / frontend defaults should enforce over-depositing.

---

## Concrete Attack Scenario: The Copycat

**Setup:** Alice commits a bid. Bob (an attacker) sees Alice's commit hash on-chain and copies it into his own `commitBid()` call.

**Attack flow:**
1. Alice calls `commitBid(0xabc...)` with 0.5 ETH deposit
2. Bob calls `commitBid(0xabc...)` with 0.5 ETH deposit (same hash)
3. Reveal phase begins
4. Alice reveals `revealBid(100, 0xsecret)` — succeeds
5. Bob tries `revealBid(100, 0xsecret)` — but Bob doesn't know Alice's secret

**Defence:** Bob cannot reveal because he does not know Alice's `secret`. The secret was never published on-chain — Alice computed the hash locally and only submitted the hash. Bob's deposit is forfeited. Even if Bob guesses a random `(amount, secret)` pair, the probability of it matching Alice's hash is 1/2^256.

---

## Summary Table

| Threat | Severity | Mitigated? | Mechanism |
|--------|----------|------------|-----------|
| Front-running | High | Yes | Commit-reveal hides bids |
| Replay / duplication | Medium | Yes | Secret prevents hash reuse |
| Non-reveal griefing | Medium | Partially | Deposit forfeiture |
| Auctioneer manipulation | Medium | Mostly | Time-based deadlines |
| Hash collision | Low | Yes | Keccak-256 security margin |
| Deposit snooping | Low | Partially | Over-deposit recommended |
