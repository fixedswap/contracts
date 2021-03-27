module.exports = async function ({ deployments, getNamedAccounts }) {
  const { deploy, save } = deployments
  const { deployer } = await getNamedAccounts()
  const ss = await deploy('TokenERC20', {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    args: ['StableSwap', 'SS', '18'],
  })
  await save('SS', ss)
  console.log('SS:', ss.address)
}

module.exports.tags = ['SS']
