// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Paperclash (PAPER)
/// @notice A fixed-supply ERC-20. The whole supply, 1,000,000,000 PAPER with 18 decimals, is minted
/// once to the deployer in the constructor. Nothing can mint afterwards, and there is no owner,
/// pause, blacklist, tax or any other privileged hand over a holder's balance.
/// @dev Powered by imd. At launch the deployer is the IMD ProjectFactory, which distributes the
/// supply: the swarm's share to the launch's MerkleDistributor, the pool share into the Uniswap v4
/// pool, and the remainder to the requester. Every transfer moves exactly the amount requested, so
/// each of those flows arrives whole.
contract PaperclashToken is ERC20 {
    /// @notice Token name returned by `name()`.
    string public constant TOKEN_NAME = "Paperclash";

    /// @notice Token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "PAPER";

    /// @notice The one-line description of the token.
    string public constant DESCRIPTION = "Powered by imd";

    /// @notice Number of decimals; the ERC-20 default, restated as a constant for the manifest.
    uint8 public constant DECIMALS = 18;

    /// @notice The fixed supply in minor units: 1,000,000,000 PAPER with 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice Mints the whole fixed supply to the deployer (`msg.sender`).
    /// @dev Takes no arguments and calls no other contract, so it deploys on an empty chain.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
