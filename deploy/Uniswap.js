module.exports = async function ({ deployments, getNamedAccounts }) {
  const { deploy, save } = deployments

  const { deployer } = await getNamedAccounts()

  const factory = await deploy('UniswapV2Factory', {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    args: [deployer],
  })

  const weth = await deploy('WETH9', {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    args: [],
  })

  const router = await deploy('UniswapV2Router02', {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    args: [factory.address, weth.address],
  })
  await save('Router', router)
  console.log('Router:', router.address)
}

module.exports.tags = ['TESTUniswap']
