// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
 * @title Bonding Curve
 * @dev Bonding curve contract based on polynomial curve that is backed by ether
 * inspired by bancor protocol, oed, simondlr
 * https://github.com/bancorprotocol/contracts
 * https://github.com/oed/bonding-curves/blob/master/contracts/EthBondingCurvedToken.sol
 * https://github.com/ConsenSys/curationmarkets/blob/master/CurationMarkets.sol
 */
contract SemiottCurve is ERC20, Ownable {

  event Minted(uint256 amount, uint256 totalCost);
  event Burned(uint256 amount, uint256 reward);

  uint256 constant private PRECISION = 10000000000;

  /**
   * @dev Available balance of reserve token in contract.
   */
  uint256 public poolBalance;

  /**
   * @dev The exponent of the polynomial bonding curve.
   */
  uint8 public exponent;

  /// @dev constructor    Initializes the bonding curve
  /// @param _name         The name of the token
  /// @param _decimals     The number of decimals to use
  /// @param _symbol       The symbol of the token
  /// @param _exponent        The exponent of the curve
  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    uint8 _exponent
  ) ERC20(_name, _symbol, _decimals) public {
    exponent = _exponent;
  }

  /// @dev        Calculate the integral from 0 to t
  /// @param t    The number to integrate to
  function curveIntegral(uint256 t) internal returns (uint256) {
    uint256 nexp = exponent + 1;
    // Calculate integral of t^exponent
    return PRECISION.div(nexp).mul(t ** nexp).div(PRECISION);
  }

  function priceToMint(uint256 numTokens) public returns(uint256) {
    uint256 totalSupply = totalSupply();
    return curveIntegral(totalSupply.add(numTokens)).sub(poolBalance);
  }

  /**
   * Calculates the amount of reserve tokens (ETH) one receives in exchange for
   * a given number of
   * continuous tokens
   */
  function calculateSaleReturn(uint256 numTokens) public returns(uint256) {
    uint256 totalSupply = totalSupply();
    return poolBalance.sub(curveIntegral(totalSupply.sub(numTokens)));
  }

  /**
   * @dev Buy tokens by minting them
   * @param numTokens The number of tokens you want to mint/buy
   * TODO implement maxAmount that helps prevent miner front-running
   */
  function buy(uint256 numTokens, address account) public payable {
    uint256 priceForTokens = priceToMint(numTokens);
    require(msg.value >= priceForTokens);

    poolBalance = poolBalance.add(msg.value);
    _mint(account, numTokens);

    // Send back refund.
    if (msg.value > priceForTokens) {
      msg.sender.transfer(msg.value - priceForTokens);
    }

    emit Minted(numTokens, priceForTokens);
  }

  /**
   * @dev Sell tokens by burning them to receive ether
   * @param sellAmount Amount of tokens you want to sell
   */
  function sell(uint256 sellAmount) public {
    require(sellAmount > 0 && balanceOf(msg.sender) >= sellAmount);

    /* The amount of ETH to return.
    */
    uint256 ethAmount = calculateSaleReturn(sellAmount);

    poolBalance = poolBalance.sub(ethAmount);
    _burn(msg.sender, sellAmount);

    msg.sender.transfer(ethAmount);

    emit Burned(sellAmount, ethAmount);
  }
}
