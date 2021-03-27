// Copy from MDEX
// SPDX-License-Identifier: MIT

pragma solidity 0.6.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./TokenERC20.sol";

contract SwapMining is Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _whitelist;

    // SS tokens created per block
    uint256 public ssPerBlock;
    // The block number when SS mining starts.
    uint256 public startBlock;
    // Total allocation points
    uint256 public totalAllocPoint = 0;
    // ss token address
    TokenERC20 public ss;
    // pair corresponding pid
    mapping(address => uint256) public pairOfPid;
    // Block number when bonus SUSHI period ends.
    uint256 public bonusEndBlock;
    // Bonus muliplier for early ss makers.
    uint256 public constant BONUS_MULTIPLIER = 5;

    constructor(
        TokenERC20 _ss,
        uint256 _ssPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        ss = _ss;
        ssPerBlock = _ssPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
    }

    struct UserInfo {
        uint256 quantity; // How many LP tokens the user has provided
        uint256 blockNumber; // Last transaction block
    }

    struct PoolInfo {
        address router; // Router address
        uint256 quantity; // Current amount of LPs
        uint256 totalQuantity; // All quantity
        uint256 allocPoint; // How many allocation points assigned to this pool
        uint256 allocSSAmount; // How many SSs
        uint256 lastRewardBlock; // Last transaction block
    }

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function _sortTokens(address _source, address _target)
        private
        pure
        returns (address source, address target)
    {
        (source, target) = _source < _target
            ? (_source, _target)
            : (_target, _source);
    }

    function addPair(
        uint256 _allocPoint,
        address _router,
        bool _withUpdate
    ) public onlyOwner {
        require(
            _router != address(0),
            "SwapMining: _router is the zero address"
        );
        if (_withUpdate) {
            massMintPools();
        }
        // add router address to whitelist
        if (!EnumerableSet.contains(_whitelist, _router)) {
            EnumerableSet.add(_whitelist, _router);
        }
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                router: _router,
                quantity: 0,
                totalQuantity: 0,
                allocPoint: _allocPoint,
                allocSSAmount: 0,
                lastRewardBlock: lastRewardBlock
            })
        );
        pairOfPid[_router] = poolLength() - 1;
    }

    // Update the allocPoint of the pool
    function setPair(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massMintPools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Set the number of ss produced by each block
    function setSSPerBlock(uint256 _newPerBlock) public onlyOwner {
        massMintPools();
        ssPerBlock = _newPerBlock;
    }

    // Only tokens in the whitelist can be mined SS
    function addWhitelist(address _addToken) public onlyOwner returns (bool) {
        require(
            _addToken != address(0),
            "SwapMining: token is the zero address"
        );
        return EnumerableSet.add(_whitelist, _addToken);
    }

    function delWhitelist(address _delToken) public onlyOwner returns (bool) {
        require(
            _delToken != address(0),
            "SwapMining: token is the zero address"
        );
        return EnumerableSet.remove(_whitelist, _delToken);
    }

    function getWhitelistLength() public view returns (uint256) {
        return EnumerableSet.length(_whitelist);
    }

    function isWhitelist(address _token) public view returns (bool) {
        return EnumerableSet.contains(_whitelist, _token);
    }

    function getWhitelist(uint256 _index) public view returns (address) {
        require(
            _index <= getWhitelistLength() - 1,
            "SwapMining: index out of bounds"
        );
        return EnumerableSet.at(_whitelist, _index);
    }

    // Rewards for the current block
    function getSSReward(uint256 _lastRewardBlock)
        public
        view
        returns (uint256)
    {
        require(
            _lastRewardBlock <= block.number,
            "SwapMining: must little than the current block number"
        );
        return getMultiplier(_lastRewardBlock, block.number).mul(ssPerBlock);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return
                bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                    _to.sub(bonusEndBlock)
                );
        }
    }

    // Update all pools Called when updating allocPoint and setting new blocks
    function massMintPools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            mint(pid);
        }
    }

    function mint(uint256 _pid) public returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return false;
        }
        uint256 blockReward = getSSReward(pool.lastRewardBlock);
        if (blockReward <= 0) {
            return false;
        }
        // Calculate the rewards obtained by the pool based on the allocPoint
        uint256 ssReward =
            blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        ss.mint(address(this), ssReward);
        // Increase the number of tokens in the current pool
        pool.allocSSAmount = pool.allocSSAmount.add(ssReward);
        pool.lastRewardBlock = block.number;
        return true;
    }

    // swapMining only router
    function swap(address account, uint256 amount) external returns (bool) {
        require(
            account != address(0),
            "SwapMining: taker swap account is the zero address"
        );

        if (poolLength() <= 0) {
            return false;
        }

        if (!isWhitelist(msg.sender)) {
            return false;
        }

        if (amount <= 0) {
            return false;
        }

        uint256 pid = pairOfPid[msg.sender];
        PoolInfo storage pool = poolInfo[pid];
        // If it does not exist or the allocPoint is 0 then return
        if (pool.allocPoint <= 0) {
            return false;
        }

        if (pool.router != msg.sender) {
            return false;
        }

        mint(pid);

        pool.quantity = pool.quantity.add(amount);
        pool.totalQuantity = pool.totalQuantity.add(amount);
        UserInfo storage user = userInfo[pid][account];
        user.quantity = user.quantity.add(amount);
        user.blockNumber = block.number;
        return true;
    }

    // The user withdraws all the transaction rewards of the pool
    function takerWithdraw() public {
        uint256 userSub;
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][msg.sender];
            if (user.quantity > 0) {
                mint(pid);
                // The reward held by the user in this pool
                uint256 userReward =
                    pool.allocSSAmount.mul(user.quantity).div(pool.quantity);
                pool.quantity = pool.quantity.sub(user.quantity);
                pool.allocSSAmount = pool.allocSSAmount.sub(userReward);
                user.quantity = 0;
                user.blockNumber = block.number;
                userSub = userSub.add(userReward);
            }
        }
        if (userSub <= 0) {
            return;
        }
        ss.transfer(msg.sender, userSub);
    }

    // Get rewards from users in the current pool
    function getUserReward(uint256 _pid)
        public
        view
        returns (uint256, uint256)
    {
        require(_pid <= poolInfo.length - 1, "SwapMining: Not find this pool");
        uint256 userSub;
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][msg.sender];
        if (user.quantity > 0) {
            uint256 blockReward = getSSReward(pool.lastRewardBlock);
            uint256 ssReward =
                blockReward.mul(pool.allocPoint).div(totalAllocPoint);
            userSub = userSub.add(
                (pool.allocSSAmount.add(ssReward)).mul(user.quantity).div(
                    pool.quantity
                )
            );
        }
        //SS available to users, User transaction amount
        return (userSub, user.quantity);
    }

    // Get details of the pool
    function getPoolInfo(uint256 _pid)
        public
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        require(_pid <= poolInfo.length - 1, "SwapMining: Not find this pool");
        PoolInfo memory pool = poolInfo[_pid];
        uint256 ssAmount = pool.allocSSAmount;
        uint256 blockReward = getSSReward(pool.lastRewardBlock);
        uint256 ssReward =
            blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        ssAmount = ssAmount.add(ssReward);
        //router,Pool remaining reward,Total /Current transaction volume of the pool
        return (
            pool.router,
            ssAmount,
            pool.totalQuantity,
            pool.quantity,
            pool.allocPoint
        );
    }
}
