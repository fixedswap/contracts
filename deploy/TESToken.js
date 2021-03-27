module.exports = async function ({ deployments, getNamedAccounts }) {
  const { deploy, save } = deployments

  const { deployer } = await getNamedAccounts()

  await save(
    'USDT',
    await deploy('TokenERC20', {
      from: deployer,
      log: true,
      deterministicDeployment: false,
      args: ['Tether USD', 'USDT', '6'],
    })
  )
  await save(
    'USDC',
    await deploy('TokenERC20', {
      from: deployer,
      log: true,
      deterministicDeployment: false,
      args: ['USD Coin', 'USDC', '6'],
    })
  )
  await save(
    'DAI',
    await deploy('TokenERC20', {
      from: deployer,
      log: true,
      deterministicDeployment: false,
      args: ['Dai Stablecoin', 'DAI', '18'],
    })
  )
}

module.exports.tags = ['TESToken']
