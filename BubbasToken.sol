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
    // WALLETS
    // -------------------------------------------------------------------------
    address public marketingWallet;
    address public devWallet;
    address public lotteryWallet;
    address public jackpotWallet;
    address public sinkWallet;

    // -------------------------------------------------------------------------
    // SPLITS (IMMUTABLE — SUM = 100)
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
    uint16 public constant MAX_TAX_BPS = 100; // 1.00%

    // -------------------------------------------------------------------------
    // FLAGS
    // -------------------------------------------------------------------------
    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isExcludedFromRewards;
    address[] private _excluded;

    // -------------------------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------------------------
    event TaxApplied(address indexed from, address indexed to, uint256 amount, uint256 taxAmount, uint16 taxRateBps);
    event PayTaxUpdated(address indexed account, bool payTax);
    event RewardsExcluded(address indexed account, bool excluded);

    constructor(address initialOwner)
        ERC20("Btest", "BTEST")
        ERC20Permit("Btest")
        Ownable(initialOwner)
    {
        reflectionShare = 20;
        sinkShare       = 30;
        marketingShare  = 10;
        devShare        = 10;
        lotteryShare    = 18;
        jackpotShare    = 12;

        require(
            reflectionShare +
            sinkShare +
            marketingShare +
            devShare +
            lotteryShare +
            jackpotShare == 100,
            "Tax shares must sum to 100"
        );

        _rOwned[initialOwner] = _rTotal;
        emit Transfer(address(0), initialOwner, _tTotal);

        // ---------------------------------------------------------------------
        // WALLET ASSIGNMENTS
        // ---------------------------------------------------------------------
        marketingWallet = 0xe114aa7982763E8471789EE273316b4609fAb9f8;
        devWallet       = 0xE4d409A5850A914686240165398E0C051A53347F;
        lotteryWallet   = 0x990DC6B4331f1158Acef1408BEe8a521Bde69Cae;
        jackpotWallet   = 0x5E621aDBF14dDF216770535aa980d22a202FBcBE;
        sinkWallet      = 0xF5F140fC4B10abe1a58598Ee3544e181107DA638;

        // ---------------------------------------------------------------------
        // SYSTEM WALLET CONFIGURATION (FINAL FIX)
        // ---------------------------------------------------------------------

        // Exclude system wallets from reflections (they still pay tax)
        _excludeFromReward(marketingWallet, true);
        _excludeFromReward(devWallet, true);
        _excludeFromReward(lotteryWallet, true);
        _excludeFromReward(jackpotWallet, true);

        // Sink wallet: no tax, no reflections
        isExcludedFromFee[sinkWallet] = true;
        _excludeFromReward(sinkWallet, true);
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

        bool takeFee = !(isExcludedFromFee[from] || isExcludedFromFee[to]);
        _tokenTransfer(from, to, amount, takeFee);
    }

    // -------------------------------------------------------------------------
    // TRANSFER LOGIC
    // -------------------------------------------------------------------------
    function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
        uint256 taxAmount;
        uint16 taxRate;

        if (takeFee) {
            (taxRate, taxAmount,,,,,,) = previewTax(amount);
            require(taxRate <= MAX_TAX_BPS, "Tax too high");
        }

        (uint256 rAmount, uint256 rTransferAmount,, uint256 tTransferAmount) =
            _getValues(amount, taxAmount);

        _rOwned[sender] -= rAmount;
        if (isExcludedFromRewards[sender]) _tOwned[sender] -= amount;

        _rOwned[recipient] += rTransferAmount;
        if (isExcludedFromRewards[recipient]) _tOwned[recipient] += tTransferAmount;

        emit Transfer(sender, recipient, tTransferAmount);

        if (taxAmount > 0) {
            _distributeTax(sender, recipient, amount, taxAmount, taxRate);
        }
    }

    // -------------------------------------------------------------------------
    // TAX DISTRIBUTION
    // -------------------------------------------------------------------------
    function _distributeTax(address from, address to, uint256 fullAmount, uint256 taxAmount, uint16 taxRate) private {
        uint256 tReflect  = (taxAmount * reflectionShare) / 100;
        uint256 tSink     = (taxAmount * sinkShare) / 100;
        uint256 tMarket   = (taxAmount * marketingShare) / 100;
        uint256 tDev      = (taxAmount * devShare) / 100;
        uint256 tLottery  = (taxAmount * lotteryShare) / 100;
        uint256 tJackpot  = (taxAmount * jackpotShare) / 100;

        uint256 totalSplit = tReflect + tSink + tMarket + tDev + tLottery + tJackpot;
        if (totalSplit < taxAmount) {
            tMarket += (taxAmount - totalSplit);
        }

        uint256 rate = _getRate();

        _rTotal -= (tReflect * rate);
        _tFeeTotal += tReflect;

        _takeFee(from, sinkWallet,      tSink,    rate);
        _takeFee(from, marketingWallet, tMarket,  rate);
        _takeFee(from, devWallet,       tDev,     rate);
        _takeFee(from, lotteryWallet,   tLottery, rate);
        _takeFee(from, jackpotWallet,   tJackpot, rate);

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
    // TAX CALCULATION
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

    function previewTax(uint256 amount) public view returns (
        uint16 rateBps,
        uint256 totalTax,
        uint256 reflectPart,
        uint256 sinkPart,
        uint256 marketPart,
        uint256 devPart,
        uint256 lotteryPart,
        uint256 jackpotPart
    ) {
        rateBps  = _getTaxRate(amount);
        totalTax = (amount * rateBps) / 10_000;

        reflectPart  = (totalTax * reflectionShare) / 100;
        sinkPart     = (totalTax * sinkShare) / 100;
        marketPart   = (totalTax * marketingShare) / 100;
        devPart      = (totalTax * devShare) / 100;
        lotteryPart  = (totalTax * lotteryShare) / 100;
        jackpotPart  = (totalTax * jackpotShare) / 100;
    }

    // -------------------------------------------------------------------------
    // OWNER CONTROLS
    // -------------------------------------------------------------------------
    function setWalletFlags(address account, bool payTax, bool earnRewards) external onlyOwner {
        isExcludedFromFee[account] = !payTax;
        emit PayTaxUpdated(account, payTax);
        _excludeFromReward(account, !earnRewards);
    }

    function _excludeFromReward(address account, bool exclude) private {
        if (exclude == isExcludedFromRewards[account]) return;

        if (exclude) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
            isExcludedFromRewards[account] = true;
            _excluded.push(account);
        } else {
            _rOwned[account] = _tOwned[account] * _getRate();
            _tOwned[account] = 0;
            isExcludedFromRewards[account] = false;

            for (uint256 i = 0; i < _excluded.length; i++) {
                if (_excluded[i] == account) {
                    _excluded[i] = _excluded[_excluded.length - 1];
                    _excluded.pop();
                    break;
                }
            }
        }

        emit RewardsExcluded(account, exclude);
    }

    // -------------------------------------------------------------------------
    // RFI INTERNALS
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
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) {
                return (_rTotal, _tTotal);
            }
            rSupply -= _rOwned[_excluded[i]];
            tSupply -= _tOwned[_excluded[i]];
        }

        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _getValues(uint256 tAmount, uint256 tFee)
        private
        view
        returns (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount)
    {
        uint256 rate = _getRate();
        rAmount = tAmount * rate;
        rFee = tFee * rate;
        rTransferAmount = rAmount - rFee;
        tTransferAmount = tAmount - tFee;
    }

    // -------------------------------------------------------------------------
    // VIEW HELPERS
    // -------------------------------------------------------------------------
    function circulatingSupply() external view returns (uint256) {
        return _tTotal - _tOwned[sinkWallet];
    }
}
