// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Btest is ERC20, ERC20Permit, Ownable {
    // -------------------------------------------------------------------------
    // ENGINE
    // -------------------------------------------------------------------------
    address public immutable engine;

    modifier onlyEngine() {
        require(msg.sender == engine, "Not engine");
        _;
    }

    // -------------------------------------------------------------------------
    // RFI STORAGE
    // -------------------------------------------------------------------------
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;

    address[] private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _tTotal = 1_000_000_000 * 1e18;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;

    // -------------------------------------------------------------------------
    // SYSTEM WALLETS
    // -------------------------------------------------------------------------
    address public immutable marketingWallet;
    address public immutable devWallet;
    address public immutable lotteryWallet;
    address public immutable jackpotWallet;
    address public immutable sinkWallet;

    mapping(address => bool) public isSystemWallet;

    // -------------------------------------------------------------------------
    // SPLITS (SUM = 100)
    // -------------------------------------------------------------------------
    uint16 public immutable reflectionShare;
    uint16 public immutable sinkShare;
    uint16 public immutable marketingShare;
    uint16 public immutable devShare;
    uint16 public immutable lotteryShare;
    uint16 public immutable jackpotShare;

    // -------------------------------------------------------------------------
    // FLAGS
    // -------------------------------------------------------------------------
    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isExcludedFromRewards;

    // -------------------------------------------------------------------------
    // LP EXCLUSION FLAG
    // -------------------------------------------------------------------------
    bool public lpExcluded;

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------
    event TaxApplied(address indexed from, uint256 taxAmount, uint16 rate);

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------
    constructor(
        address initialOwner,
        address _engine,
        address _marketing,
        address _dev,
        address _lottery,
        address _jackpot,
        address _sink
    )
        ERC20("Btest", "BTEST")
        ERC20Permit("Btest")
        Ownable(initialOwner)
    {
        require(_engine != address(0), "Zero engine");
        engine = _engine;

        reflectionShare = 20;
        sinkShare = 30;
        marketingShare = 10;
        devShare = 10;
        lotteryShare = 18;
        jackpotShare = 12;

        require(
            reflectionShare +
            sinkShare +
            marketingShare +
            devShare +
            lotteryShare +
            jackpotShare == 100,
            "Invalid splits"
        );

        marketingWallet = _marketing;
        devWallet = _dev;
        lotteryWallet = _lottery;
        jackpotWallet = _jackpot;
        sinkWallet = _sink;

        isSystemWallet[_marketing] = true;
        isSystemWallet[_dev] = true;
        isSystemWallet[_lottery] = true;
        isSystemWallet[_jackpot] = true;
        isSystemWallet[_sink] = true;

        // Exclude ALL system wallets from reflections
        isExcludedFromRewards[marketingWallet] = true;
        isExcludedFromRewards[devWallet] = true;
        isExcludedFromRewards[lotteryWallet] = true;
        isExcludedFromRewards[jackpotWallet] = true;
        isExcludedFromRewards[sinkWallet] = true;

        _excluded.push(marketingWallet);
        _excluded.push(devWallet);
        _excluded.push(lotteryWallet);
        _excluded.push(jackpotWallet);
        _excluded.push(sinkWallet);

        // RFI-authoritative mint
        _mint(initialOwner, _tTotal);
        _rOwned[initialOwner] = _rTotal;
    }

    // -------------------------------------------------------------------------
    // ERC20 OVERRIDES
    // -------------------------------------------------------------------------
    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (isExcludedFromRewards[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, amount);
            return;
        }

        require(from != sinkWallet, "Sink is locked");
        require(!isSystemWallet[from], "System wallet locked");

        bool takeFee = !(isExcludedFromFee[from] || isExcludedFromFee[to]);
        _tokenTransfer(from, to, amount, takeFee);
    }

    // -------------------------------------------------------------------------
    // SYSTEM PAYOUT (TAX-FREE)
    // -------------------------------------------------------------------------
    function systemPayout(address from, address to, uint256 amount)
        external
        onlyEngine
    {
        require(isSystemWallet[from], "Not system wallet");
        require(from != sinkWallet, "Sink cannot pay");
        require(!isSystemWallet[to], "No system-to-system");

        uint256 rate = _getRate();
        uint256 rAmount = amount * rate;

        _rOwned[from] -= rAmount;
        if (isExcludedFromRewards[from]) _tOwned[from] -= amount;

        _rOwned[to] += rAmount;
        if (isExcludedFromRewards[to]) _tOwned[to] += amount;

        emit Transfer(from, to, amount);
    }

    // -------------------------------------------------------------------------
    // LP EXCLUSION (EXACT FUNCTION AS REQUESTED)
    // -------------------------------------------------------------------------
    function excludeLPFromRewards(address lp)
        external
        onlyOwner
    {
        require(!lpExcluded, "LP already excluded");
        require(lp != address(0), "Zero address");

        isExcludedFromRewards[lp] = true;
        _excluded.push(lp);

        // convert reflected balance to token balance
        _tOwned[lp] = tokenFromReflection(_rOwned[lp]);

        lpExcluded = true;
    }

    // -------------------------------------------------------------------------
    // TRANSFER CORE
    // -------------------------------------------------------------------------
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        uint256 rate = _getRate();

        uint256 taxAmount;
        uint16 taxRate;

        if (takeFee) {
            taxRate = _getTaxRate(amount);
            taxAmount = (amount * taxRate) / 10_000;
        }

        (uint256 rAmount, uint256 rTransfer, uint256 tTransfer) =
            _getValues(amount, taxAmount, rate);

        _rOwned[sender] -= rAmount;
        if (isExcludedFromRewards[sender]) _tOwned[sender] -= amount;

        _rOwned[recipient] += rTransfer;
        if (isExcludedFromRewards[recipient]) _tOwned[recipient] += tTransfer;

        emit Transfer(sender, recipient, tTransfer);

        if (taxAmount > 0) {
            _distributeTax(sender, taxAmount, rate, taxRate);
        }
    }

    // -------------------------------------------------------------------------
    // TAX ROUTING
    // -------------------------------------------------------------------------
    function _takeFee(address from, address to, uint256 tAmount, uint256 rate)
        private
    {
        if (tAmount == 0) return;

        uint256 rAmount = tAmount * rate;
        _rOwned[to] += rAmount;
        if (isExcludedFromRewards[to]) _tOwned[to] += tAmount;

        emit Transfer(from, to, tAmount);
    }

    function _distributeTax(
        address from,
        uint256 taxAmount,
        uint256 rate,
        uint16 taxRate
    ) private {
        uint256 tReflect = (taxAmount * reflectionShare) / 100;
        _rTotal -= tReflect * rate;
        _tFeeTotal += tReflect;

        _takeFee(from, sinkWallet,      (taxAmount * sinkShare) / 100, rate);
        _takeFee(from, marketingWallet, (taxAmount * marketingShare) / 100, rate);
        _takeFee(from, devWallet,       (taxAmount * devShare) / 100, rate);
        _takeFee(from, lotteryWallet,   (taxAmount * lotteryShare) / 100, rate);
        _takeFee(from, jackpotWallet,   (taxAmount * jackpotShare) / 100, rate);

        emit TaxApplied(from, taxAmount, taxRate);
    }

    // -------------------------------------------------------------------------
    // RFI CORE
    // -------------------------------------------------------------------------
    function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
        return rAmount / _getRate();
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply()
        private
        view
        returns (uint256 rSupply, uint256 tSupply)
    {
        rSupply = _rTotal;
        tSupply = _tTotal;

        for (uint256 i = 0; i < _excluded.length; i++) {
            address acc = _excluded[i];
            rSupply -= _rOwned[acc];
            tSupply -= _tOwned[acc];
        }

        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _getValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 rate
    )
        private
        pure
        returns (uint256 rAmount, uint256 rTransfer, uint256 tTransfer)
    {
        rAmount = tAmount * rate;
        rTransfer = rAmount - (tFee * rate);
        tTransfer = tAmount - tFee;
    }

    // -------------------------------------------------------------------------
    // TAX CURVE
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
