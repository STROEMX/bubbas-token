// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Btest is ERC20, ERC20Permit, Ownable {

    // -------------------------------------------------------------------------
    // SYSTEM WALLETS (LOCKED)
    // -------------------------------------------------------------------------
    address public constant ENGINE_WALLET    = 0x48Fe53Ce093950B6c0510186CA3e2BF20F659226;
    address public constant MARKETING_WALLET = 0xe114aa7982763E8471789EE273316b4609fAb9f8;
    address public constant DEV_WALLET       = 0xE4d409A5850A914686240165398E0C051A53347F;
    address public constant LOTTERY_WALLET   = 0x990DC6B4331f1158Acef1408BEe8a521Bde69Cae;
    address public constant JACKPOT_WALLET   = 0x5E621aDBF14dDF216770535aa980d22a202FBcBE;
    address public constant SINK_WALLET      = 0xF5F140fC4B10abe1a58598Ee3544e181107DA638;

    // -------------------------------------------------------------------------
    // ENGINE (2-STEP ROTATION)
    // -------------------------------------------------------------------------
    address public engine;
    address public pendingEngine;

    modifier onlyEngine() {
        require(msg.sender == engine, "Not engine");
        _;
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
    // SYSTEM ALIAS (FUTURE-PROOF ONLY)
    // -------------------------------------------------------------------------
    mapping(bytes32 => address) public systemAlias;

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------
    event TaxApplied(address indexed from, uint256 amount, uint16 bps);
    event EngineUpdated(address indexed oldEngine, address indexed newEngine);
    event EngineProposed(address indexed oldEngine, address indexed newEngine);

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------
    constructor(address initialOwner)
        ERC20("BtestV3", "BTESTV3")
        ERC20Permit("BtestV3")
        Ownable(initialOwner)
    {
        engine = ENGINE_WALLET;

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
        }

        // Alias init (NOT used in logic)
        systemAlias["MARKETING"] = MARKETING_WALLET;
        systemAlias["DEV"]       = DEV_WALLET;
        systemAlias["LOTTERY"]   = LOTTERY_WALLET;
        systemAlias["JACKPOT"]   = JACKPOT_WALLET;
        systemAlias["SINK"]      = SINK_WALLET;

        _rOwned[initialOwner] = _rTotal;
        emit Transfer(address(0), initialOwner, _tTotal);
    }

    // -------------------------------------------------------------------------
    // ERC20 OVERRIDES
    // -------------------------------------------------------------------------
    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (isExcludedFromRewards[account]) return _tOwned[account];
        return _rOwned[account] / _getRate();
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0)) return;
        require(to != address(0), "Burn disabled");
        require(from != SINK_WALLET, "Sink locked");
        require(!isSystemWallet[from], "System locked");

        bool takeFee =
            feesEnabled &&
            !(isExcludedFromFee[from] || isExcludedFromFee[to]);

        _tokenTransfer(from, to, amount, takeFee);
    }

    // -------------------------------------------------------------------------
    // ENGINE PAYOUT (EXPLICIT ONLY)
    // -------------------------------------------------------------------------
    function systemPayout(address from, address to, uint256 amount)
        external
        onlyEngine
    {
        require(isSystemWallet[from], "Not system");
        require(!isSystemWallet[to], "No system-to-system");

        uint256 rate = _getRate();
        uint256 rAmt = amount * rate;

        _rOwned[from] -= rAmt;
        if (isExcludedFromRewards[from]) _tOwned[from] -= amount;

        _rOwned[to] += rAmt;
        if (isExcludedFromRewards[to]) _tOwned[to] += amount;

        emit Transfer(from, to, amount);
    }

    // -------------------------------------------------------------------------
    // ENGINE ROTATION (SAFE)
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

    // -------------------------------------------------------------------------
    // FEE TOGGLE (SOFT EMERGENCY)
    // -------------------------------------------------------------------------
    function setFeesEnabled(bool enabled) external onlyOwner {
        feesEnabled = enabled;
    }

    // -------------------------------------------------------------------------
    // LP EXCLUSION (LEGACY)
    // -------------------------------------------------------------------------
    function excludeLPFromRewards(address lp) external onlyOwner {
        require(lp != address(0), "Zero address");
        require(!isLP[lp], "Already LP");

        isLP[lp] = true;
        isExcludedFromRewards[lp] = true;
        isExcludedFromFee[lp] = true;

        _tOwned[lp] = _rOwned[lp] / _getRate();
        _rOwned[lp] = 0;

        _excluded.push(lp);
        emit Transfer(lp, lp, 0);
    }

    // -------------------------------------------------------------------------
    // LP EXCLUSION (TAGGED, FUTURE)
    // -------------------------------------------------------------------------
    function excludeLPFromRewardsWithTag(address lp, bytes32 /* tag */)
        external
        onlyOwner
    {
        require(lp != address(0), "Zero address");
        require(!isLP[lp], "Already LP");

        isLP[lp] = true;
        isExcludedFromRewards[lp] = true;
        isExcludedFromFee[lp] = true;

        _tOwned[lp] = _rOwned[lp] / _getRate();
        _rOwned[lp] = 0;

        _excluded.push(lp);
        emit Transfer(lp, lp, 0);
    }

    // -------------------------------------------------------------------------
    // TRANSFER CORE (UNCHANGED)
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

        _rOwned[from] -= rAmount;
        _rOwned[to]   += rTransfer;

        if (isExcludedFromRewards[from]) _tOwned[from] -= tAmount;
        if (isExcludedFromRewards[to])   _tOwned[to]   += tTransfer;

        if (tTax > 0) {
            uint256 tReflect = (tTax * reflectionShare) / 100;
            _rTotal -= tReflect * rate;
            _tFeeTotal += tReflect;

            _takeSystemFee(from, SINK_WALLET,      (tTax * sinkShare) / 100);
            _takeSystemFee(from, MARKETING_WALLET, (tTax * marketingShare) / 100);
            _takeSystemFee(from, DEV_WALLET,       (tTax * devShare) / 100);
            _takeSystemFee(from, LOTTERY_WALLET,   (tTax * lotteryShare) / 100);
            _takeSystemFee(from, JACKPOT_WALLET,   (tTax * jackpotShare) / 100);

            emit TaxApplied(from, tTax, bps);
        }

        emit Transfer(from, to, tTransfer);
    }

    // -------------------------------------------------------------------------
    // SYSTEM FEE (UNCHANGED)
    // -------------------------------------------------------------------------
    function _takeSystemFee(address from, address to, uint256 tAmount) private {
        if (tAmount == 0) return;

        uint256 rate = _getRate();
        uint256 rAmount = tAmount * rate;

        _rOwned[from] -= rAmount;
        if (isExcludedFromRewards[from]) _tOwned[from] -= tAmount;

        _rOwned[to] += rAmount;
        if (isExcludedFromRewards[to]) _tOwned[to] += tAmount;

        emit Transfer(from, to, tAmount);
    }

    // -------------------------------------------------------------------------
    // RATE (STABLE)
    // -------------------------------------------------------------------------
    function _getRate() private view returns (uint256) {
        return _rTotal / _tTotal;
    }

    // -------------------------------------------------------------------------
    // LINEAR TAX CURVE (UNCHANGED)
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
