// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Btest is ERC20, ERC20Permit, Ownable {

    // -------------------------------------------------------------------------
    // HARD-CODED SYSTEM WALLETS (ENGINE-CONTROLLED, LOCKED) - TESTING TESTING
    // -------------------------------------------------------------------------
    address public constant ENGINE_WALLET    = 0x72D5DFE8827E6f117E31668D8E460F1572Be767e;
    address public constant MARKETING_WALLET = 0xB36f3aa9875668c44aCb8C6ad50D405679D4736c;
    address public constant DEV_WALLET       = 0x4c50381460B9530041d783Bc0f36A7cF20b84Ed8;
    address public constant LOTTERY_WALLET   = 0x042566dDF73101b29749F00d5E71594e1ceB3596;
    address public constant JACKPOT_WALLET   = 0xaD5E560150bEE0C3E933154c933D315297597704;
    address public constant SINK_WALLET      = 0xCC314556d404616c66a28F10A85AE8835238FC5E;

    address public constant engine = ENGINE_WALLET;

    // -------------------------------------------------------------------------
    // NON-CIRCULATING (CUSTODY + RESERVE) WALLETS
    // -------------------------------------------------------------------------
    address public constant CUSTODY_WALLET        = 0x48Fe53Ce093950B6c0510186CA3e2BF20F659226;

    address public constant RESERVE_LIQUIDITY     = 0x1eF243a43D4Bb7d6aa2F738BEc3d4AD297ba6a08;
    address public constant RESERVE_VESTING       = 0xaB3D656D2cd46310E082E7ce36A0CD23Ce470486;
    address public constant RESERVE_MINING        = 0x582738f6f6e7E882fffCb53eDA7f0491F44db449;
    address public constant RESERVE_MARKETING     = 0x5eFE8f36Cd4E4dbBa7f2585170BB0603608Fe595;
    address public constant RESERVE_DEVELOPMENT   = 0x2CfE7065289C2543663ffcd62AaCf566E5D0100d;
    address public constant RESERVE_BONUS         = 0xfC6da39a46f2E45cb63528e46e5eb4Bd4405f031;
    address public constant RESERVE_DAO           = 0x9F5196b3d771a86A83F7A27230DB22DA914a742a;

    // -------------------------------------------------------------------------
    // MODIFIERS
    // -------------------------------------------------------------------------
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
    // SYSTEM FLAGS
    // -------------------------------------------------------------------------
    mapping(address => bool) public isSystemWallet;
    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isExcludedFromRewards;

    bool public lpExcluded;

    // -------------------------------------------------------------------------
    // SPLITS (SUM = 100)
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
    event TaxApplied(address indexed from, uint256 taxAmount, uint16 rate);

    // -------------------------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------------------------
    constructor(address initialOwner)
        ERC20("Btest", "BTEST")
        ERC20Permit("Btest")
        Ownable(initialOwner)
    {
        // ---------------------------------------------------------------------
        // REGISTER SYSTEM (ENGINE-CONTROLLED) WALLETS
        // ---------------------------------------------------------------------
        address[6] memory systemWallets = [
            ENGINE_WALLET,
            MARKETING_WALLET,
            DEV_WALLET,
            LOTTERY_WALLET,
            JACKPOT_WALLET,
            SINK_WALLET
        ];

        for (uint256 i = 0; i < systemWallets.length; i++) {
            address w = systemWallets[i];
            isSystemWallet[w] = true;
            isExcludedFromFee[w] = true;
            isExcludedFromRewards[w] = true;
            _excluded.push(w);
        }

        // ---------------------------------------------------------------------
        // EXCLUDE CUSTODY + RESERVE WALLETS (NON-CIRCULATING)
        // ---------------------------------------------------------------------
        address[8] memory excludedWallets = [
            CUSTODY_WALLET,
            RESERVE_LIQUIDITY,
            RESERVE_VESTING,
            RESERVE_MINING,
            RESERVE_MARKETING,
            RESERVE_DEVELOPMENT,
            RESERVE_BONUS,
            RESERVE_DAO
        ];

        for (uint256 i = 0; i < excludedWallets.length; i++) {
            address w = excludedWallets[i];
            isExcludedFromFee[w] = true;
            isExcludedFromRewards[w] = true;
            _excluded.push(w);
        }

        // ---------------------------------------------------------------------
        // RFI-AUTHORITATIVE MINT
        // ---------------------------------------------------------------------
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

        require(from != SINK_WALLET, "Sink locked");
        require(!isSystemWallet[from], "System locked");

        bool takeFee = !(isExcludedFromFee[from] || isExcludedFromFee[to]);
        _tokenTransfer(from, to, amount, takeFee);
    }

    // -------------------------------------------------------------------------
    // SYSTEM PAYOUT (ENGINE ONLY, TAX-FREE)
    // -------------------------------------------------------------------------
    function systemPayout(address from, address to, uint256 amount)
        external
        onlyEngine
    {
        require(isSystemWallet[from], "Not system wallet");
        require(from != SINK_WALLET, "Sink cannot pay");
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
    // LP EXCLUSION
    // -------------------------------------------------------------------------
    function excludeLPFromRewards(address lp) external onlyOwner {
        require(!lpExcluded, "LP excluded");
        require(lp != address(0), "Zero address");

        isExcludedFromRewards[lp] = true;
        _excluded.push(lp);
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

        _takeFee(from, SINK_WALLET,      (taxAmount * sinkShare) / 100, rate);
        _takeFee(from, MARKETING_WALLET, (taxAmount * marketingShare) / 100, rate);
        _takeFee(from, DEV_WALLET,       (taxAmount * devShare) / 100, rate);
        _takeFee(from, LOTTERY_WALLET,   (taxAmount * lotteryShare) / 100, rate);
        _takeFee(from, JACKPOT_WALLET,   (taxAmount * jackpotShare) / 100, rate);

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
            rSupply -= _rOwned[_excluded[i]];
            tSupply -= _tOwned[_excluded[i]];
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
