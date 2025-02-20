// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITokenType} from "./ITokenType.sol";
import {Incentive} from "../../Incentive.sol";

interface IFactory is ITokenType {
    function distributeRewards(
        uint256 questId,
        address token,
        address to,
        uint256 amount,
        uint256 rewardTokenId,
        TokenType tokenType,
        uint256 rakeBps
    ) external;

    function withdrawFunds(
        uint256 questId,
        address to,
        address token,
        uint256 tokenId,
        TokenType tokenType
    ) external;

    function createEscrow(
        address creator,
        address[] memory whitelistedTokens,
        address treasury
    ) external returns (uint256);

    function addTokenToWhitelist(uint256 questId, address token) external;
    function removeTokenFromWhitelist(uint256 questId, address token) external;

    function initialize(address admin) external;

    function s_escrows(uint256 escrowId)
        external
        view
        returns (uint256 escrowId_, address escrow, address creator, bool active);

    function s_questToEscrow(uint256 questId) external view returns (uint256);

    function getEscrow(uint256 questId) external view returns (address);
}
