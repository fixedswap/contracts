const { task, types } = require('hardhat/config')
const { BN } = require('ethereumjs-util')
require('@nomiclabs/hardhat-web3')

async function createWeb3Contract({ name, artifactName, address, deployments, web3, from }) {
  const { getArtifact, get } = deployments
  const addr = address ? address : (await get(name)).address
  const contract = new web3.eth.Contract((await getArtifact(artifactName ? artifactName : name)).abi, addr, from ? { from } : undefined)
  return { addr, contract }
}

function BNFromString(str) {
  return str.indexOf('0x') === 0 ? new BN(str.substr(2), 'hex') : new BN(str)
}

async function decimals(contract) {
  return BNFromString(await contract.methods.decimals().call())
}

async function balanceOf(contract, account) {
  const dec = await decimals(contract)
  const bal = BNFromString(await contract.methods.balanceOf(account).call())
  return bal.div(new BN(10).pow(dec))
}

async function allowance(contract, from, to) {
  return BNFromString(await contract.methods.allowance(from, to).call())
}

async function approve(contract, to) {
  await contract.methods.approve(to, '0x' + 'f'.repeat(64)).send()
}

async function mint(contract, to, amount) {
  const dec = await decimals(contract)
  await contract.methods.mint(to, new BN(amount).mul(new BN(10).pow(dec))).send()
}

function actualAmount(amount, dec) {
  return typeof amount === 'string' ? BNFromString(amount).mul(new BN(10).pow(dec)) : new BN(amount).mul(new BN(10).pow(dec))
}

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async () => {
  const accounts = await ethers.getSigners()

  for (const account of accounts) {
    console.log(account.address)
  }
})

task('balance', "Prints an account's balance")
  .addParam('account', 'User account')
  .setAction(async (taskArgs, { web3 }) => {
    const { account } = taskArgs
    const balance = await web3.eth.getBalance(account)

    console.log(web3.utils.fromWei(balance, 'ether'), 'ETH')
  })

task('testoken:mint', 'Mint test token to account')
  .addParam('account', 'User account')
  .addOptionalParam('amount', 'the amount of test token', 10000, types.int)
  .setAction(async (taskArgs, { web3, deployments, getNamedAccounts }) => {
    const { deployer } = await getNamedAccounts()
    const { account, amount } = taskArgs
    for (const name of ['USDT', 'USDC', 'DAI']) {
      const { contract } = await createWeb3Contract({ name, artifactName: 'TokenERC20', deployments, web3, from: deployer })
      await mint(contract, account, amount)
      console.log('mint test token', name, 'success')
    }
  })

task('testoken:balance', 'Query balance of each test token')
  .addParam('account', 'User account')
  .setAction(async (taskArgs, { web3, deployments }) => {
    const { account } = taskArgs
    for (const name of ['USDT', 'USDC', 'DAI']) {
      const { contract } = await createWeb3Contract({ name, artifactName: 'TokenERC20', deployments, web3 })
      console.log((await balanceOf(contract, account)).toString(), name)
    }
  })

task('ss:mint', 'Mint SS token to account')
  .addParam('account', 'User account')
  .addOptionalParam('amount', 'the amount of ss token', 10000, types.int)
  .setAction(async (taskArgs, { web3, deployments, getNamedAccounts }) => {
    const { deployer } = await getNamedAccounts()
    const { account, amount } = taskArgs
    const { contract } = await createWeb3Contract({ name: 'SS', artifactName: 'TokenERC20', deployments, web3, from: deployer })
    await mint(contract, account, amount)
    console.log('mint ss success')
  })

task('ss:balance', 'Query balance of ss')
  .addParam('account', 'User account')
  .setAction(async (taskArgs, { web3, deployments }) => {
    const { account } = taskArgs
    const { contract } = await createWeb3Contract({ name: 'SS', artifactName: 'TokenERC20', deployments, web3 })
    console.log((await balanceOf(contract, account)).toString(), 'SS')
  })

task('uniswap:addlq', 'Add liquidity to uniswap')
  .addFlag('test', 'Use test token and test uniswap')
  .addParam('account', 'User account')
  .addParam('ssamount', 'amount of ss', 1000, types.int)
  .addParam('stablecoinamount', 'amount of ss', 1000, types.int)
  .setAction(async (taskArgs, { web3, deployments }) => {
    const { test, account, ssamount, stablecoinamount } = taskArgs
    const { addr: USDTAddr, contract: USDT } = test
      ? await createWeb3Contract({ name: 'USDT', artifactName: 'TokenERC20', deployments, web3, from: account })
      : await createWeb3Contract({ artifactName: 'TokenERC20', deployments, web3, address: process.env.STABLE_COIN_ADDR, from: account })
    const { addr: ssAddr, contract: ss } = await createWeb3Contract({ name: 'SS', artifactName: 'TokenERC20', deployments, web3, from: account })
    const { addr: routerAddr, contract: router } = test
      ? await createWeb3Contract({ name: 'Router', artifactName: 'UniswapV2Router02', deployments, web3, from: account })
      : await createWeb3Contract({ artifactName: 'UniswapV2Router02', deployments, web3, address: process.env.ROUTER_ADDR, from: account })
    const USDTDec = await decimals(USDT)
    const USDTAllowanceFromAccToRounter = await allowance(USDT, account, routerAddr)
    if (USDTAllowanceFromAccToRounter.eqn(0)) {
      console.log('start approve usdt, from', account, 'to', routerAddr)
      await approve(USDT, routerAddr)
    }
    const ssDec = await decimals(ss)
    const ssAllowanceFromAccToRouter = await allowance(ss, account, routerAddr)
    if (ssAllowanceFromAccToRouter.eqn(0)) {
      console.log('start approve ss, from', account, 'to', routerAddr)
      await approve(ss, routerAddr)
    }
    await router.methods
      .addLiquidity(
        USDTAddr,
        ssAddr,
        actualAmount(stablecoinamount, USDTDec),
        actualAmount(ssamount, ssDec),
        '1',
        '1',
        account,
        '0x' + 'f'.repeat(64)
      )
      .send()
    console.log('add liquidity to uniswap success')
  })

task('stableswap:whitelist', 'Set stable swap whitelist')
  .addOptionalParam('addr', 'the address of stable coin')
  .addOptionalParam('name', 'the name of stable coin')
  .setAction(async (taskArgs, { web3, deployments }) => {
    const { get } = deployments
    const { deployer } = await getNamedAccounts()
    const { addr, name } = taskArgs
    const { contract: stableSwap } = await createWeb3Contract({ name: 'StableSwap', deployments, web3, from: deployer })
    const stableCoinAddr = name ? (await get(name)).address : addr
    await stableSwap.methods.addWhitelist(stableCoinAddr).send()
    console.log('add', stableCoinAddr, 'to stable swap whitelist success')
  })

task('stableswap:addlq', 'Add liquidity to stable swap')
  .addParam('account', 'User account')
  .addParam('amount', 'amount of stable coin', 1000, types.int)
  .addOptionalParam('addr', 'the address of stable coin')
  .addOptionalParam('name', 'the name of stable coin')
  .setAction(async (taskArgs, { web3, deployments }) => {
    const { addr, name, account, amount } = taskArgs
    const { addr: stableCoinAddr, contract: stableCoin } = name
      ? await createWeb3Contract({ name, artifactName: 'TokenERC20', deployments, web3, from: account })
      : await createWeb3Contract({ artifactName: 'TokenERC20', deployments, web3, address: addr, from: account })
    const { addr: stableSwapAddr, contract: stableSwap } = await createWeb3Contract({ name: 'StableSwap', deployments, web3, from: account })
    const dec = await decimals(stableCoin)
    const allowanceFromAccToRounter = await allowance(stableCoin, account, stableSwapAddr)
    if (allowanceFromAccToRounter.eqn(0)) {
      console.log('start approve stable coin, from', account, 'to', stableSwapAddr)
      await approve(stableCoin, stableSwapAddr)
    }
    await stableSwap.methods.deposit(stableCoinAddr, actualAmount(amount, dec), account).send()
    console.log('add liquidity to stable swap success')
  })

task('stableswap:setfee', 'Set the fee percentage of stable swap')
  .addOptionalParam('fee', 'fee percentage', 4, types.int)
  .setAction(async (taskArgs, { web3, deployments, getNamedAccounts }) => {
    const { fee } = taskArgs
    const { deployer } = await getNamedAccounts()
    const { contract } = await createWeb3Contract({ name: 'StableSwap', deployments, web3, from: deployer })
    await contract.methods.setFee(fee).send()
    console.log('set fee to', fee)
  })

task('initrole', 'Initialize role').setAction(async (taskArgs, { web3, deployments, getNamedAccounts }) => {
  const { deployer } = await getNamedAccounts()
  const { addr: swapMiningAddr } = await createWeb3Contract({ name: 'SwapMining', deployments, web3 })
  const { addr: masterChefAddr } = await createWeb3Contract({ name: 'MasterChef', deployments, web3 })
  const { contract: ss } = await createWeb3Contract({ name: 'SS', artifactName: 'TokenERC20', deployments, web3, from: deployer })
  const mintRole = await ss.methods.MINTER_ROLE().call()
  await ss.methods.grantRole(mintRole, swapMiningAddr).send()
  await ss.methods.grantRole(mintRole, masterChefAddr).send()
  console.log('init role success')
})

task('swapmining:add', 'Add ss pair to swap mining')
  .addOptionalParam('alloc', 'alloc point', 10, types.int)
  .setAction(async (taskArgs, { web3, deployments, getNamedAccounts }) => {
    const { alloc } = taskArgs
    const { deployer } = await getNamedAccounts()
    const { contract } = await createWeb3Contract({ name: 'SwapMining', deployments, web3, from: deployer })
    const { addr: stableSwapAddr } = await createWeb3Contract({ name: 'StableSwap', deployments, web3 })
    await contract.methods.addPair(alloc, stableSwapAddr, false).send()
    console.log('add pair to swap mining success')
  })

task('masterchef:add', 'Add ss pair to master chef')
  .addOptionalParam('alloc', 'alloc point', 10, types.int)
  .setAction(async (taskArgs, { web3, deployments, getNamedAccounts }) => {
    const { alloc } = taskArgs
    const { deployer } = await getNamedAccounts()
    const { contract } = await createWeb3Contract({ name: 'MasterChef', deployments, web3, from: deployer })
    const { contract: ss } = await createWeb3Contract({ name: 'StableSwap', deployments, web3 })
    await contract.methods.add(alloc, await ss.methods.lp().call(), false).send()
    console.log('add pair to master chef success')
  })

task('masterchef:deposit', 'Deposit all token to master chef')
  .addParam('account', 'User account')
  .addOptionalParam('pid', 'pool index', 0, types.int)
  .setAction(async (taskArgs, { web3, deployments }) => {
    const { account, pid } = taskArgs
    const { addr: masterChefAddr, contract: masterChef } = await createWeb3Contract({ name: 'MasterChef', deployments, web3, from: account })
    const { contract: ss } = await createWeb3Contract({ name: 'StableSwap', deployments, web3 })
    const lpAddr = await ss.methods.lp().call()
    const { contract: lp } = await createWeb3Contract({ artifactName: 'TokenERC20', address: lpAddr, deployments, web3, from: account })
    const allowanceFromAccToMasterChef = await allowance(lp, account, masterChefAddr)
    if (allowanceFromAccToMasterChef.eqn(0)) {
      console.log('start approve ss lp, from', account, 'to', masterChefAddr)
      await approve(lp, masterChefAddr)
    }
    const bal = await lp.methods.balanceOf(account).call()
    if (new BN(bal).gtn(0)) {
      await masterChef.methods.deposit(pid, bal).send()
      console.log('deposit', bal.toString(), 'to master chef success')
    } else {
      console.log('skip deposit, balance = 0')
    }
  })

task('setup', 'Setup all contracts')
  .addFlag('test', 'Use test token and test uniswap')
  .addParam('account', 'User account')
  .addParam('ssamount', 'amount of ss', 1000, types.int)
  .addParam('stablecoinamount', 'amount of ss', 1000, types.int)
  .addParam('ssmintamount', 'mint the amount of ss', 10000, types.int)
  .setAction(async (taskArgs, { run }) => {
    const { account, test, stablecoinamount, ssamount, ssmintamount } = taskArgs
    if (test) {
      await run('testoken:mint', { account })
    }
    await run('ss:mint', { account, amount: ssmintamount })
    await run('uniswap:addlq', { test, account, stablecoinamount, ssamount })
    if (test) {
      await run('stableswap:whitelist', { name: 'USDT' })
      await run('stableswap:whitelist', { name: 'USDC' })
      await run('stableswap:whitelist', { name: 'DAI' })
      await run('stableswap:addlq', { account, name: 'USDT', amount: 1000 })
      await run('stableswap:addlq', { account, name: 'USDC', amount: 1000 })
      await run('stableswap:addlq', { account, name: 'DAI', amount: 1000 })
    } else {
      await run('stableswap:whitelist', { addr: process.env.STABLE_COIN_ADDR })
    }
    await run('stableswap:setfee')
    await run('initrole')
    await run('swapmining:add')
    await run('masterchef:add')
    await run('masterchef:deposit', { account })
  })
