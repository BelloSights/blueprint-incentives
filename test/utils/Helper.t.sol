// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Test.sol";

import {Incentive} from "../../src/Incentive.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockERC721} from "../mock/MockERC721.sol";
import {MockERC1155} from "../mock/MockERC1155.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract Helper is Incentive {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /// @notice Computes the struct hash for IncentiveData.
    /// @dev This mirrors the new logic in the updated Incentive contract (note that feeRecipients are no longer present).
    function getStructHash(IncentiveData calldata data) public pure returns (bytes32) {
        // Encode the transactions and reward
        bytes32 encodedTxs = _encodeCompletedTxs(data.transactions);
        bytes32 encodedReward = _encodeReward(data.reward);

        return keccak256(
            abi.encode(
                INCENTIVE_DATA_HASH,
                data.questId,
                data.nonce,
                data.toAddress,
                keccak256(bytes(data.walletProvider)),
                keccak256(bytes(data.embedOrigin)),
                encodedTxs,
                encodedReward
            )
        );
    }

    /// @notice Recovers the signer from IncentiveData and its signature.
    function getSigner(IncentiveData calldata data, bytes calldata signature)
        public
        view
        returns (address)
    {
        return _getSigner(data, signature);
    }

    /// @notice Returns the full EIP712 digest given a domain separator and struct hash.
    function getDigest(bytes32 domainSeparator, bytes32 structHash) public pure returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }

    /// @notice Creates a IncentiveData struct for testing with the new structure.
    /// @param _claimTo The address to which rewards will be sent.
    /// @param factoryAddress The address of the factory (for reward distribution).
    /// @param tokenAddress The address of the reward token.
    /// @param tokenId The token id (if applicable).
    /// @param amount The reward amount.
    /// @param tokenType The reward token type.
    /// @param rakeBps The rake basis points.
    /// @param chainId The chain id where the reward applies.
    /// @return A IncentiveData struct with one dummy TransactionData (fields such as feeRecipients are no longer included).
    function getIncentiveData(
        address _claimTo,
        address factoryAddress,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        Incentive.TokenType tokenType,
        uint256 rakeBps,
        uint256 chainId
    ) public pure returns (Incentive.IncentiveData memory) {
        // Create one dummy transaction
        Incentive.TransactionData[] memory transactions = new Incentive.TransactionData[](1);
        transactions[0] = Incentive.TransactionData({
            txHash: "0xe265a54b4f6470f7f52bb1e4b19489b13d4a6d0c87e6e39c5d05c6639ec98002",
            networkChainId: "evm:137"
        });

        // Prepare the reward data
        Incentive.RewardData memory reward = Incentive.RewardData({
            tokenAddress: tokenAddress,
            chainId: chainId,
            amount: amount,
            tokenId: tokenId,
            tokenType: tokenType,
            rakeBps: rakeBps,
            factoryAddress: factoryAddress
        });

        return Incentive.IncentiveData({
            questId: 1,
            nonce: 1,
            toAddress: _claimTo,
            walletProvider: "MetaMask",
            embedOrigin: "test.com",
            transactions: transactions,
            reward: reward
        });
    }

    /// @notice Deposits native ETH to an escrow.
    function depositNativeToEscrow(address escrow, uint256 amount) public {
        (bool success,) = address(escrow).call{value: amount}("");
        require(success, "native deposit failed");
    }

    /// @notice Deposits ERC20 tokens to an escrow.
    function depositERC20ToEscrow(uint256 amount, address to, MockERC20 erc20) public {
        erc20.transfer(to, amount);
    }

    /// @notice Deposits an ERC721 token to an escrow.
    function depositERC721ToEscrow(address from, address to, uint256 tokenId, MockERC721 erc721) public {
        erc721.safeTransferFrom(from, to, tokenId);
    }
}
