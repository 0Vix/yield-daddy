// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {ICERC20} from "./external/ICERC20.sol";
import {OvixERC4626} from "./OvixERC4626.sol";
import {IComptroller} from "./external/IComptroller.sol";
import {ERC4626Factory} from "../base/ERC4626Factory.sol";

import "forge-std/console.sol";

/// @title OvixERC4626Factory
/// @author zefram.eth
/// @notice Factory for creating OvixERC4626 contracts
contract OvixERC4626Factory is ERC4626Factory {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when trying to deploy an OvixERC4626 vault using an asset without a oToken
    error OvixERC4626Factory__OTokenNonexistent();

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The COMP token contract
    ERC20 public immutable vix;

    /// @notice The address that will receive the liquidity mining rewards (if any)
    address public immutable rewardRecipient;

    /// @notice The Ovix comptroller contract
    IComptroller public immutable comptroller;

    /// @notice The Ovix oNative address (oMatic on PoS, oETH on zkEVM)
    address internal immutable oNativeAddress;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice Maps underlying asset to the corresponding oToken
    mapping(ERC20 => ICERC20) public underlyingToOToken;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        IComptroller comptroller_,
        address oNativeAddress_,
        address rewardRecipient_
    ) {
        comptroller = comptroller_;
        oNativeAddress = oNativeAddress_;
        rewardRecipient = rewardRecipient_;
        vix = ERC20(comptroller_.getVixAddress());
        // initialize underlyingToOToken
        ICERC20[] memory allOTokens = comptroller_.getAllMarkets();
        uint256 numOTokens = allOTokens.length;
        ICERC20 oToken;
        for (uint256 i; i < numOTokens; ) {
            oToken = allOTokens[i];
            if (address(oToken) != oNativeAddress_) {
                underlyingToOToken[oToken.underlying()] = oToken;
            }

            unchecked {
                ++i;
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @inheritdoc ERC4626Factory
    function createERC4626(
        ERC20 asset
    ) external virtual override returns (ERC4626 vault) {
        ICERC20 oToken = underlyingToOToken[asset];
        if (address(oToken) == address(0)) {
            revert OvixERC4626Factory__OTokenNonexistent();
        }

        vault = new OvixERC4626{salt: bytes32(0)}(
            asset,
            oToken,
            rewardRecipient,
            comptroller
        );

        emit CreateERC4626(asset, vault);
    }

    /// @inheritdoc ERC4626Factory
    function computeERC4626Address(
        ERC20 asset
    ) external view virtual override returns (ERC4626 vault) {
        vault = ERC4626(
            _computeCreate2Address(
                keccak256(
                    abi.encodePacked(
                        // Deployment bytecode:
                        type(OvixERC4626).creationCode,
                        // Constructor arguments:
                        abi.encode(
                            asset,
                            vix,
                            underlyingToOToken[asset],
                            rewardRecipient,
                            comptroller
                        )
                    )
                )
            )
        );
    }

    /// @notice Updates the underlyingToOToken mapping in order to support newly added oTokens
    /// @dev This is needed because Ovix doesn't have an onchain registry of oTokens corresponding to underlying assets.
    /// @param newOTokenIndices The indices of the new oTokens to register in the comptroller.allMarkets array
    function updateUnderlyingToOToken(
        uint256[] calldata newOTokenIndices
    ) external {
        uint256 numOTokens = newOTokenIndices.length;
        ICERC20 oToken;
        uint256 index;
        for (uint256 i; i < numOTokens; ) {
            index = newOTokenIndices[i];
            oToken = comptroller.allMarkets(index);
            if (address(oToken) != oNativeAddress) {
                underlyingToOToken[oToken.underlying()] = oToken;
            }

            unchecked {
                ++i;
            }
        }
    }
}
