// SPDX-License-Identifier: MIT

pragma solidity 0.6.2;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "./TokenERC20.sol";

interface ISwapMining {
    function swap(address account, uint256 amount) external returns (bool);
}

contract StableSwap is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // stable coin whitelist.
    EnumerableSet.AddressSet private _whitelist;
    // balance of each stable token.
    mapping(address => uint256) public balanceOf;
    // swap path used by feedback.
    address[] public feedbackPath;

    // address of the SS LP token.
    TokenERC20 public lp;
    // address of the SS token.
    TokenERC20 public ss;
    // address of swap router.
    IUniswapV2Router02 public router;
    // swap mining address.
    ISwapMining public swapMining;

    // swap fee.
    uint256 public fee;

    event Deposit(
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint256 liquidity,
        address to
    );
    event Withdraw(
        address indexed sender,
        address[] tokens,
        uint256[] amounts,
        uint256 liquidity,
        address to
    );
    event Swap(
        address indexed sender,
        address indexed source,
        address indexed target,
        uint256 amountIn,
        uint256 amountOut,
        uint256 amountFeedback,
        address to
    );

    modifier inWhitelist(address _target) {
        require(
            _whitelist.contains(_target),
            "StableSwap: whitelist doesn't contain token"
        );
        _;
    }

    constructor(
        address _ss,
        address _lp,
        address _router,
        address _swapMining,
        address[] memory _path
    ) public Ownable() {
        require(_ss != address(0), "StableSwap: ss is the zero address");
        require(
            _router != address(0),
            "StableSwap: router is the zero address"
        );
        require(
            _swapMining != address(0),
            "StableSwap: swapMining is the zero address"
        );
        require(
            _path.length >= 2 && _path[_path.length - 1] == _ss,
            "StableSwap: invalid token path"
        );
        // if _lp isn't 0x000..., please make sure this contract has the mint role and the default admin role of _lp!
        lp = _lp == address(0)
            ? new TokenERC20("Stable Swap LP", "SSLP", 18)
            : TokenERC20(_lp);
        ss = TokenERC20(_ss);
        router = IUniswapV2Router02(_router);
        swapMining = ISwapMining(_swapMining);
        feedbackPath = _path;
    }

    // update router.
    function setRouter(address _router) external onlyOwner {
        require(
            _router != address(0),
            "StableSwap: router is the zero address"
        );
        router = IUniswapV2Router02(_router);
    }

    // pause and unPause
    function pause() external virtual onlyOwner {
        _pause();
    }

    function unpause() external virtual onlyOwner {
        _unpause();
    }

    // update fee.
    function setFee(uint256 _fee) external onlyOwner {
        require(_fee <= 10000, "StableSwap: fee is too large");
        fee = _fee;
    }

    // update path for token.
    function setPath(address[] calldata _path) external onlyOwner {
        require(
            _path.length >= 2 &&
                _whitelist.contains(_path[0]) &&
                _path[_path.length - 1] == address(ss),
            "StableSwap: invalid token path"
        );
        feedbackPath = _path;
    }

    function getPathLength() external view returns (uint256) {
        return feedbackPath.length;
    }

    // operate whitelist.
    function addWhitelist(address _token) external onlyOwner returns (bool) {
        require(_token != address(0), "StableSwap: token is the zero address");
        require(
            ERC20(_token).decimals() <= 18,
            "StableSwap: invalid token decimals"
        );
        ERC20(_token).safeApprove(address(router), uint256(-1));
        return _whitelist.add(_token);
    }

    function getWhitelistLength() external view returns (uint256) {
        return _whitelist.length();
    }

    function isWhitelist(address _token) external view returns (bool) {
        return _whitelist.contains(_token);
    }

    function getWhitelist(uint256 _index) external view returns (address) {
        require(
            _index <= _whitelist.length() - 1,
            "StableSwap: index out of bounds"
        );
        return _whitelist.at(_index);
    }

    // core logic.
    function _getLiquidityAmount(address _target, uint256 _amount)
        private
        view
        returns (uint256 liquidity)
    {
        liquidity = _amount;
        uint8 decimals = ERC20(_target).decimals();
        if (decimals < 18) {
            liquidity = liquidity.mul(10**uint256(18 - decimals));
        }
    }

    function _getTokenAmount(address _target, uint256 _liquidity)
        private
        view
        returns (uint256 amount)
    {
        amount = _liquidity;
        uint8 decimals = ERC20(_target).decimals();
        if (decimals < 18) {
            amount = amount.div(10**uint256(18 - decimals));
        }
    }

    function deposit(
        address _target,
        uint256 _amount,
        address _to
    ) external whenNotPaused nonReentrant inWhitelist(_target) {
        require(_to != address(this), "StableSwap: invalid address");
        ERC20(_target).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 liquidity = _getLiquidityAmount(_target, _amount);
        balanceOf[_target] = balanceOf[_target].add(liquidity);
        lp.mint(_to, liquidity);
        emit Deposit(msg.sender, _target, _amount, liquidity, _to);
    }

    function withdraw(uint256 _liquidity, address _to) external nonReentrant {
        require(_to != address(this), "StableSwap: invalid address");
        require(
            _liquidity > 0 && lp.balanceOf(msg.sender) >= _liquidity,
            "StableSwap: insufficient balance"
        );
        uint256 totalSupply = lp.totalSupply();
        require(totalSupply > 0, "StableSwap: insufficient totalSupply");
        uint256 length = _whitelist.length();
        address[] memory tokens = new address[](length);
        uint256[] memory amounts = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            uint256 amount = 0;
            address target = _whitelist.at(i);
            uint256 targetBalance = balanceOf[target];
            uint256 targetLiquidity =
                _liquidity.mul(targetBalance).div(totalSupply);
            if (targetLiquidity > 0) {
                amount = _getTokenAmount(target, targetLiquidity);
                ERC20(target).safeTransfer(_to, amount);
                balanceOf[target] = targetBalance.sub(targetLiquidity);
            }
            tokens[i] = target;
            amounts[i] = amount;
        }
        lp.burnFrom(msg.sender, _liquidity);
        emit Withdraw(msg.sender, tokens, amounts, _liquidity, _to);
    }

    function skim(address _to) external whenNotPaused nonReentrant {
        require(_to != address(this), "StableSwap: invalid address");
        // skim each stable token.
        uint256 length = _whitelist.length();
        for (uint256 i = 0; i < length; i++) {
            address target = _whitelist.at(i);
            uint256 amount =
                ERC20(target).balanceOf(address(this)).sub(
                    _getTokenAmount(target, balanceOf[target])
                );
            if (amount > 0) {
                ERC20(target).safeTransfer(_to, amount);
            }
        }
        // skim ss.
        uint256 amount = ss.balanceOf(address(this));
        if (amount > 0) {
            ss.transfer(_to, amount);
        }
    }

    function _getSwapResult(
        address _source,
        address _target,
        uint256 _amount,
        bool _calcFee
    )
        private
        view
        returns (
            uint256 liquidity,
            uint256 amount,
            uint256 amountFee,
            uint256 amountOut
        )
    {
        require(_source != _target, "StableSwap: identical token address");
        liquidity = _getLiquidityAmount(_source, _amount);
        amount = _getTokenAmount(_target, liquidity);
        amountFee = _calcFee && fee > 0 ? amount.mul(fee).div(10000) : 0;
        amountOut = amount.sub(amountFee);
    }

    function getSwapResult(
        address _source,
        address _target,
        uint256 _amount
    )
        external
        view
        inWhitelist(_source)
        inWhitelist(_target)
        returns (
            uint256 liquidity,
            uint256 amountFee,
            uint256 amountOut,
            uint256 amountFeedbackSS
        )
    {
        (liquidity, , amountFee, amountOut) = _getSwapResult(
            _source,
            _target,
            _amount,
            true
        );
        if (amountFee > 0) {
            address[] memory path = feedbackPath;
            address tokenFeedback = path[0];
            uint256 amountFeedback = amountFee;
            if (_target != tokenFeedback) {
                (, , , amountFeedback) = _getSwapResult(
                    _target,
                    tokenFeedback,
                    amountFee,
                    false
                );
            }
            if (amountFeedback > 0) {
                uint256[] memory amounts =
                    router.getAmountsOut(amountFeedback, path);
                require(
                    path.length == amounts.length &&
                        amounts[0] == amountFeedback,
                    "StableSwap: swap failed, unequal length or feedback amount"
                );
                amountFeedbackSS = amounts[amounts.length - 1];
            }
        }
    }

    function _swap(
        address _source,
        address _target,
        uint256 _amount,
        address _to
    )
        private
        returns (
            uint256 liquidity,
            uint256 amount,
            uint256 amountFee,
            uint256 amountOut
        )
    {
        bool internalCall = _to == address(this);
        (liquidity, amount, amountFee, amountOut) = _getSwapResult(
            _source,
            _target,
            _amount,
            !internalCall
        );
        uint256 targetBalance = balanceOf[_target];
        require(
            targetBalance >= liquidity &&
                ERC20(_target).balanceOf(address(this)) >= amount,
            "StableSwap: insufficient target balance"
        );
        if (!internalCall) {
            ERC20(_source).safeTransferFrom(msg.sender, address(this), _amount);
            ERC20(_target).safeTransfer(_to, amountOut);
        }
        balanceOf[_source] = balanceOf[_source].add(liquidity);
        balanceOf[_target] = targetBalance.sub(liquidity);
    }

    function _abs(uint256 num1, uint256 num2)
        private
        pure
        returns (uint256 abs)
    {
        abs = num1 > num2 ? num1.sub(num2) : num2.sub(num1);
    }

    function swap(
        address _source,
        address _target,
        uint256 _amount,
        address _to
    )
        external
        whenNotPaused
        nonReentrant
        inWhitelist(_source)
        inWhitelist(_target)
        returns (
            uint256 liquidity,
            uint256 amountFee,
            uint256 amountOut,
            uint256 amountFeedbackSS
        )
    {
        require(_to != address(this), "StableSwap: invalid address");
        // get the absolute value difference before swap.
        uint256 differenceBeforeSwap =
            _abs(balanceOf[_source], balanceOf[_target]);
        (liquidity, , amountFee, amountOut) = _swap(
            _source,
            _target,
            _amount,
            _to
        );
        if (amountFee > 0) {
            address[] memory path = feedbackPath;
            address tokenFeedback = path[0];
            uint256 amountFeedback = amountFee;
            if (_target != tokenFeedback) {
                (, , , amountFeedback) = _swap(
                    _target,
                    tokenFeedback,
                    amountFee,
                    address(this)
                );
            }
            if (amountFeedback > 0) {
                uint256[] memory amounts =
                    router.swapExactTokensForTokens(
                        amountFeedback,
                        0,
                        path,
                        address(this),
                        block.timestamp
                    );
                require(
                    path.length == amounts.length &&
                        amounts[0] == amountFeedback,
                    "StableSwap: swap failed, unequal length or feedback amount"
                );
                amountFeedbackSS = amounts[amounts.length - 1];
                if (amountFeedbackSS > 0) {
                    ss.burn(amountFeedbackSS);
                }
            }
        }
        // get the absolute value difference after swap.
        uint256 differenceAfterSwap =
            _abs(balanceOf[_source], balanceOf[_target]);
        if (differenceBeforeSwap > differenceAfterSwap) {
            swapMining.swap(
                msg.sender,
                differenceBeforeSwap.sub(differenceAfterSwap)
            );
        }
        emit Swap(
            msg.sender,
            _source,
            _target,
            _amount,
            amountOut,
            amountFeedbackSS,
            _to
        );
    }
}
