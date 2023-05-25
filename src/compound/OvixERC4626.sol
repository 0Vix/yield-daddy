// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {ICERC20} from "./external/ICERC20.sol";
import {LibCompound} from "./lib/LibCompound.sol";
import {IComptroller} from "./external/IComptroller.sol";

/// @title OvixERC4626
/// @author zefram.eth
/// @notice ERC4626 wrapper for Ovix Finance
contract OvixERC4626 is ERC4626 {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using LibCompound for ICERC20;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event ClaimRewards(uint256 amount);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when a call to Ovix returned an error.
    /// @param errorCode The error code returned by Ovix
    error OvixERC4626__OvixError(uint256 errorCode);

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant NO_ERROR = 0;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The VIX token contract
    ERC20 public immutable vix;

    /// @notice The Ovix oToken contract
    ICERC20 public immutable oToken;

    /// @notice The address that will receive the liquidity mining rewards (if any)
    address public immutable rewardRecipient;

    /// @notice The Ovix comptroller contract
    IComptroller public immutable comptroller;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(ERC20 asset_, ERC20 comp_, ICERC20 oToken_, address rewardRecipient_, IComptroller comptroller_)
        ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_))
    {
        vix = comp_;
        oToken = oToken_;
        comptroller = comptroller_;
        rewardRecipient = rewardRecipient_;
    }

    /// -----------------------------------------------------------------------
    /// Ovix liquidity mining
    /// -----------------------------------------------------------------------

    /// @notice Claims liquidity mining rewards from Ovix and sends it to rewardRecipient
    function claimRewards() external {
        address[] memory holders = new address[](1);
        holders[0] = address(this);
        ICERC20[] memory oTokens = new ICERC20[](1);
        oTokens[0] = oToken;
        comptroller.claimRewards(holders, oTokens, false, true);
        uint256 amount = vix.balanceOf(address(this));
        vix.safeTransfer(rewardRecipient, amount);
        emit ClaimRewards(amount);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function totalAssets() public view virtual override returns (uint256) {
        return oToken.viewUnderlyingBalanceOf(address(this));
    }

    function beforeWithdraw(uint256 assets, uint256 /*shares*/ ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Withdraw assets from Ovix
        /// -----------------------------------------------------------------------

        uint256 errorCode = oToken.redeemUnderlying(assets);
        if (errorCode != NO_ERROR) {
            revert OvixERC4626__OvixError(errorCode);
        }
    }

    function afterDeposit(uint256 assets, uint256 /*shares*/ ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Deposit assets into Ovix
        /// -----------------------------------------------------------------------

        // approve to oToken
        asset.safeApprove(address(oToken), assets);

        // deposit into oToken
        uint256 errorCode = oToken.mint(assets);
        if (errorCode != NO_ERROR) {
            revert OvixERC4626__OvixError(errorCode);
        }
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (comptroller.guardianPaused(oToken)) {
            return 0;
        }
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (comptroller.guardianPaused(oToken)) {
            return 0;
        }
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 cash = oToken.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 cash = oToken.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    // underlying to oToken exchange rate
    function exchangeRate() public view returns (uint256) {
        return oToken.viewExchangeRate();
    }

    // accumulated preVIX rewards
    function preVIXBalance() public view returns (uint256) {
        return vix.balanceOf(address(this));
    }

    /// -----------------------------------------------------------------------
    /// ERC20 metadata generation
    /// -----------------------------------------------------------------------

    function _vaultName(ERC20 asset_) internal view virtual returns (string memory vaultName) {
        vaultName = string.concat("ERC4626-Wrapped 0VIX ", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string.concat("wo", asset_.symbol());
    }
}
