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

    /// @notice Thrown when trying to deploy an OvixERC4626 vault using an asset without a cToken
    error OvixERC4626Factory__CTokenNonexistent();

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The COMP token contract
    ERC20 public immutable vix;

    /// @notice The address that will receive the liquidity mining rewards (if any)
    address public immutable rewardRecipient;

    /// @notice The Ovix comptroller contract
    IComptroller public immutable comptroller;

    /// @notice The Ovix cEther address
    address internal immutable oNativeAddress;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice Maps underlying asset to the corresponding cToken
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
        // initialize underlyingToCToken
        ICERC20[] memory allCTokens = comptroller_.getAllMarkets();
        uint256 numCTokens = allCTokens.length;
        ICERC20 oToken;
        for (uint256 i; i < numCTokens; ) {
            oToken = allCTokens[i];
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
        ICERC20 cToken = underlyingToOToken[asset];
        if (address(cToken) == address(0)) {
            revert OvixERC4626Factory__CTokenNonexistent();
        }

        vault = new OvixERC4626{salt: bytes32(0)}(
            asset,
            vix,
            cToken,
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

    /// @notice Updates the underlyingToCToken mapping in order to support newly added cTokens
    /// @dev This is needed because Ovix doesn't have an onchain registry of cTokens corresponding to underlying assets.
    /// @param newCTokenIndices The indices of the new cTokens to register in the comptroller.allMarkets array
    function updateUnderlyingToCToken(
        uint256[] calldata newCTokenIndices
    ) external {
        uint256 numCTokens = newCTokenIndices.length;
        ICERC20 cToken;
        uint256 index;
        for (uint256 i; i < numCTokens; ) {
            index = newCTokenIndices[i];
            cToken = comptroller.allMarkets(index);
            if (address(cToken) != oNativeAddress) {
                underlyingToOToken[cToken.underlying()] = cToken;
            }

            unchecked {
                ++i;
            }
        }
    }
}
