module.exports = {
  swapMining: {
    rewardPerBlock: 2,
    startBlock: 0,
    bonusEndBlock: 100,
  },
  masterChef: {
    rewardPerBlock: 2,
    startBlock: 0,
    bonusEndBlock: 100,
  },
}

module.exports.skip = () => Promise.resolve(true)
