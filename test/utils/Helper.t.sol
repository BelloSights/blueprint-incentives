// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ITokenType} from "../../src/incentive/interfaces/ITokenType.sol";
import {Incentive} from "../../src/incentive/Incentive.sol";

/// @notice Test helper to build IncentiveData and EIP-712 digests
contract Helper {
    // Must match Incentive.sol constants exactly
    bytes32 internal constant TX_DATA_HASH =
        keccak256("TransactionData(string txHash,string networkChainId)");
    bytes32 internal constant REWARD_DATA_HASH = keccak256(
        "RewardData(address tokenAddress,uint256 chainId,uint256 amount,uint256 tokenId,uint8 tokenType,uint256 rakeBps,address factoryAddress)"
    );
    bytes32 internal constant INCENTIVE_DATA_HASH = keccak256(
        "IncentiveData(uint256 questId,uint256 nonce,address toAddress,string walletProvider,string embedOrigin,TransactionData[] transactions,RewardData reward)RewardData(address tokenAddress,uint256 chainId,uint256 amount,uint256 tokenId,uint8 tokenType,uint256 rakeBps,address factoryAddress)TransactionData(string txHash,string networkChainId)"
    );

    function getIncentiveData(
        address to,
        address factory,
        address token,
        uint256 tokenId,
        uint256 amount,
        ITokenType.TokenType tokenType,
        uint256 rakeBps,
        uint256 chainId
    ) external pure returns (Incentive.IncentiveData memory data) {
        data.questId = 1;
        data.nonce = 0;
        data.toAddress = to;
        data.walletProvider = "test";
        data.embedOrigin = "test";
        data.transactions = new Incentive.TransactionData[](1);
        data.transactions[0] = Incentive.TransactionData({txHash: "0x", networkChainId: "evm:1"});
        data.reward = Incentive.RewardData({
            tokenAddress: token,
            chainId: chainId,
            amount: amount,
            tokenId: tokenId,
            tokenType: tokenType,
            rakeBps: rakeBps,
            factoryAddress: factory
        });
    }

    function getStructHash(Incentive.IncentiveData memory data)
        external
        pure
        returns (bytes32)
    {
        bytes32 txs = _encodeCompletedTxs(data.transactions);
        bytes32 reward = _encodeReward(data.reward);
        bytes memory encoded = abi.encode(
            INCENTIVE_DATA_HASH,
            data.questId,
            data.nonce,
            data.toAddress,
            _encodeString(data.walletProvider),
            _encodeString(data.embedOrigin),
            txs,
            reward
        );
        return keccak256(encoded);
    }

    function getDigest(bytes32 domainSeparator, bytes32 structHash)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    // -------- Internal encoding helpers (mirror Incentive.sol) --------
    function _encodeString(string memory s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    function _encodeTx(Incentive.TransactionData memory txd)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(TX_DATA_HASH, _encodeString(txd.txHash), _encodeString(txd.networkChainId));
    }

    function _encodeCompletedTxs(Incentive.TransactionData[] memory txData)
        internal
        pure
        returns (bytes32)
    {
        bytes32[] memory hashes = new bytes32[](txData.length);
        for (uint256 i = 0; i < txData.length; i++) {
            hashes[i] = keccak256(_encodeTx(txData[i]));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _encodeReward(Incentive.RewardData memory r) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                REWARD_DATA_HASH,
                r.tokenAddress,
                r.chainId,
                r.amount,
                r.tokenId,
                r.tokenType,
                r.rakeBps,
                r.factoryAddress
            )
        );
    }
}


