# System Design

## Actors

| Actor | Role | Trust level |
|-------|------|-------------|
| **Auctioneer** (contract owner) | Deploys contract, grants challenge access, can advance phases | Semi-trusted — could manipulate phase timing (mitigated by time-based deadlines) |
| **Bidders** | Submit hidden bids, reveal them, compete to win | Untrusted — may try to cheat, front-run, or grief |
| **Ethereum Miners/Validators** | Order transactions within blocks | Untrusted — could front-run if bids were visible (commit-reveal prevents this) |
| **Oracle** (future work) | Could verify off-chain challenge completion | Not implemented — replaced by owner whitelist for demo |

## Trust Assumptions

1. **Keccak-256 is secure** — pre-image and collision resistance hold.
2. **Ethereum consensus is honest** — transactions are eventually included and ordered fairly (within the bounds of MEV).
3. **The auctioneer is semi-honest** — they follow the protocol but might try to gain an advantage. Time-based deadlines limit their ability to manipulate phase transitions.
4. **Bidders are rational** — they are incentivized to reveal (deposit forfeiture penalty) and to bid competitively (lowest bid wins the contract).

## Protocol Flow

```
┌─────────────────────────────────────────────────────────┐
│                   SETUP                                  │
│  Owner deploys contract with commit + reveal durations   │
│  Owner grants challenge access to eligible bidders       │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│                COMMIT PHASE                              │
│                                                          │
│  For each bidder:                                        │
│    1. Compute hash = keccak256(amount, secret) off-chain │
│    2. Call commitBid(hash) with deposit ≥ amount         │
│       → Contract stores hash + deposit                   │
│       → Deposit hides real bid (can overpay)             │
│                                                          │
│  Ends: commitDeadline or owner advances                  │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│                REVEAL PHASE                               │
│                                                          │
│  For each bidder:                                        │
│    1. Call revealBid(amount, secret)                      │
│       → Contract verifies keccak256(amount, secret)      │
│         matches stored hash (binding property)           │
│       → Excess deposit refunded immediately              │
│                                                          │
│  Non-revealers: deposit is forfeited (anti-griefing)     │
│                                                          │
│  Ends: revealDeadline or owner advances                  │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│               SETTLEMENT PHASE                           │
│                                                          │
│  1. Find lowest bid among revealed bids                   │
│  2. Winner awarded the service contract                   │
│  3. All revealers get deposits refunded                   │
│  4. Non-revealer deposits forfeited to auctioneer         │
│  5. Emit AuctionSettled event                             │
└─────────────────────────────────────────────────────────┘
```

## Why Commit-Reveal Prevents Front-Running

In a naive auction (bids visible on-chain), a miner or MEV bot could:
1. See a pending `placeBid(100 wei)` in the mempool
2. Submit their own `placeBid(99 wei)` with higher gas to get included first

With commit-reveal:
- During the commit phase, only **hashes** are visible on-chain. The hash reveals nothing about the bid amount (hiding property of keccak256).
- The deposit amount is deliberately allowed to be **larger** than the actual bid, so even the ETH sent with the commit does not leak the bid value.
- By the time bids are revealed, it is too late to submit new bids — the commit phase is closed.

## Deposit Design

The deposit serves two purposes:
1. **Hides bid amount** — bidders send more ETH than their actual bid, so observers cannot infer the bid from the transaction value.
2. **Anti-griefing** — if a bidder does not reveal, they lose their entire deposit, discouraging commit-and-abandon attacks.

Excess deposit (deposit minus actual bid) is refunded immediately upon reveal.

## Failure Cases

| Scenario | Handling |
|----------|----------|
| Bidder commits but never reveals | Deposit forfeited to auctioneer |
| Bidder tries to reveal a different amount | Hash mismatch → `revealBid` reverts |
| No bids at all | Settlement completes with no winner |
| Multiple bidders tie for lowest | First revealer with that amount wins |
| Bidder tries to bid without passing challenge | `commitBid` reverts with "Challenge not passed" |
| Bidder tries to commit twice | `commitBid` reverts with "Already committed" |
