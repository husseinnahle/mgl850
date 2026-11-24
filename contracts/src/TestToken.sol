// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TestToken
/// @notice Jeton ERC-20 de test du protocole (EF-10).
/// @dev Deux instances sont déployées : tETH (18 décimales), la garantie fongible,
///      et tUSDC (6 décimales, comme le vrai USDC), l'actif prêté et emprunté.
contract TestToken is ERC20, Ownable {
    uint8 private immutable _decimals;

    /// @notice Quantité de jetons remise à chaque appel de `faucet`.
    uint256 public immutable faucetAmount;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 faucetAmount_, address owner_)
        ERC20(name_, symbol_)
        Ownable(owner_)
    {
        _decimals = decimals_;
        faucetAmount = faucetAmount_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Émet des jetons pour une adresse. Réservé au propriétaire, pour préparer une démonstration.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Remet `faucetAmount` jetons à l'appelant, pour essayer le protocole sur le réseau de test.
    function faucet() external {
        _mint(msg.sender, faucetAmount);
    }
}
