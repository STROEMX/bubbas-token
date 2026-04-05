// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IBUBBAS {
    function systemPayout(address from, address to, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

contract PayoutManager is Ownable, ReentrancyGuard {

    // -------------------------------------------------------------------------
    // TYPES
    // -------------------------------------------------------------------------
    enum PoolType { LOTTERY, JACKPOT, BANKROLL, RESERVE }

    struct PoolConfig {
        address wallet;
        uint256 payoutLimitPerBlock;
        uint256 payoutLimitPerMinute;
        uint256 cooldownSeconds;        // min seconds between payouts
        uint16  maxValuePerMinuteBps;   // max % of pool balance per minute (BPS)
        uint16  maxSinglePayoutBps;     // max % of pool balance per payout (BPS)
        uint16  minReserveBps;          // min % that must remain after payout (BPS)
        bool    drainsOnPayout;         // true = can drain to zero
        bool    enabled;
        bool    initialized;            // must be true before payouts
    }

    struct PoolUsage {
        uint256 lastBlock;
        uint256 blockUsed;
        uint256 lastMinute;
        uint256 minuteUsed;
        uint256 lastPayoutTime;         // timestamp of last payout (cooldown)
    }

    // -------------------------------------------------------------------------
    // STATE
    // -------------------------------------------------------------------------
    IBUBBAS public immutable token;
    address public engine;
    address public pendingEngine;
    bool public globalPaused;
    uint256 public maxRecipientsPerTx = 200;
    uint256 public maxPoolBalance;
    uint256 public dailyPayoutTotal;
    uint256 public lastDailyReset;

    mapping(PoolType => PoolConfig) public poolConfig;
    mapping(PoolType => PoolUsage) private poolUsage;

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------
    event Payout(PoolType indexed poolType, address indexed to, uint256 amount);
    event PayoutRejected(PoolType indexed poolType, address indexed to, uint256 amount, string reason);
    event PoolConfigUpdated(PoolType indexed poolType);
    event PoolInitialized(PoolType indexed poolType);
    event PoolEnabled(PoolType indexed poolType, bool enabled);
    event PoolWalletSet(PoolType indexed poolType, address indexed wallet);
    event EngineUpdated(address indexed oldEngine, address indexed newEngine);
    event EngineProposed(address indexed oldEngine, address indexed newEngine);
    event GlobalPaused(bool paused);
    event MaxRecipientsPerTxUpdated(uint256 newLimit);
    event MaxPoolBalanceUpdated(uint256 newLimit);
    event EmergencyWithdraw(address indexed to, uint256 amount, uint256 timestamp);
    event DailyPayoutUsed(uint256 amount, uint256 totalToday);

    // -------------------------------------------------------------------------
    // MODIFIERS
    // -------------------------------------------------------------------------
    modifier onlyEngine() {
        require(msg.sender == engine, "Not engine");
        _;
    }

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------
    constructor(
        address initialOwner,
        address engine_,
        address token_
    ) Ownable(initialOwner) {
        require(engine_ != address(0), "Zero engine");
        require(token_ != address(0), "Zero token");
        engine = engine_;
        token = IBUBBAS(token_);
    }

    // -------------------------------------------------------------------------
    // ENGINE MANAGEMENT
    // -------------------------------------------------------------------------
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

    function setGlobalPaused(bool paused) external onlyOwner {
        globalPaused = paused;
        emit GlobalPaused(paused);
    }

    function setMaxRecipientsPerTx(uint256 newLimit) external onlyOwner {
        require(newLimit > 0, "Zero limit");
        maxRecipientsPerTx = newLimit;
        emit MaxRecipientsPerTxUpdated(newLimit);
    }

    function setMaxPoolBalance(uint256 newLimit) external onlyOwner {
        maxPoolBalance = newLimit;
        emit MaxPoolBalanceUpdated(newLimit);
    }

    // -------------------------------------------------------------------------
    // POOL CONFIGURATION (ENGINE-ONLY)
    // -------------------------------------------------------------------------
    function setPoolWallet(PoolType poolType, address wallet) external onlyEngine {
        require(wallet != address(0), "Zero address");
        poolConfig[poolType].wallet = wallet;
        emit PoolWalletSet(poolType, wallet);
    }

    function setPoolConfig(
        PoolType poolType,
        uint256 payoutLimitPerBlock,
        uint256 payoutLimitPerMinute,
        uint256 cooldownSeconds,
        uint16  maxValuePerMinuteBps,
        uint16  maxSinglePayoutBps,
        uint16  minReserveBps,
        bool    drainsOnPayout
    ) external onlyEngine {
        require(payoutLimitPerBlock > 0, "Block limit required");
        require(payoutLimitPerMinute > 0, "Minute limit required");
        require(maxSinglePayoutBps > 0 && maxSinglePayoutBps <= 10_000, "Invalid single BPS");
        require(maxValuePerMinuteBps <= 10_000, "BPS overflow");
        require(minReserveBps <= 10_000, "BPS overflow");

        PoolConfig storage cfg = poolConfig[poolType];
        cfg.payoutLimitPerBlock = payoutLimitPerBlock;
        cfg.payoutLimitPerMinute = payoutLimitPerMinute;
        cfg.cooldownSeconds = cooldownSeconds;
        cfg.maxValuePerMinuteBps = maxValuePerMinuteBps;
        cfg.maxSinglePayoutBps = maxSinglePayoutBps;
        cfg.minReserveBps = minReserveBps;
        cfg.drainsOnPayout = drainsOnPayout;
        cfg.initialized = true;

        emit PoolConfigUpdated(poolType);
        emit PoolInitialized(poolType);
    }

    function setPoolEnabled(PoolType poolType, bool enabled) external onlyEngine {
        poolConfig[poolType].enabled = enabled;
        emit PoolEnabled(poolType, enabled);
    }

    // -------------------------------------------------------------------------
    // INTERNAL VALIDATION (SHARED BY payout AND batchPayout)
    // -------------------------------------------------------------------------
    function _validateLimits(PoolType poolType, uint256 amount) internal {
        require(!globalPaused, "Globally paused");

        PoolConfig storage cfg = poolConfig[poolType];
        require(cfg.initialized, "Pool not initialized");
        require(cfg.enabled, "Pool disabled");
        require(cfg.wallet != address(0), "Pool wallet not set");

        uint256 poolBalance = token.balanceOf(cfg.wallet);
        require(poolBalance >= amount, "Insufficient pool balance");

        // --- per-payout BPS limit ---
        uint256 maxSingle = (poolBalance * cfg.maxSinglePayoutBps) / 10_000;
        require(amount <= maxSingle, "Exceeds single payout limit");

        // --- per-block limit ---
        PoolUsage storage usage = poolUsage[poolType];
        if (cfg.payoutLimitPerBlock > 0) {
            if (block.number != usage.lastBlock) {
                usage.lastBlock = block.number;
                usage.blockUsed = 0;
            }
            require(usage.blockUsed + amount <= cfg.payoutLimitPerBlock, "Block limit");
        }

        // --- cooldown ---
        if (cfg.cooldownSeconds > 0) {
            require(
                block.timestamp >= usage.lastPayoutTime + cfg.cooldownSeconds,
                "Cooldown active"
            );
        }

        // --- per-minute limits ---
        uint256 currentMinute = block.timestamp / 60;
        if (currentMinute != usage.lastMinute) {
            usage.lastMinute = currentMinute;
            usage.minuteUsed = 0;
        }

        if (cfg.payoutLimitPerMinute > 0) {
            require(usage.minuteUsed + amount <= cfg.payoutLimitPerMinute, "Minute limit");
        }

        if (cfg.maxValuePerMinuteBps > 0) {
            uint256 maxMinute = (poolBalance * cfg.maxValuePerMinuteBps) / 10_000;
            require(usage.minuteUsed + amount <= maxMinute, "Minute BPS limit");
        }

        // --- min reserve check (non-draining pools only) ---
        if (!cfg.drainsOnPayout && cfg.minReserveBps > 0) {
            uint256 minReserve = (poolBalance * cfg.minReserveBps) / 10_000;
            require(poolBalance - amount >= minReserve, "Below min reserve");
        }

        // --- update usage ---
        if (cfg.payoutLimitPerBlock > 0) {
            usage.blockUsed += amount;
        }
        usage.minuteUsed += amount;
        usage.lastPayoutTime = block.timestamp;
    }

    function _trackDaily(uint256 amount) internal {
        if (block.timestamp >= lastDailyReset + 1 days) {
            dailyPayoutTotal = 0;
            lastDailyReset = block.timestamp;
        }
        dailyPayoutTotal += amount;
        emit DailyPayoutUsed(amount, dailyPayoutTotal);
    }

    function _checkMaxPoolBalance(PoolType poolType) internal view {
        if (maxPoolBalance > 0) {
            uint256 balanceAfter = token.balanceOf(poolConfig[poolType].wallet);
            require(balanceAfter <= maxPoolBalance, "Pool balance exceeds max limit");
        }
    }

    // -------------------------------------------------------------------------
    // PAYOUT (ENGINE-ONLY, SINGLE ENTRY POINT)
    // -------------------------------------------------------------------------
    function payout(
        PoolType poolType,
        address to,
        uint256 amount
    ) external onlyEngine nonReentrant {
        require(amount > 0, "Zero amount");
        require(to != address(0), "Zero recipient");

        _validateLimits(poolType, amount);

        token.systemPayout(poolConfig[poolType].wallet, to, amount);

        _trackDaily(amount);
        _checkMaxPoolBalance(poolType);

        emit Payout(poolType, to, amount);
    }

    // -------------------------------------------------------------------------
    // VIEW
    // -------------------------------------------------------------------------
    function getPoolBalance(PoolType poolType) external view returns (uint256) {
        address wallet = poolConfig[poolType].wallet;
        if (wallet == address(0)) return 0;
        return token.balanceOf(wallet);
    }

    function getPoolUsage(PoolType poolType) external view returns (
        uint256 lastBlock,
        uint256 blockUsed,
        uint256 lastMinute,
        uint256 minuteUsed,
        uint256 lastPayoutTime
    ) {
        PoolUsage storage u = poolUsage[poolType];
        return (u.lastBlock, u.blockUsed, u.lastMinute, u.minuteUsed, u.lastPayoutTime);
    }

    // -------------------------------------------------------------------------
    // BATCH PAYOUT
    // -------------------------------------------------------------------------
    function batchPayout(
        PoolType poolType,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyEngine nonReentrant {
        require(recipients.length == amounts.length, "Length mismatch");
        require(recipients.length > 0, "Empty batch");
        require(recipients.length <= maxRecipientsPerTx, "Too many recipients");

        // --- calculate total ---
        uint256 total;
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Zero recipient");
            require(amounts[i] > 0, "Zero amount");
            total += amounts[i];
        }

        // --- validate all limits against total ---
        _validateLimits(poolType, total);

        // --- execute payouts ---
        address wallet = poolConfig[poolType].wallet;
        for (uint256 i = 0; i < recipients.length; i++) {
            token.systemPayout(wallet, recipients[i], amounts[i]);
            emit Payout(poolType, recipients[i], amounts[i]);
        }

        // --- post-payout tracking ---
        _trackDaily(total);
        _checkMaxPoolBalance(poolType);
    }

    // -------------------------------------------------------------------------
    // EMERGENCY WITHDRAW (RESERVE POOL ONLY)
    // -------------------------------------------------------------------------
    function emergencyWithdraw(
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(to != address(0), "Zero recipient");
        require(amount > 0, "Zero amount");

        PoolConfig storage cfg = poolConfig[PoolType.RESERVE];
        require(cfg.wallet != address(0), "Reserve wallet not set");

        uint256 reserveBalance = token.balanceOf(cfg.wallet);
        require(reserveBalance >= amount, "Insufficient reserve balance");

        token.systemPayout(cfg.wallet, to, amount);

        emit EmergencyWithdraw(to, amount, block.timestamp);
    }
}
