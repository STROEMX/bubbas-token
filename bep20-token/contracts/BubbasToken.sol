// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/*
    -------------------------------------------------------------------------
    GAMEFI DESIGN NOTE

    This is a GameFi settlement token.

    - Game logic and payouts happen off-chain.
    - On-chain logic only enforces fees, sinks, and settlement constraints.
    - This token is NOT a DeFi yield or pure RFI instrument.
    - Reflections are a mechanical fee-distribution effect, not a
      financial return guarantee.

    NOTE:
    Cold / reserve wallets are excluded from fees and reflections by design.
    Cold wallets receive tokens post-deploy but are excluded from reflections.
    All balances are transferred post-deploy only.

    -------------------------------------------------------------------------

    🔧 RFI ACCOUNTING NOTE (BUGFIX CONTEXT)

    _tOwned was not reliably materialized on first receipt, because the logic
    did not guarantee initialization for excluded wallets across all transfer paths.

    -------------------------------------------------------------------------
*/

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BUBBAS is ERC20, ERC20Permit, Ownable {

    // -------------------------------------------------------------------------
    // SYSTEM WALLETS (LOCKED)
    // -------------------------------------------------------------------------
    address public constant ENGINE_WALLET    = 0x48Fe53Ce093950B6c0510186CA3e2BF20F659226;
    address public constant MARKETING_WALLET = 0xe114aa7982763E8471789EE273316b4609fAb9f8;
    address public constant DEV_WALLET       = 0xE4d409A5850A914686240165398E0C051A53347F;
    address public constant LOTTERY_WALLET   = 0x990DC6B4331f1158Acef1408BEe8a521Bde69Cae;
    address public constant JACKPOT_WALLET   = 0x5E621aDBF14dDF216770535aa980d22a202FBcBE;
    address public constant SINK_WALLET      = 0xF5F140fC4B10abe1a58598Ee3544e181107DA638;

    // OPS / BACKEND / FEE PAYER (HOT WALLET)
    address public opsWallet;
    address public pendingOpsWallet;

    // -------------------------------------------------------------------------
    // COLD / RESERVE WALLETS (NEVER PARTICIPATE)
    // -------------------------------------------------------------------------
    address public constant RESERVE_LIQUIDITY    = 0x381203eB865BBdbe1776c65Cc915DC97CcD01Aa0;
    address public constant RESERVE_VESTING      = 0xaB3D656D2cd46310E082E7ce36A0CD23Ce470486;
    address public constant RESERVE_MINING       = 0x582738f6f6e7E882fffCb53eDA7f0491F44db449;
    address public constant RESERVE_MARKETING    = 0x5eFE8f36Cd4E4dbBa7f2585170BB0603608Fe595;
    address public constant RESERVE_DEVELOPMENT  = 0x2CfE7065289C2543663ffcd62AaCf566E5D0100d;
    address public constant RESERVE_BONUS        = 0xfC6da39a46f2E45cb63528e46e5eb4Bd4405f031;
    address public constant RESERVE_DAO          = 0x9F5196b3d771a86A83F7A27230DB22DA914a742a;

    // -------------------------------------------------------------------------
    // ENGINE (2-STEP ROTATION)
    // -------------------------------------------------------------------------
    address public engine;
    address public pendingEngine;

    uint256 public maxPayoutPerTx = 1_000_000 * 1e18;
    uint256 public dailyPayoutLimit;
    uint256 public dailyPayoutUsed;
    uint256 public lastPayoutDay;
    bool public enginePaused;

    modifier onlyEngine() {
        require(msg.sender == engine, "Not engine");
        _;
    }

    modifier engineActive() {
        require(!enginePaused, "Engine paused");
        _;
    }

    modifier payoutsActive() {
        require(!payoutsPaused, "Payouts paused");
        _;
    }

    // -------------------------------------------------------------------------
    // ERC20 OVERRIDES (RFI COMPATIBILITY)
    // -------------------------------------------------------------------------
    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (isExcludedFromRewards[account]) return _tOwned[account];
        return _rOwned[account] / _getRate();
    }

    // -------------------------------------------------------------------------
    // RFI STORAGE
    // -------------------------------------------------------------------------
    uint256 private constant MAX = type(uint256).max;
    uint256 private constant _tTotal = 1_000_000_000 * 1e18;
    uint256 private _rTotal = MAX - (MAX % _tTotal);
    uint256 private _tFeeTotal;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;

    address[] private _excluded;

    // -------------------------------------------------------------------------
    // FLAGS
    // -------------------------------------------------------------------------
    mapping(address => bool) public isSystemWallet;
    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isExcludedFromRewards;
    mapping(address => bool) public isLP;

    bool public feesEnabled = true;
    bool public emergencyMode;
    bool public payoutsPaused;

    // -------------------------------------------------------------------------
    // TAX SPLIT (SUM = 100)
    // -------------------------------------------------------------------------
    uint16 public constant reflectionShare = 20;
    uint16 public constant sinkShare       = 30;
    uint16 public constant marketingShare  = 10;
    uint16 public constant devShare        = 10;
    uint16 public constant lotteryShare    = 18;
    uint16 public constant jackpotShare    = 12;

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------
    event TaxApplied(address indexed from, uint256 amount, uint16 bps);
    event EngineUpdated(address indexed oldEngine, address indexed newEngine);
    event EngineProposed(address indexed oldEngine, address indexed newEngine);
    event OpsWalletProposed(address indexed oldWallet, address indexed newWallet);
    event OpsWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event EmergencyModeSet(bool enabled);
    event EnginePaused(bool paused);
    event MaxPayoutUpdated(uint256 amount);
    event FeesEnabledSet(bool enabled);
    event DailyPayoutLimitUpdated(uint256 amount);
    event PayoutsPaused(bool paused);
    event LPSet(address indexed lp);
    event LPUnset(address indexed lp);

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------
    constructor(address initialOwner, address _opsWallet)
        ERC20("BUBBAS", "BUBBAS")
        ERC20Permit("BUBBAS")
        Ownable(initialOwner)
    {
        engine = ENGINE_WALLET;

        require(_opsWallet != address(0), "OPS wallet cannot be zero");
        opsWallet = _opsWallet;

        _rOwned[initialOwner] = _rTotal;
        emit Transfer(address(0), initialOwner, _tTotal);

        address[6] memory sys = [
            ENGINE_WALLET,
            MARKETING_WALLET,
            DEV_WALLET,
            LOTTERY_WALLET,
            JACKPOT_WALLET,
            SINK_WALLET
        ];

        for (uint256 i; i < sys.length; i++) {
            isSystemWallet[sys[i]] = true;
            isExcludedFromFee[sys[i]] = true;
            isExcludedFromRewards[sys[i]] = true;
            _excluded.push(sys[i]);

            if (sys[i] == initialOwner) {
                _tOwned[sys[i]] = _tTotal;
            }
        }

        address[7] memory cold = [
            RESERVE_LIQUIDITY,
            RESERVE_VESTING,
            RESERVE_MINING,
            RESERVE_MARKETING,
            RESERVE_DEVELOPMENT,
            RESERVE_BONUS,
            RESERVE_DAO
        ];

        for (uint256 i; i < cold.length; i++) {
            isExcludedFromFee[cold[i]] = true;
            isExcludedFromRewards[cold[i]] = true;
            _excluded.push(cold[i]);
        }

        isExcludedFromFee[opsWallet] = true;
        isExcludedFromRewards[opsWallet] = true;
        _excluded.push(opsWallet);

        if (isExcludedFromRewards[initialOwner]) {
            require(_tOwned[initialOwner] == _tTotal, "Excluded owner must have tOwned initialized");
        }

        require(
            reflectionShare +
            sinkShare +
            marketingShare +
            devShare +
            lotteryShare +
            jackpotShare == 100,
            "Invalid tax split"
        );
    }

    // -------------------------------------------------------------------------
    // ENGINE ROTATION
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

    function setMaxPayoutPerTx(uint256 amount) external onlyOwner {
        maxPayoutPerTx = amount;
        emit MaxPayoutUpdated(amount);
    }

    function setEnginePaused(bool paused) external onlyOwner {
        enginePaused = paused;
        emit EnginePaused(paused);
    }

    function setFeesEnabled(bool enabled) external onlyOwner {
        feesEnabled = enabled;
        emit FeesEnabledSet(enabled);
    }

    function setEmergencyMode(bool enabled) external onlyOwner {
        emergencyMode = enabled;
        emit EmergencyModeSet(enabled);
    }

    function setDailyPayoutLimit(uint256 amount) external onlyOwner {
        dailyPayoutLimit = amount;
        emit DailyPayoutLimitUpdated(amount);
    }

    function setPayoutsPaused(bool paused) external onlyOwner {
        payoutsPaused = paused;
        emit PayoutsPaused(paused);
    }

    // -------------------------------------------------------------------------
    // OPS WALLET ROTATION (2-STEP)
    // -------------------------------------------------------------------------
    function proposeOpsWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Zero address");
        require(newWallet != opsWallet, "Already ops wallet");
        pendingOpsWallet = newWallet;
        emit OpsWalletProposed(opsWallet, newWallet);
    }

    function acceptOpsWallet() external {
        require(msg.sender == pendingOpsWallet, "Not pending wallet");

        address oldWallet = opsWallet;
        address newWallet = pendingOpsWallet;

        uint256 rate = _getRate();

        // remove old exclusions
        isExcludedFromFee[oldWallet] = false;
        isExcludedFromRewards[oldWallet] = false;

        // remove old wallet from _excluded array
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == oldWallet) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _excluded.pop();
                break;
            }
        }

        // set new wallet
        opsWallet = newWallet;
        pendingOpsWallet = address(0);

        // apply exclusions
        isExcludedFromFee[newWallet] = true;
        isExcludedFromRewards[newWallet] = true;

        // initialize tOwned if excluded
        if (_rOwned[newWallet] > 0) {
            _tOwned[newWallet] = _rOwned[newWallet] / rate;
        }

        emit OpsWalletUpdated(oldWallet, newWallet);
    }

    // -------------------------------------------------------------------------
    // LP MANAGEMENT (POST-DEPLOY, ONE-WAY)
    // -------------------------------------------------------------------------
    function setLP(address lp) external onlyOwner {
        require(lp != address(0), "Zero address");

        isLP[lp] = true;
        isExcludedFromFee[lp] = true;

        if (!isExcludedFromRewards[lp]) {
            isExcludedFromRewards[lp] = true;
            _excluded.push(lp);

            uint256 rBal = _rOwned[lp];
            if (rBal > 0) {
                _tOwned[lp] = rBal / _getRate();
            }
        }

        emit LPSet(lp);
    }

    function unsetLP(address lp) external onlyOwner {
        require(isLP[lp], "Not LP");

        isLP[lp] = false;

        if (isExcludedFromRewards[lp]) {
            isExcludedFromRewards[lp] = false;

            for (uint256 i = 0; i < _excluded.length; i++) {
                if (_excluded[i] == lp) {
                    _excluded[i] = _excluded[_excluded.length - 1];
                    _excluded.pop();
                    break;
                }
            }
        }

        if (isExcludedFromFee[lp]) {
            isExcludedFromFee[lp] = false;
        }

        emit LPUnset(lp);
    }

    // -------------------------------------------------------------------------
    // TRANSFER CORE
    // -------------------------------------------------------------------------
    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0)) return;
        require(to != address(0), "Burn disabled");
        require(from != SINK_WALLET, "Sink locked");
        if (emergencyMode) {
            require(
                isSystemWallet[from] || from == engine,
                "Transfers paused"
            );
        }
        require(
            !isSystemWallet[from] || from == engine,
            "System locked"
        );

        bool takeFee =
            feesEnabled &&
            !(isExcludedFromFee[from] || isExcludedFromFee[to]);

        _tokenTransfer(from, to, amount, takeFee);
    }

    // -------------------------------------------------------------------------
    // ENGINE PAYOUT (FIXED)
    // -------------------------------------------------------------------------
    function systemPayout(address from, address to, uint256 amount)
        external
        onlyEngine
        engineActive
        payoutsActive
    {
        require(amount <= maxPayoutPerTx, "Payout too large");
        require(isSystemWallet[from], "Not system");
        require(!isSystemWallet[to], "No system-to-system");

        // daily payout cap
        uint256 today = block.timestamp / 1 days;
        if (today != lastPayoutDay) {
            lastPayoutDay = today;
            dailyPayoutUsed = 0;
        }
        if (dailyPayoutLimit > 0) {
            require(dailyPayoutUsed + amount <= dailyPayoutLimit, "Daily payout limit");
        }
        dailyPayoutUsed += amount;

        uint256 rate = _getRate();
        uint256 rAmt = amount * rate;

        // ✅ FIX: synchronize _rOwned before mutation
        if (isExcludedFromRewards[from]) {
            _rOwned[from] = _tOwned[from] * rate;
        }

        if (isExcludedFromRewards[to]) {
            _rOwned[to] = _tOwned[to] * rate;
        }

        _rOwned[from] -= rAmt;
        if (isExcludedFromRewards[from]) _tOwned[from] -= amount;

        _rOwned[to] += rAmt;
        if (isExcludedFromRewards[to]) _tOwned[to] += amount;

        emit Transfer(from, to, amount);
    }

    // -------------------------------------------------------------------------
    // TRANSFER CORE LOGIC
    // -------------------------------------------------------------------------
    function _tokenTransfer(
        address from,
        address to,
        uint256 tAmount,
        bool takeFee
    ) private {
        uint16 bps = takeFee ? _getTaxRate(tAmount) : 0;
        uint256 tTax = (tAmount * bps) / 10_000;
        uint256 tTransfer = tAmount - tTax;

        uint256 rate = _getRate();
        uint256 rAmount = tAmount * rate;
        uint256 rTransfer = tTransfer * rate;

        if (isExcludedFromRewards[from]) {
            require(_tOwned[from] >= tAmount, "Not enough balance");
        }

        _rOwned[from] -= rAmount;
        _rOwned[to]   += rTransfer;

        // ✅ FIX: materialize tOwned for excluded wallets
        if (isExcludedFromRewards[from]) {
            _tOwned[from] -= tAmount;
        }

        if (isExcludedFromRewards[to]) {
            _tOwned[to] += tTransfer;
        }

        // ✅ FIX: synchronize _rOwned after _tOwned update
        if (isExcludedFromRewards[from]) {
            _rOwned[from] = _tOwned[from] * rate;
        }

        if (isExcludedFromRewards[to]) {
            _rOwned[to] = _tOwned[to] * rate;
        }

        if (tTax > 0) {
            uint256 tReflect = (tTax * reflectionShare) / 100;
            _rTotal -= tReflect * rate;
            _tFeeTotal += tReflect;

            _takeSystemFee(from, SINK_WALLET,      (tTax * sinkShare) / 100, rate);
            _takeSystemFee(from, MARKETING_WALLET, (tTax * marketingShare) / 100, rate);
            _takeSystemFee(from, DEV_WALLET,       (tTax * devShare) / 100, rate);
            _takeSystemFee(from, LOTTERY_WALLET,   (tTax * lotteryShare) / 100, rate);
            _takeSystemFee(from, JACKPOT_WALLET,   (tTax * jackpotShare) / 100, rate);

            emit TaxApplied(from, tTax, bps);
        }

        emit Transfer(from, to, tTransfer);
    }

    // -------------------------------------------------------------------------
    // SYSTEM FEE
    // -------------------------------------------------------------------------
    function _takeSystemFee(address from, address to, uint256 tAmount, uint256 rate) private {
        if (tAmount == 0) return;

        uint256 rAmount = tAmount * rate;

        _rOwned[to] += rAmount;
        if (isExcludedFromRewards[to]) _tOwned[to] += tAmount;

        emit Transfer(from, to, tAmount);
    }

    // -------------------------------------------------------------------------
    // RATE
    // -------------------------------------------------------------------------
    function _getCurrentSupply() private view returns (uint256 rSupply, uint256 tSupply) {
        rSupply = _rTotal;
        tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) {
                return (_rTotal, _tTotal);
            }
            rSupply -= _rOwned[_excluded[i]];
            tSupply -= _tOwned[_excluded[i]];
        }
        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    // -------------------------------------------------------------------------
    // LINEAR TAX CURVE
    // -------------------------------------------------------------------------
    function _getTaxRate(uint256 amount) internal pure returns (uint16) {
        uint256 maxAmount = 1_000_000 * 1e18;
        uint256 minBps = 10;
        uint256 maxBps = 100;

        if (amount >= maxAmount) return uint16(minBps);

        uint256 bps =
            maxBps -
            ((amount * (maxBps - minBps)) / maxAmount);

        return uint16(bps < minBps ? minBps : bps);
    }
}
