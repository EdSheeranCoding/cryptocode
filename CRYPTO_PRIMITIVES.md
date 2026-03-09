# Cryptographic Primitives Used

## 1. Keccak-256 Hash Function (Commit-Reveal Scheme)

**What it is:** Keccak-256 is the hash function used natively in Ethereum (`keccak256` in Solidity). It takes arbitrary input and produces a fixed 256-bit digest.

**How we use it:** Bidders compute `keccak256(abi.encodePacked(bid_amount, secret))` off-chain and submit only the hash during the commit phase. During the reveal phase they submit the original `(bid_amount, secret)` pair and the contract recomputes the hash to verify it matches.

**Security properties provided:**

| Property | What it means | Why it matters |
|----------|--------------|----------------|
| **Hiding** (pre-image resistance) | Given a hash `H`, it is computationally infeasible to find any input that hashes to `H` | No one (including miners and other bidders) can determine the bid amount from the on-chain hash |
| **Binding** (second pre-image resistance) | Given an input `x`, it is infeasible to find a different `x'` with the same hash | A bidder cannot change their bid after committing — any different `(amount, secret)` pair will produce a different hash |
| **Collision resistance** | Infeasible to find any two distinct inputs with the same hash | Prevents two different bids from accidentally colliding |

**Why keccak256 specifically?** It is the Ethereum-native hash — using it in Solidity costs only 30 gas + 6 gas/word, making it the most gas-efficient choice. It is also the same function underlying Ethereum's Merkle-Patricia tries and address derivation, so it is battle-tested on the network.

## 2. ECDSA Digital Signatures (Ethereum Transaction Signing)

**What it is:** Every Ethereum transaction is signed with the sender's private key using the Elliptic Curve Digital Signature Algorithm (secp256k1 curve). The signature is verified by network nodes before a transaction is included in a block.

**How we use it (implicitly):** When a bidder calls `commitBid()` or `revealBid()`, their wallet (e.g., MetaMask) signs the transaction with their private key. The EVM recovers the signer's address and sets `msg.sender`, which the contract trusts as the authenticated identity of the caller.

**Security properties provided:**

| Property | What it means | Why it matters |
|----------|--------------|----------------|
| **Authentication** | Only the holder of a private key can produce a valid signature for the corresponding address | Ensures only the actual bidder can commit/reveal their bid |
| **Non-repudiation** | A signed transaction proves the signer authorized it | A bidder cannot deny having placed a bid |
| **Integrity** | Any modification to the signed transaction invalidates the signature | Prevents tampering with bid data in transit |

## 3. Why These Two Are Sufficient

The commit-reveal scheme (keccak256) provides **bid privacy** — no one can see bids until the reveal phase. ECDSA signatures provide **identity and authorization** — only legitimate, authenticated users can interact with the contract.

Together they achieve the core goal: **a fair auction where bids are hidden during bidding and tamper-proof after submission**.

## 4. Future Work — Additional Primitives

| Primitive | Potential use |
|-----------|--------------|
| **Zero-Knowledge Proofs (ZKPs)** | Replace mock challenge verification with a real proof that the user solved a challenge, without revealing the solution |
| **Time-Lock Encryption** | Encrypt bids such that they can only be decrypted after a certain block height, removing the need for a reveal phase entirely |
| **Merkle Trees** | If scaling to many bidders, a Merkle root could commit to a batch of bids efficiently |
| **Ring Signatures** | Could provide bidder anonymity (hide *who* bid, not just *what* they bid) |
