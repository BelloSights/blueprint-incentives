# Environment file selection
ENV_FILE := .env
ifeq ($(findstring --network local,$(ARGS)),--network local)
ENV_FILE := .env.test
endif

# Load environment variables
-include $(ENV_FILE)

.PHONY: deploy test coverage build deploy_proxy fork_test deploy_all deploy_escrow verify_base_sepolia deploy_storefront deploy_treasury deploy_token deploy_nft_factory upgrade_proxy upgrade_nft_factory verify_erc1155_implementation verify_blueprint_factory_implementation

DEFAULT_ANVIL_PRIVATE_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

install:; forge install
build:; forge build
test:
	@source .env.test && forge clean && forge test -vvvv --ffi

test-coverage:
	@source .env.test && forge coverage --ffi

coverage :; forge coverage --ffi --report debug > coverage-report.txt
snapshot :; forge snapshot --ffi

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_PRIVATE_KEY) --broadcast

# Goerli
ifeq ($(findstring --network goerli,$(ARGS)),--network goerli)
	NETWORK_ARGS := --rpc-url $(GOERLI_RPC_ENDPOINT) --private-key $(PRIVATE_KEY) --verify --etherscan-api-key $(ETHERSCAN_API_KEY) --broadcast -vvvv
endif

# Base Mainnet
ifeq ($(findstring --network base,$(ARGS)),--network base)
	NETWORK_ARGS := --rpc-url $(BASE_MAINNET_RPC) --private-key $(PRIVATE_KEY) --broadcast -vvvv
endif

# Base Sepolia
ifeq ($(findstring --network base_sepolia,$(ARGS)),--network base_sepolia)
	NETWORK_ARGS := --rpc-url $(BASE_SEPOLIA_RPC) --private-key $(PRIVATE_KEY) --broadcast -vvvv
endif

# Cyber Testnet
ifeq ($(findstring --network cyber_testnet,$(ARGS)),--network cyber_testnet)
	NETWORK_ARGS := --rpc-url $(CYBER_TESTNET_RPC) --private-key $(PRIVATE_KEY) --broadcast -vvvv
endif

# Cyber Mainnet 
ifeq ($(findstring --network cyber,$(ARGS)),--network cyber)
	NETWORK_ARGS := --rpc-url $(CYBER_MAINNET_RPC) --private-key $(PRIVATE_KEY) --broadcast -vvvv
endif

# Local network
ifeq ($(findstring --network local,$(ARGS)),--network local)
	NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(PRIVATE_KEY) --broadcast -vvvv
endif

# Add to NETWORK_ARGS handling
ifeq ($(findstring --unsafe,$(ARGS)),--unsafe)
	NETWORK_ARGS += --unsafe
endif

deploy_treasury:
	@source $(ENV_FILE) && forge script script/DeployTreasury.s.sol:DeployTreasury $(NETWORK_ARGS) --ffi

deploy_token:
	@source $(ENV_FILE) && forge script script/DeployToken.s.sol:DeployToken $(NETWORK_ARGS) --ffi

deploy_storefront:
	@source $(ENV_FILE) && forge script script/DeployStorefront.s.sol:DeployStorefront $(NETWORK_ARGS) --ffi

deploy_proxy:
	@source $(ENV_FILE) && forge script script/DeployProxy.s.sol:DeployProxy $(NETWORK_ARGS) --ffi

deploy_escrow:
	@source $(ENV_FILE) && forge script script/DeployEscrow.s.sol:DeployEscrow $(NETWORK_ARGS) --ffi --sig "deploy()"

deploy_nft_factory:
	@source $(ENV_FILE) && forge script script/DeployBlueprintNFT.s.sol:DeployBlueprintNFT $(NETWORK_ARGS) --ffi

upgrade_proxy:
	@source $(ENV_FILE) && forge script script/UpgradeIncentive.s.sol:UpgradeIncentive $(NETWORK_ARGS) \
		--ffi \
		--sig "run()"

upgrade_nft_factory:
	@source $(ENV_FILE) && forge script script/UpgradeBlueprintNFT.s.sol:UpgradeBlueprintNFT $(NETWORK_ARGS) \
		--ffi \
		--sig "run()"

fork_test:
	@forge test --rpc-url $(RPC_ENDPOINT) -vvv

deploy_all: deploy_proxy deploy_token deploy_storefront deploy_treasury

verify_erc1155_implementation:
	@forge verify-contract \
		$(BASE_ERC1155_IMPLEMENTATION_ADDRESS) \
		"src/nft/BlueprintERC1155.sol:BlueprintERC1155" \
		--chain-id 8453 \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		--rpc-url $(BASE_MAINNET_RPC) \
		--watch

verify_blueprint_factory_implementation:
	@echo "Verifying BlueprintERC1155Factory implementation contract..."
	@forge verify-contract \
		$(BASE_ERC1155_FACTORY_IMPLEMENTATION_ADDRESS) \
		"src/nft/BlueprintERC1155Factory.sol:BlueprintERC1155Factory" \
		--chain-id 8453 \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		--rpc-url $(BASE_MAINNET_RPC) \
		--watch

verify_erc1155_implementation_base_sepolia:
	@forge verify-contract \
		$(BASE_SEPOLIA_ERC1155_IMPLEMENTATION_ADDRESS) \
		"src/nft/BlueprintERC1155.sol:BlueprintERC1155" \
		--chain-id 84532 \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		--rpc-url $(BASE_SEPOLIA_RPC) \
		--watch

verify_blueprint_factory_implementation_base_sepolia:
	@echo "Verifying BlueprintERC1155Factory implementation contract..."
	@forge verify-contract \
		$(BASE_SEPOLIA_ERC1155_FACTORY_IMPLEMENTATION_ADDRESS) \
		"src/nft/BlueprintERC1155Factory.sol:BlueprintERC1155Factory" \
		--chain-id 84532 \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		--rpc-url $(BASE_SEPOLIA_RPC) \
		--watch

verify_base_sepolia:
	@if [ -z "${ADDRESS}" ] || [ -z "${CONTRACT}" ]; then \
		echo "Usage: make verify ADDRESS=0x... CONTRACT=path:Name"; \
		echo "Example targets:"; \
		echo "  Incentive:     src/Incentive.sol:Incentive"; \
		echo "  Factory:  src/escrow/Factory.sol:Factory"; \
		echo "  Escrow:   src/escrow/Escrow.sol:Escrow"; \
		exit 1; \
	fi
	forge verify-contract \
		${ADDRESS} \
		"${CONTRACT}" \
		--chain-id 84532 \
		--verifier etherscan \
		--etherscan-api-key ${BASESCAN_API_KEY}

verify_base:
	@if [ -z "${ADDRESS}" ] || [ -z "${CONTRACT}" ]; then \
		echo "Usage: make verify ADDRESS=0x... CONTRACT=path:Name"; \
		echo "Example targets:"; \
		echo "  Incentive:     src/Incentive.sol:Incentive"; \
		echo "  Factory:       src/escrow/Factory.sol:Factory"; \
		echo "  Escrow:        src/escrow/Escrow.sol:Escrow"; \
		echo "  BlueprintERC1155: src/nft/BlueprintERC1155.sol:BlueprintERC1155"; \
		exit 1; \
	fi
	forge verify-contract \
		${ADDRESS} \
		"${CONTRACT}" \
		--chain-id 8453 \
		--verifier etherscan \
		--etherscan-api-key ${BASESCAN_API_KEY}
