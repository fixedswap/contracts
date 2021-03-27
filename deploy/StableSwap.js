const process = require('process')
const { Address, bufferToHex, BN } = require('ethereumjs-util')
const settings = require('./deploySettings')

module.exports = async function ({ deployments, getNamedAccounts }) {
  const { deploy, save, get, read } = deployments

  const { deployer } = await getNamedAccounts()

  const ssAddr = (await get('SS')).address
  const routerAddr = process.env.ROUTER_ADDR || (await get('Router')).address
  const stableCoinAddr = process.env.STABLE_COIN_ADDR || (await get('USDT')).address

  const swapMining = await deploy('SwapMining', {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    // address of ss, reward per block, start block, bonus end block
    args: [
      ssAddr,
      new BN(settings['swapMining'].rewardPerBlock).mul(new BN(10).pow(new BN(18))).toString(),
      settings['swapMining'].startBlock,
      settings['swapMining'].bonusEndBlock,
    ],
  })
  await save('SwapMining', swapMining)
  console.log('SwapMing:', swapMining.address)

  const stableSwap = await deploy('StableSwap', {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    // address of ss, addres of sslp, uniswap router address, swap mining address, feedback path of ss
    args: [ssAddr, bufferToHex(Address.zero().buf), routerAddr, swapMining.address, [stableCoinAddr, ssAddr]],
  })
  await save('StableSwap', stableSwap)
  console.log('StableSwap:', stableSwap.address)

  const masterChef = await deploy('MasterChef', {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    // address of ss, dev addr, reward per block, start block, bonus end block
    args: [
      ssAddr,
      deployer,
      new BN(settings['masterChef'].rewardPerBlock).mul(new BN(10).pow(new BN(18))).toString(),
      settings['masterChef'].startBlock,
      settings['masterChef'].bonusEndBlock,
    ],
  })
  await save('MasterChef', masterChef)
  console.log('MasterChef:', masterChef.address)

  const lpAddr = await read('StableSwap', 'lp')
  console.log('lpAddr', lpAddr)
}

module.exports.tags = ['StableSwap']
module.exports.dependencies = ['SS']
module.exports.runAtTheEnd = true
