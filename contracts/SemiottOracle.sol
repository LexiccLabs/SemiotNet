// SPDX-License-Identifier: Apache License 2.0

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "chainlink/v0.5/contracts/Chainlink.sol";
import "chainlink/v0.5/contracts/ChainlinkClient.sol";


contract SemiottOracle is ChainlinkClient {

    address s_externalAdapter;
    address s_p1;
    address s_p2;
    bytes32 s_chainlinkJobId;

    // The usual state transistion goes
    // INACTIVE -> WAITING_FOR_FUNDS -> WAITING_FOR_REPORT -> INACTIVE ->
    // -> ... -> INACTIVE -> PAYOUT
    // If a problem occurs during WAITING_FOR_FUNDS/WAITING_FOR_REPORT,
    // ESCAPE_HATCH may be triggered by the players.
    // PAYOUT and ESCAPE_HATCH are absorbing states
    enum State {
        _DUMMY,
        INACTIVE,
        WAITING_FOR_FUNDS,
        WAITING_FOR_REPORT,
        PAYOUT,
        ESCAPE_HATCH
    }
    State s_state;

    uint128 s_roundIndex;
    // Tracks how much of a refund is owed to any address that funded the mixicle
    // in the current round. Maps (roundIndex, address) to amount.
    mapping(uint256 => mapping(address => uint256)) s_outstandingRefunds;
    uint256 s_requiredBalance;
    uint256 s_setupDeadline;
    uint256 s_reportDeadline;
    bytes16 s_outcome;
    uint256 s_processedSlateParts;

    /// @param link Address of Chainlink token contract
    /// @param oracle Address of the Chainlink oracle that is permitted
    ///     to report to the mixicle contract.
    /// @param externalAdapter Address of the external adapter delivering
    ///     data to the oracle. Players communicate off-chain with the
    ///     adapter to set up each round.
    ///     This address needs to be freshly chosen for this mixicle
    ///     contract. Using the same address for multiple Mixicles enables
    ///     replay attacks where a message destined to one contract can be
    ///     replayed to another.
    /// @param p1 Address from which player 1 signs messages to the mixicle.
    ///     This address needs to be freshly chosen for this mixicle
    ///     contract. Using the same address for multiple Mixicles enables
    ///     replay attacks where a message destined to one contract can be
    ///     replayed to another.
    /// @param p2 Address from which player 2 signs messages to the mixicle.
    ///     This address needs to be freshly chosen for this mixicle
    ///     contract. Using the same address for multiple Mixicles enables
    ///     replay attacks where a message destined to one contract can be
    ///     replayed to another.
    /// @param chainlinkJobId Job ID to be passed to the Chainlink network
    ///     as part of requests for data.
    constructor(
        address link,
        address oracle,
        address externalAdapter,
        address p1,
        address p2,
        bytes32 chainlinkJobId
    ) public {
        if (link == address(0)) {
            setPublicChainlinkToken();
        } else {
            setChainlinkToken(link);
        }
        setChainlinkOracle(oracle);
        s_externalAdapter = externalAdapter;
        s_p1 = p1;
        s_p2 = p2;
        s_chainlinkJobId = chainlinkJobId;

        s_state = State.INACTIVE;

        // Initialize variables with non-zero values to make cost of
        // call to newRound more consistent
        s_requiredBalance = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        s_setupDeadline = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        s_reportDeadline = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        s_outcome = hex"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";
    }

    /// @notice Start a new round of betting. Can only be called by
    ///     the oracle.
    /// @param dealParams the ABI-encoded parameters describing the
    ///     new round
    /// @param v1 Part of p1's ECDSA signature of `dealParams`
    /// @param r1 Part of p1's ECDSA signature of `dealParams`
    /// @param s1 Part of p1's ECDSA signature of `dealParams`
    /// @param v2 Part of p2's ECDSA signature of `dealParams`
    /// @param r2 Part of p2's ECDSA signature of `dealParams`
    /// @param s2 Part of p2's ECDSA signature of `dealParams`
    /// @param vea Part of external adapter's ECDSA signature of `dealParams`
    /// @param rea Part of external adapter's ECDSA signature of `dealParams`
    /// @param sea Part of external adapter's ECDSA signature of `dealParams`
    function newRound(
        bytes calldata dealParams,
        uint8 v1, bytes32 r1, bytes32 s1,
        uint8 v2, bytes32 r2, bytes32 s2,
        uint8 vea, bytes32 rea, bytes32 sea
    ) external {
        // Verify signatures and decode dealParams
        bytes32 dealParamsHash = keccak256(dealParams);
        require(s_p1 == ecrecover(dealParamsHash, v1, r1, s1), "incorrect sig of p1");
        require(s_p2 == ecrecover(dealParamsHash, v2, r2, s2), "incorrect sig of p2");
        require(s_externalAdapter == ecrecover(dealParamsHash, vea, rea, sea), "incorrect sig of ea");
        newRoundAux(dealParams);
    }

    /// @notice Further logic for newRound. Implemented as a separate
    ///     private function to avoid "stack too deep" errors caused by the
    ///     many arguments of newRound.
    function newRoundAux(bytes memory dealParams) private {
        uint128 roundIndex;
        uint256 requiredBalance;
        uint256 setupDeadline;
        uint256 reportDeadline;
        uint256 dealId;
        uint256 chainlinkPayment;
        // this is a commitment to the terms by the oracle. We don't use it
        // in the contract, we merely wish to record it on-chain.
        bytes32 _termsCommit;
        (
            roundIndex,
            requiredBalance,
            setupDeadline,
            reportDeadline,
            dealId,
            chainlinkPayment,
            _termsCommit
        ) = abi.decode(
            dealParams,
            (uint128, uint256, uint256, uint256, uint256, uint256, bytes32)
        );

        // State machine
        require(s_state == State.INACTIVE);
        if (requiredBalance <= address(this).balance) {
            s_state = State.WAITING_FOR_REPORT;
        } else {
            s_state = State.WAITING_FOR_FUNDS;
        }

        require(block.number <= setupDeadline, "setupDeadline expired");
        require(setupDeadline < reportDeadline, "setupDeadline >= reportDeadline");
        require(s_roundIndex + 1 == roundIndex, "roundIndex must be incremented by one");
        s_roundIndex = roundIndex;
        s_requiredBalance = requiredBalance;
        s_setupDeadline = setupDeadline;
        s_reportDeadline = reportDeadline;

        Chainlink.Request memory request = buildChainlinkRequest(
            s_chainlinkJobId,
            address(this),
            this.report.selector
        );
        request.addUint("dealId", dealId);
        sendChainlinkRequest(request, chainlinkPayment);
    }

    /// @notice Fund the mixicle. To be used by the players
    /// @param refundAddress refund address that funds can be withdrawn to,
    ///     if the setup deadline or the report deadline expire
    function fund(address refundAddress) external payable {
        // State machine
        require(s_state == State.WAITING_FOR_FUNDS);
        if (s_requiredBalance <= address(this).balance) {
            s_state = State.WAITING_FOR_REPORT;
        }

        require(block.number <= s_setupDeadline);

        s_outstandingRefunds[s_roundIndex][refundAddress] += msg.value;
    }

    /// @notice Trigger a refund after the setup deadline has expired
    ///     without the contract being fully funded or the report
    ///     deadline has expired without an oracle report.
    /// @param refundAddress refund address that funds can be withdrawn to,
    ///     previously registered by calling fund().
    function refund(address payable refundAddress) external {
        // State machine
        State state = s_state;
        require(
            state == State.ESCAPE_HATCH
            || (state == State.WAITING_FOR_FUNDS
                && s_setupDeadline < block.number)
            || (state == State.WAITING_FOR_REPORT
                && s_reportDeadline < block.number),
            "invalid state transition"
        );
        if (state != State.ESCAPE_HATCH) {
            s_state = State.ESCAPE_HATCH;
        }

        uint256 amount = s_outstandingRefunds[s_roundIndex][refundAddress];
        s_outstandingRefunds[s_roundIndex][refundAddress] = 0;
        refundAddress.transfer(amount);
    }

    /// @notice Report oracle outcome to the contract. Can only be called by
    ///     the oracle before the report deadline expires.
    ///     Note that the protocol from the Mixicles paper requires the
    ///     outcome tag to be signed by both players to avoid a DoS attack,
    ///     where the oracle reports an invalid outcome tag, causing funds
    ///     to be stuck unless both players cooperate. Due to internal
    ///     implementation details, Chainlink oracles can currently submit
    ///     at most 32 bytes of outcome data, so we diverge from the paper
    ///     by dropping the signatures. In any case, this attack isn't too
    ///     concerning in practice, since the oracle could always mount a
    ///     more "powerful" attack by simply reporting a valid but false
    ///     outcome.
    /// @param outcomeAndRoundIndex the first 16 bytes are a (pseudo-)random
    ///     string/tag identifying the outcome. The next 16 bytes are a
    ///     big-endian unsigned integer containing the round index.
    function report(
        bytes32 requestId,
        bytes32 outcomeAndRoundIndex
    ) external {
        validateChainlinkCallback(requestId);
        bytes16 outcome;
        uint128 roundIndex;

        outcome = bytes16(outcomeAndRoundIndex);
        roundIndex = uint128(uint256(outcomeAndRoundIndex));

        // State machine
        require(s_state == State.WAITING_FOR_REPORT, "mixicle not waiting for report");
        s_state = State.INACTIVE;

        require(block.number <= s_reportDeadline, "block number is not before the report time");
        require(s_requiredBalance <= address(this).balance, "required balance is not present");
        require(s_roundIndex == roundIndex, "wrong round index provided");
        s_outcome = outcome;
    }

    /// @notice Read the latest reported outcome
    function outcome() view external returns (bytes16) {
      return s_outcome;
    }

    /// @notice Trigger payout after oracle report or escape hatch
    /// @param encodedSlatePart Part of a slate, in ABI-encoded format
    ///     We can't require the entire slate to be submitted in one tx,
    ///     because processing it might cost more gas than is available in
    ///     a single block. So we allow partial slates to be submitted and
    ///     use a simple counter mechanism to ensure that no part can be
    ///     submitted twice.
    /// @param v1 Part of p1's ECDSA signature of `encodedSlatePart`
    /// @param r1 Part of p1's ECDSA signature of `encodedSlatePart`
    /// @param s1 Part of p1's ECDSA signature of `encodedSlatePart`
    /// @param v2 Part of p2's ECDSA signature of `encodedSlatePart`
    /// @param r2 Part of p2's ECDSA signature of `encodedSlatePart`
    /// @param s2 Part of p2's ECDSA signature of `encodedSlatePart`
    function payout(
        bytes calldata encodedSlatePart,
        uint8 v1, bytes32 r1, bytes32 s1,
        uint8 v2, bytes32 r2, bytes32 s2
    ) external {
        // Verify signatures and decode call data
        bytes32 encodedSlatePartHash = keccak256(encodedSlatePart);
        require(s_p1 == ecrecover(encodedSlatePartHash, v1, r1, s1), "p1 signature doesn't match");
        require(s_p2 == ecrecover(encodedSlatePartHash, v2, r2, s2), "p2 signature doesn't match");
        uint128 roundIndex;
        bytes16 outcome;
        uint256 index;
        address[] memory slateAddresses;
        uint256[] memory slateAmounts;
        (roundIndex, outcome, index, slateAddresses, slateAmounts) =
            abi.decode(
                encodedSlatePart,
                (uint128, bytes16, uint256, address[], uint256[])
            );

        // State machine
        State state = s_state;
        require(
            state == State.PAYOUT ||
            state == State.ESCAPE_HATCH ||
            state == State.INACTIVE, "wrong state"
        );
        if (state == State.INACTIVE) {
            state = State.PAYOUT;
            s_state = state;
        }

        require(
            (state == State.PAYOUT && s_roundIndex == roundIndex) ||
            (state == State.ESCAPE_HATCH && s_roundIndex == roundIndex + 1),
            "wrong round index"
        );
        require(s_outcome == outcome, "wrong outcome");
        require(s_processedSlateParts == index, "wrong part");
        require(slateAddresses.length == slateAmounts.length, "length mismatch");

        s_processedSlateParts = index + 1;

        for (uint i = 0; i < slateAddresses.length; i++) {
            address payable addr = address(uint160(slateAddresses[i]));
            addr.transfer(slateAmounts[i]);
        }
    }
}
