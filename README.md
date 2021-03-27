# stableswap-contracts

![Node Version](https://img.shields.io/badge/node-%e2%89%a5v12.0.0-blue)
![NPM Version](https://img.shields.io/badge/npm-%E2%89%A5v6.0.0-blue)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-3.2.0-blue)
![UniswapV2Periphery](https://img.shields.io/badge/UniswapV2Periphery-1.1.0--beta.0-blue)

## Environment variable

```sh
# the api key of infura(if you want to connect mainnet or ethereum testnet, you must provide this key).
export INFURA_API_KEY=xxx
# the mnemonic of deployer(if not provided, the deployer will be the first account of the default accouts).
export MNEMONIC="test test test test test test test test test test test junk"
# deployer address, it should match the mnemonic
export DEV_ADDR=0x...abc
# UniswapV2Router02 address, which should be provided when deploying on mainnet
export ROUTER_ADDR=0x...abc
# stable coin address(used to create a uniswap trading pair with ss), which should be provided when deploying on mainnet
export STABLE_COIN_ADDR=0x...abc
# etherscan api key, used to verify and publish the contracts
export ETHERSCAN_KEY=xxx
```

## Install

```
npm i
```

## Compile

```
npm run build
```

## Develop

### Develop on localhost

```
npm run node
npx hardhat --network localhost setup --test --account 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --stablecoinamount 1000 --ssamount 1000 --ssmintamount 10000
```

### Develop on testnet(like goerli)

```
npm run deploy:goerli
npx hardhat --network goerli setup --test --account 0x...abc --stablecoinamount 1000 --ssamount 1000 --ssmintamount 10000
```

## Deploy to mainnet

```
npm run deploy:mainnet
npx hardhat --network mainnet setup --account 0x...abc --stablecoinamount xxx --ssamount xxx --ssmintamount xxx
```

## Tasks

```
accounts              Prints the list of accounts
balance               Prints an account's balance
initrole              Initialize role
masterchef:add        Add ss pair to master chef
masterchef:deposit    Deposit all token to master chef
setup                 Setup all contracts
ss:balance            Query balance of ss
ss:mint               Mint SS token to account
stableswap:addlq      Add liquidity to stable swap
stableswap:setfee     Set the fee percentage of stable swap
stableswap:whitelist  Set stable swap whitelist
swapmining:add        Add ss pair to swap mining
testoken:balance      Query balance of each test token
testoken:mint         Mint test token to account
uniswap:addlq         Add liquidity to uniswap
verify                Verifies contract on Etherscan
```

You can get detailed options of the task like this:

```
npx hardhat ss:mint --help
```

You can simply run the task like this:

```
npx hardhat --network localhost stableswap:whitelist --name USDT
npx hardhat --network localhost stableswap:addlq --account 0x...abc --name USDT --amount 100
```

## Verify

**notice: please first make sure you can access [api.etherscan.io](https://api.etherscan.io)**

```
npx hardhat verify --network goerli 0x...abc ConstructorArgs...
```

## LICENSE

[MIT](https://opensource.org/licenses/MIT)
