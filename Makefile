
main		:; FOUNDRY_PROFILE=mainnet forge test -vvv
unit		:; FOUNDRY_PROFILE=default forge test -vvv

# Coverage https://github.com/linux-test-project/lcov (brew install lcov)
cover		:;	forge coverage --watch --report lcov && genhtml lcov.info --branch-coverage --output-dir coverage
show		:;	npx http-server ./coverage

fmt     :;  FOUNDRY_PROFILE=default forge fmt && FOUNDRY_PROFILE=mainnet forge fmt
