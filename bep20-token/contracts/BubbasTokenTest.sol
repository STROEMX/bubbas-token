// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./BubbasToken.sol";

contract BubbasTokenTest is BUBBAS {

    constructor(address initialOwner, address opsWallet)
        BUBBAS(initialOwner, opsWallet)
    {}

    function name() public pure override returns (string memory) {
        return "BUBBATEST v2";
    }

    function symbol() public pure override returns (string memory) {
        return "BUBBAT2";
    }
}
