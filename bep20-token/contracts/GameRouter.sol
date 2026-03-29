// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract GameRouter is Ownable, ReentrancyGuard {

    address public engine;
    address public pendingEngine;

    mapping(bytes32 => address) public game;

    event GameSet(bytes32 indexed gameId, address indexed gameAddress);
    event GameRemoved(bytes32 indexed gameId);
    event GameExecuted(bytes32 indexed gameId, address indexed caller);
    event EngineUpdated(address indexed oldEngine, address indexed newEngine);
    event EngineProposed(address indexed oldEngine, address indexed newEngine);

    constructor(address initialOwner, address engine_) Ownable(initialOwner) {
        require(engine_ != address(0), "Zero engine");
        engine = engine_;
    }

    function setGame(
        bytes32 gameId,
        address gameAddress
    )
        external
        onlyOwner
    {
        require(gameAddress != address(0), "Zero address");

        game[gameId] = gameAddress;

        emit GameSet(gameId, gameAddress);
    }

    function removeGame(bytes32 gameId) external onlyOwner {
        require(game[gameId] != address(0), "Game not set");
        delete game[gameId];
        emit GameRemoved(gameId);
    }

    function setEngine(address newEngine)
        external
        onlyOwner
    {
        require(newEngine != address(0), "Zero address");

        address oldEngine = engine;
        engine = newEngine;

        emit EngineUpdated(oldEngine, newEngine);
    }

    function proposeEngine(address newEngine) external onlyOwner {
        require(newEngine != address(0), "Zero address");
        pendingEngine = newEngine;
        emit EngineProposed(engine, newEngine);
    }

    function acceptEngine() external {
        require(msg.sender == pendingEngine, "Not pending engine");
        emit EngineUpdated(engine, pendingEngine);
        engine = pendingEngine;
        pendingEngine = address(0);
    }

    function execute(
        bytes32 gameId,
        bytes calldata data
    )
        external
        nonReentrant
        returns (bytes memory)
    {
        require(msg.sender == engine, "Not engine");
        require(data.length < 4096, "Data too large");

        address target = game[gameId];

        require(target != address(0), "Game not set");

        (bool success, bytes memory result) =
            target.call(data);

        require(success, "Game call failed");

        emit GameExecuted(gameId, msg.sender);

        return result;
    }
}
