// SPDX-License-Identifier: Apache License 2.0

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

interface IBeaconContract {
    /*
      If there is a randomness that was calculated based on blockNumber, returns it.
      Otherwise, returns 0.
    */
    function getRandomness(uint256 blockNumber) external view returns (bytes32);

    /*
      Returns the latest pair of (blockNumber, randomness) that was registered.
    */
    function getLatestRandomness() external view returns (uint256, bytes32);
}
