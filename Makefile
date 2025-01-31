# Environment file selection
ENV_FILE := .env
ifeq ($(findstring --network local,$(ARGS)),--network local)
ENV_FILE := .env.test
endif

# Load environment variables
-include $(ENV_FILE)

.PHONY: deploy test coverage build deploy_proxy fork_test deploy_all deploy_escrow verify_base_sepolia

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

deploy:
	@forge script script/DeployCube.s.sol:DeployCube $(NETWORK_ARGS)

deploy_proxy:
	@source $(ENV_FILE) && forge script script/DeployProxy.s.sol:DeployProxy $(NETWORK_ARGS) --ffi

upgrade_proxy:
	@source $(ENV_FILE) && forge script script/UpgradeCube.s.sol:UpgradeCube $(NETWORK_ARGS) \
		--ffi \
		--sig "run()"

fork_test:
	@forge test --rpc-url $(RPC_ENDPOINT) -vvv

deploy_all: deploy_proxy deploy_escrow

# Get proxy address from latest deployment
CUBE_PROXY_ADDRESS := $(shell ./bash-scripts/get-proxy-address.sh)

deploy_escrow:
ifndef CUBE_PROXY_ADDRESS
	$(error Run "make deploy_proxy" first)
endif
	@forge script script/DeployEscrow.s.sol:DeployEscrow $(NETWORK_ARGS) \
		--ffi \
		--sig "run(address,address,address)" \
		$(shell cast wallet address --private-key $(PRIVATE_KEY)) \
		$(TREASURY_ADDRESS) \
		$(CUBE_PROXY_ADDRESS)

verify_base_sepolia:
	@if [ -z "${ADDRESS}" ] || [ -z "${CONTRACT}" ]; then \
		echo "Usage: make verify ADDRESS=0x... CONTRACT=path:Name"; \
		echo "Example targets:"; \
		echo "  CUBE:     src/CUBE.sol:CUBE"; \
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