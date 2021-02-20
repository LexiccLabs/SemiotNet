// SPDX-License-Identifier: Apache License 2.0

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;


/**
 * @title Bonding Curve
 * @dev Bonding curve contract based on Bacor formula
 * inspired by bancor protocol and simondlr
 * https://github.com/bancorprotocol/contracts
 * https://github.com/ConsenSys/curationmarkets/blob/master/CurationMarkets.sol
 */

import "./Ownable.sol";
import "./BancorFormula.sol";
import './SafeMath.sol';

import "./SemiottToken.sol";


contract SemiottCurve is Ownable, BancorFormula {

  using SafeMath for uint256;

  SemiottToken public ssmToken;

  struct Holder {
    address   holder;   // holder address
    uint256   ntoken;   // number of bonded token
    uint256   target;    // the target sell price
  }
  // mapping address to associated holder struct
  mapping (address => Holder) public mHolders;
  // the holder array used to find highest target sell price
  address[] public arrayHolders;

  // latest sold price
  uint256 public  curSoldPrice;

  // the number of remaining bonded tokens
  uint256 public  supply;
  uint256 public  initPrice;

  modifier validHolder() {
    require(mHolders[msg.sender].holder != address(0));
    _;
  }

  ///////////////////////////////////////////////////////////////////
  //  Constructor function
  ///////////////////////////////////////////////////////////////////
  // 1. constructor
  constructor(address _tokenAddress) public {
      require(_tokenAddress != address(0));
      // instantiate deployed Ocean token contract
      mToken = Token(_tokenAddress);
      // initial available supply of bonded token
      supply = 100;
      // inital price for bonded token
      initPrice = 1;
  }

  function buyTokens(uint256 _ntoken, uint256 _target) public returns (bool) {
    // first check whether the holder exist, if not, create holder struct
    if (mHolders[msg.sender].holder == address(0)){
        mHolders[msg.sender] = Holder(msg.sender, 0, 0);
        arrayHolders.push(msg.sender);
    }

    // if supply is available, buy bonded token upto available balance with fixed price
    if(supply > 0) {
      uint256 amount = (_ntoken > supply) ? supply : _ntoken;
      // make payment
      require(mToken.transferFrom(msg.sender, address(this), amount.mul(initPrice)));
      // update balance
      mHolders[msg.sender].ntoken = mHolders[msg.sender].ntoken.add(amount);
      // update supply
      supply = supply.sub(amount);
      // update target price
      mHolders[msg.sender].target = _target;
    }

    // if all bonded tokens are sold out, buy from another holders
    // buy the tokens with target price from the nextSeller
    // for time being, we limit the buy amount equals to balance of nextSeller
    // we will improve this to buy more in the next available sellers in the future
    if(supply == 0){
      // find next seller
      address seller = findNextHolder();
      // calculate amount of tokens to buy
      uint256 num =  (_ntoken > mHolders[seller].ntoken) ? mHolders[seller].ntoken : _ntoken;
      // calculate cost
      uint256 cost = num.mul(mHolders[seller].target);
      // make payment
      require(mToken.transferFrom(msg.sender, mHolders[seller].holder, cost));
      // update seller balance
      mHolders[seller].ntoken = mHolders[seller].ntoken.sub(num);
      // update buyer balance
      mHolders[msg.sender].ntoken = mHolders[msg.sender].ntoken.add(num);
      // there is no change in total supply
      mHolders[msg.sender].target = _target;
    }
    return true;
  }

  function sellTokens(uint256 amount) public validHolder returns (bool) {
    // holder shall have enough bonded token to sell
    require(mHolders[msg.sender].ntoken >= amount);
    // calculate payout of reserved token
    uint256 payout = amount.mul(initPrice);
    // ensure the contract has enough reserved token to pay out
    require(mToken.balanceOf(address(this)) >= payout);
    // transfer reserved token to holder
    require(mToken.transfer(msg.sender, payout));
    // decrease the balance of bonded token for seller
    mHolders[msg.sender].ntoken = mHolders[msg.sender].ntoken.sub(amount);
    // update supply
    supply = supply.add(amount);
    return true;
  }

  function changeTargetPrice(uint256 _price) public validHolder returns (bool) {
    // change his target sell price
    mHolders[msg.sender].target = _price;
    return true;
  }

  // query the next available sell price
  function queryNextPrice() public view returns(uint256) {
    //check remaining supply
    if(supply > 0){
      return initPrice;
    } else if (supply == 0){
      return mHolders[findNextHolder()].target;
    }
  }


  function getTokenSupply() public view returns (uint256) {
    return supply;
  }

  // query balance of bonded token
  function getTokenBalance() public view validHolder returns (uint256) {
    return mHolders[msg.sender].ntoken;
  }

  function findNextHolder() internal view returns(address) {
    uint256 maximal = 0;
    for(uint256 i; i < arrayHolders.length; i++){
        // skip holders with zero token balance
        if(mHolders[arrayHolders[i]].ntoken == 0){
          continue;
        }
        // find the holder with highest target sell price
        if(mHolders[arrayHolders[i]].target > mHolders[arrayHolders[maximal]].target){
            maximal = i;
        }
    }

    return mHolders[arrayHolders[maximal]].holder;
  }

}
