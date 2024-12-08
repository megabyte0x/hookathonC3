# Variables
ARTIFACTS_DIR = circuit_artifacts

# Default target
all: setup compile ptau gen_verifier

install:
	forge install cyfrin/foundry-devops --no-commit && npm i

# Create necessary directories
setup:
	mkdir -p $(ARTIFACTS_DIR)

# Compile withdraw.circom
compile:
	@echo "Compiling withdraw.circom..."
	circom circuits/withdraw.circom --r1cs --wasm --sym -o $(ARTIFACTS_DIR)

# Powers of tau ceremony
ptau:
	@echo "Performing powers of tau ceremony..."
	cd $(ARTIFACTS_DIR) && \
	snarkjs powersoftau new bn128 16 pot16_0000.ptau -v && \
	snarkjs powersoftau contribute pot16_0000.ptau pot16_0001.ptau --name="First contribution" -v && \
	snarkjs powersoftau prepare phase2 pot16_0001.ptau pot16_final.ptau -v

# Generate zkey and verifier contract
gen_verifier:
	cd $(ARTIFACTS_DIR) && \
	snarkjs groth16 setup withdraw.r1cs pot16_final.ptau withdraw_final.zkey && \
	snarkjs zkey export solidityverifier withdraw_final.zkey ../src/Verifier.sol && \
	snarkjs zkey export verificationkey withdraw_final.zkey verification_key.json

# Clean circuit_artifacts
clean:
	rm -rf $(ARTIFACTS_DIR)

deployFromSratch:
	forge script script/V4Deployer.s.sol:V4Deployer --fork-url http://localhost:8545 --broadcast
	forge script script/HookDeployer.s.sol:HookDeployer --fork-url http://localhost:8545 --broadcast --ffi

set_avs_address:
	forge script script/TornadoHook.s.sol:SetAVSAddress --fork-url http://localhost:8545 --broadcast --ffi
