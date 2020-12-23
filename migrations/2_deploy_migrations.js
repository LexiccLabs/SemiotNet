var BismuthCoin = artifacts.require("./BismuthCoin..sol");
var Ethereum934 = artifacts.require("./Ethereum934.sol");

module.exports = function(deployer) {
  deployer.deploy(Ethereum934, web3.eth.getAccounts().then(function (f) { return f[9] }));
  deployer.deploy(BismuthCoin, { value: 15000000000000000000 });
};
