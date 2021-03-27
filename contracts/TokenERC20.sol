// SPDX-License-Identifier: MIT

pragma solidity 0.6.2;

import "@openzeppelin/contracts/presets/ERC20PresetMinterPauser.sol";

contract TokenERC20 is ERC20PresetMinterPauser {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public ERC20PresetMinterPauser(name, symbol) {
        super._setupDecimals(decimals);
    }
}
