// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ReverseAuction
 * @notice A reverse auction with hidden bids using commit-reveal scheme.
 *         Lowest bid wins. Challenge-gated participation (e.g., CTF).
 *
 * Use case: A company (auctioneer) posts a challenge (e.g., CTF). Security
 * researchers who solve it can bid to offer their services. The lowest
 * bidder wins the contract — sellers competing on price.
 *
 * Cryptographic primitives used:
 *   - keccak256: commit-reveal hiding & binding
 *   - ECDSA (implicit): Ethereum tx signatures for identity/authentication
 *
 * Phases: COMMIT → REVEAL → SETTLED
 */
contract ReverseAuction {
    // ─── Types ───────────────────────────────────────────────────────────
    enum Phase { COMMIT, REVEAL, SETTLED }

    struct Commit {
        bytes32 hash;       // keccak256(abi.encodePacked(amount, secret))
        uint256 deposit;    // ETH locked with commit
        bool revealed;      // whether bid was revealed
        uint256 revealedAmt;// the actual bid amount (set on reveal)
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public owner;
    Phase   public phase;

    uint256 public commitDeadline;
    uint256 public revealDeadline;

    // challenge whitelist (mock verification)
    mapping(address => bool) public challengePassed;

    // bids
    mapping(address => Commit) public commits;
    address[] public bidders;

    // result
    address public winner;
    uint256 public winningBid;
    bool    public settled;


    // ─── Events ──────────────────────────────────────────────────────────
    event ChallengeVerified(address indexed user);
    event BidCommitted(address indexed bidder, bytes32 hash);
    event BidRevealed(address indexed bidder, uint256 amount);
    event AuctionSettled(address indexed winner, uint256 winningBid);
    event PhaseAdvanced(Phase newPhase);
    event Refunded(address indexed bidder, uint256 amount);
    event DepositForfeited(address indexed bidder, uint256 amount);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier inPhase(Phase _phase) {
        require(phase == _phase, "Wrong phase");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    /**
     * @param _commitDurationSecs  seconds the commit phase lasts
     * @param _revealDurationSecs  seconds the reveal phase lasts (after commit ends)
     */
    constructor(uint256 _commitDurationSecs, uint256 _revealDurationSecs) {
        owner = msg.sender;
        phase = Phase.COMMIT;
        commitDeadline = block.timestamp + _commitDurationSecs;
        revealDeadline = commitDeadline + _revealDurationSecs;
    }

    // ─── Challenge Verification (Mock) ───────────────────────────────────
    /**
     * @notice Mock challenge gate. In production this would verify a ZK proof
     *         or check an oracle attestation. For the demo the owner whitelists
     *         addresses, simulating "passing a challenge".
     */
    function grantChallenge(address _user) external onlyOwner {
        challengePassed[_user] = true;
        emit ChallengeVerified(_user);
    }

    function verifyChallenge(address _user) public view returns (bool) {
        return challengePassed[_user];
    }

    // ─── Phase Management ────────────────────────────────────────────────
    /**
     * @notice Advance phase. Can be called by anyone once the deadline has passed,
     *         or by the owner at any time (for demo flexibility).
     */
    function advancePhase() external {
        if (phase == Phase.COMMIT) {
            require(
                block.timestamp >= commitDeadline || msg.sender == owner,
                "Commit phase not over"
            );
            phase = Phase.REVEAL;
            emit PhaseAdvanced(Phase.REVEAL);
        } else if (phase == Phase.REVEAL) {
            require(
                block.timestamp >= revealDeadline || msg.sender == owner,
                "Reveal phase not over"
            );
            phase = Phase.SETTLED;
            _settle();
            emit PhaseAdvanced(Phase.SETTLED);
        } else {
            revert("Already settled");
        }
    }

    // ─── Commit Phase ────────────────────────────────────────────────────
    /**
     * @notice Submit a hidden bid. The hash commits the bidder to a specific
     *         (amount, secret) pair without revealing it.
     * @param _hash  keccak256(abi.encodePacked(uint256 amount, bytes32 secret))
     *
     * The msg.value sent is the deposit. It must be >= actual bid amount
     * (verified at reveal time). This hides the real bid amount since the
     * deposit can be larger.
     */
    function commitBid(bytes32 _hash) external payable inPhase(Phase.COMMIT) {
        require(verifyChallenge(msg.sender), "Challenge not passed");
        require(commits[msg.sender].hash == bytes32(0), "Already committed");
        require(msg.value > 0, "Must deposit ETH");

        commits[msg.sender] = Commit({
            hash: _hash,
            deposit: msg.value,
            revealed: false,
            revealedAmt: 0
        });
        bidders.push(msg.sender);

        emit BidCommitted(msg.sender, _hash);
    }

    // ─── Reveal Phase ────────────────────────────────────────────────────
    /**
     * @notice Reveal a previously committed bid. The contract recomputes the
     *         hash and checks it matches the commit — this is the **binding**
     *         property of keccak256: the bidder cannot change their bid.
     * @param _amount  the bid amount in wei
     * @param _secret  the secret used when committing
     */
    function revealBid(uint256 _amount, bytes32 _secret) external inPhase(Phase.REVEAL) {
        Commit storage c = commits[msg.sender];
        require(c.hash != bytes32(0), "No commit found");
        require(!c.revealed, "Already revealed");

        // Verify hash — binding property
        bytes32 computed = keccak256(abi.encodePacked(_amount, _secret));
        require(computed == c.hash, "Hash mismatch — bid tampered or wrong secret");

        // Deposit must cover bid
        require(c.deposit >= _amount, "Deposit less than bid");

        c.revealed = true;
        c.revealedAmt = _amount;

        // Refund excess deposit immediately
        uint256 excess = c.deposit - _amount;
        if (excess > 0) {
            c.deposit = _amount; // update stored deposit to actual bid
            (bool ok, ) = payable(msg.sender).call{value: excess}("");
            require(ok, "Refund failed");
            emit Refunded(msg.sender, excess);
        }

        emit BidRevealed(msg.sender, _amount);
    }

    // ─── Settlement ──────────────────────────────────────────────────────
    /**
     * @dev Internal: find the lowest bid and pay the winner.
     *      Non-revealers forfeit their deposit (anti-griefing).
     *      This is a sellers' auction — lowest price wins the contract.
     */
    function _settle() internal {
        settled = true;

        // 1. Find lowest bid
        uint256 lowestBid = type(uint256).max;
        address lowestAddr = address(0);

        for (uint256 i = 0; i < bidders.length; i++) {
            address b = bidders[i];
            Commit storage c = commits[b];

            if (!c.revealed) {
                // Forfeit deposit for non-revealers
                emit DepositForfeited(b, c.deposit);
                continue;
            }

            if (c.revealedAmt < lowestBid) {
                lowestBid = c.revealedAmt;
                lowestAddr = b;
            }
        }

        // 2. If we found a winner
        if (lowestAddr != address(0)) {
            winner = lowestAddr;
            winningBid = lowestBid;
            emit AuctionSettled(lowestAddr, lowestBid);
        }

        // 3. Refund all revealers (they are sellers, not buyers — their
        //    deposits are just collateral to ensure they reveal)
        for (uint256 i = 0; i < bidders.length; i++) {
            address b = bidders[i];
            Commit storage c = commits[b];

            if (c.revealed && c.deposit > 0) {
                uint256 refund = c.deposit;
                c.deposit = 0;
                (bool ok, ) = payable(b).call{value: refund}("");
                require(ok, "Refund failed");
                emit Refunded(b, refund);
            }
        }
    }

    // ─── View Helpers ────────────────────────────────────────────────────
    function getBidderCount() external view returns (uint256) {
        return bidders.length;
    }

    function getPhase() external view returns (string memory) {
        if (phase == Phase.COMMIT) return "COMMIT";
        if (phase == Phase.REVEAL) return "REVEAL";
        return "SETTLED";
    }

    /**
     * @notice Helper to compute the commit hash off-chain or in Remix console.
     *         Users should call this BEFORE committing to generate their hash.
     */
    function computeHash(uint256 _amount, bytes32 _secret) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(_amount, _secret));
    }

    // ─── Emergency ───────────────────────────────────────────────────────
    /**
     * @notice Owner can withdraw any remaining ETH after settlement
     *         (forfeited deposits from non-revealers).
     */
    function withdrawForfeited() external onlyOwner {
        require(settled, "Not settled yet");
        uint256 bal = address(this).balance;
        require(bal > 0, "Nothing to withdraw");
        (bool ok, ) = payable(owner).call{value: bal}("");
        require(ok, "Withdraw failed");
    }
}
