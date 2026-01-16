// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Btest is ERC20, ERC20Permit, Ownable {
    // -------------------------------------------------------------------------
    // RFI STORAGE
    // -------------------------------------------------------------------------
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;

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
    // TAX GUARD
    // -------------------------------------------------------------------------
    uint16 public constant MAX_TAX_BPS = 100;

    // -------------------------------------------------------------------------
    // FLAGS
    // -------------------------------------------------------------------------
    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isExcludedFromRewards;
    mapping(address => bool) public permanentlyExcluded;

    address[] private _excluded;

    // -------------------------------------------------------------------------
    // LP REGISTRY
    // -------------------------------------------------------------------------
    mapping(address => bool) public isLiquidityPool;

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------
    event TaxApplied(address indexed from, address indexed to, uint256 amount, uint256 tax, uint16 rate);
    event RewardsExcluded(address indexed account, bool excluded);
    event LiquidityPoolRegistered(address indexed lp);

    constructor(
        address initialOwner,
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

        _rOwned[initialOwner] = _rTotal;
        emit Transfer(address(0), initialOwner, _tTotal);

        _excludeFromReward(_marketing, true);
        _excludeFromReward(_dev, true);
        _excludeFromReward(_lottery, true);
        _excludeFromReward(_jackpot, true);

        permanentlyExcluded[_marketing] = true;
        permanentlyExcluded[_dev] = true;
        permanentlyExcluded[_lottery] = true;
        permanentlyExcluded[_jackpot] = true;

        isExcludedFromFee[_sink] = true;
        _excludeFromReward(_sink, true);
        permanentlyExcluded[_sink] = true;
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

        require(!isSystemWallet[from], "System wallet locked");

        bool takeFee = !(isExcludedFromFee[from] || isExcludedFromFee[to]);
        _tokenTransfer(from, to, amount, takeFee);
    }

    // -------------------------------------------------------------------------
    // TRANSFER (RATE-LOCKED)
    // -------------------------------------------------------------------------
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        uint256 rate = _getRate(); // 🔒 LOCK RATE ONCE

        uint256 taxAmount;
        uint16 taxRate;

        if (takeFee) {
            taxRate = _getTaxRate(amount);
            require(taxRate <= MAX_TAX_BPS, "Tax too high");
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
            _distributeTax(sender, recipient, amount, taxAmount, taxRate, rate);
        }
    }

    // -------------------------------------------------------------------------
    // TAX DISTRIBUTION (RATE-SAFE)
    // -------------------------------------------------------------------------
    function _distributeTax(
        address from,
        address to,
        uint256 fullAmount,
        uint256 taxAmount,
        uint16 taxRate,
        uint256 rate
    ) private {
        uint256 tReflect = (taxAmount * reflectionShare) / 100;
        _rTotal -= tReflect * rate;
        _tFeeTotal += tReflect;

        _takeFee(from, sinkWallet,      (taxAmount * sinkShare) / 100, rate);
        _takeFee(from, marketingWallet, (taxAmount * marketingShare) / 100, rate);
        _takeFee(from, devWallet,       (taxAmount * devShare) / 100, rate);
        _takeFee(from, lotteryWallet,   (taxAmount * lotteryShare) / 100, rate);
        _takeFee(from, jackpotWallet,   (taxAmount * jackpotShare) / 100, rate);

        emit TaxApplied(from, to, fullAmount, taxAmount, taxRate);
    }

    function _takeFee(address from, address to, uint256 tAmount, uint256 rate) private {
        if (tAmount == 0) return;

        uint256 rAmount = tAmount * rate;
        _rOwned[to] += rAmount;
        if (isExcludedFromRewards[to]) _tOwned[to] += tAmount;

        emit Transfer(from, to, tAmount);
    }

    // -------------------------------------------------------------------------
    // RFI CORE
    // -------------------------------------------------------------------------
    function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
        require(rAmount <= _rTotal, "Invalid rAmount");
        return rAmount / _getRate();
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;

        for (uint256 i = 0; i < _excluded.length; i++) {
            rSupply -= _rOwned[_excluded[i]];
            tSupply -= _tOwned[_excluded[i]];
        }

        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _getValues(uint256 tAmount, uint256 tFee, uint256 rate)
        private
        pure
        returns (uint256 rAmount, uint256 rTransfer, uint256 tTransfer)
    {
        rAmount = tAmount * rate;
        uint256 rFee = tFee * rate;
        rTransfer = rAmount - rFee;
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

    // -------------------------------------------------------------------------
    // VIEW
    // -------------------------------------------------------------------------
    function circulatingSupply() external view returns (uint256) {
        return _tTotal - _tOwned[sinkWallet];
    }
}
