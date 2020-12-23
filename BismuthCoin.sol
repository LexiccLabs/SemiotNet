pragma solidity ^0.5.0;

import "./@openzeppelin/contracts/access/Roles.sol";
import "./@openzeppelin/contracts/token/ERC20/ERC20Fee.sol";
import "@aztec/protocol/contracts/ERC1724/ZkAssetMintable.sol";
import "@aztec/protocol/contracts/ERC1724/ZkAsset.sol";

contract BismuthCoin is ERC20Fee, ZkAssetMintable, ZkAsset {
    using Roles for Roles.Role;

    Roles.Role private _minters;
    Roles.Role private _burners;

    /**
     * @dev Emitted when account get access to {MinterRole}
     */
    event MinterAdded(address indexed account);

    /**
     * @dev Emitted when account get access to {BurnerRole}
     */
    event BurnerAdded(address indexed account);

    /**
     * @dev Emitted when an account loses access to the {MinterRole}
     */
    event MinterRemoved(address indexed account);

    /**
     * @dev Emitted when an account loses access to the {BurnerRole}
     */
    event BurnerRemoved(address indexed account);

    /**
     * @dev Throws if caller does not have the {MinterRole}
     */
    modifier onlyMinter() {
        require(
            isMinter(_msgSender()),
            "MinterRole: caller does not have the Minter role"
        );
        _;
    }

    /**
     * @dev Throws if caller does not have the {BurnerRole}
     */
    modifier onlyBurner() {
        require(
            isBurner(_msgSender()),
            "BurnerRole: caller does not have the Burner role"
        );
        _;
    }

    /**
     * @dev Sets the values for `name`, `symbol`, `decimals`
     * and gives owner {MinterRole} and {BurnerRole}
     * @param name The name of the token
     * @param symbol The symbol of the token 
     * @param decimals The number of decimals the token uses
     * @notice `name`, `symbol` and `decimals`
     * values are immutable: they can only be set once during construction
     */
    constructor(string memory name, string memory symbol, uint8 decimals)
        public
        ERC20Fee(name, symbol, decimals)
    {
        _addMinter(_msgSender());
        _addBurner(_msgSender());
    }

    /**
     * @dev Give an account access to {MinterRole}
     * @param account Account address
     */
    function addMinter(address account) external onlyOwner {
        _addMinter(account);
    }

    /**
     * @dev Give an account access to {BurnerRole}
     * @param account Account address
     */
    function addBurner(address account) external onlyOwner {
        _addBurner(account);
    }

    /**
    /**
     * @dev Remove an account's access to {MinterRole}
     * @param account Account address
     */
    function renounceMinter(address account) external onlyOwner {
        _removeMinter(account);
    }

    /**
     * @dev Remove an account's access to {BurnerRole}
     * @param account Account address
     */
    function renounceBurner(address account) external onlyOwner {
        _removeBurner(account);
    }

    /**
     * @dev Check if an account has {MinterRole}
     * @param account Account address
     * @return bool
     */
    function isMinter(address account) public view returns (bool) {
        return _minters.has(account);
    }

    /**
     * @dev Check if an account has {BurnerRole}
     * @param account Account address
     * @return bool
     */
    function isBurner(address account) public view returns (bool) {
        return _burners.has(account);
    }

    /**
     * @dev Mint `amount` of tokens `to` recipient. See {ERC20-_mint}
     * @param to Account address of recipient
     * @param amount Amount to mint
     * @notice Requirements:
     * the caller must have the {MinterRole}
     * @return bool
     */
    function mint(address to, uint256 amount)
        external
        onlyMinter
        returns (bool)
    {
        _mint(to, amount);
        return true;
    }

    /**
     * @dev Destroys `amount` of tokens from the caller. See {ERC20-_mint}
     * @param amount Amount to burn
     * @notice Requirements:
     * the caller must have the {BurnerRole}
     * @return bool
     */
    function burn(uint256 amount) external onlyBurner returns (bool) {
        _burn(_msgSender(), amount);
    }

    // Internal functions
    function _addMinter(address account) internal {
        _minters.add(account);
        emit MinterAdded(account);
    }

    function _addBurner(address account) internal {
        _burners.add(account);
        emit BurnerAdded(account);
    }

    function _removeMinter(address account) internal {
        _minters.remove(account);
        emit MinterRemoved(account);
    }

    function _removeBurner(address account) internal {
        _burners.remove(account);
        emit BurnerRemoved(account);
    }
}
