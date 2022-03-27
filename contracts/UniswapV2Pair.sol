pragma solidity =0.5.16;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;
    //最小流动性的定义是1000
    uint public constant MINIMUM_LIQUIDITY = 10**3;
    //转账方法签名
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;//工厂地址 因为pair合约是通过工厂合约进行部署的，所有会有一个变量专门存放工厂合约的地址
    //token地址 pair合约的含义，就是一对token，所有在合约中会存放两个token的地址，便于调用
    address public token0;
    address public token1;
    /*
    * 储备量是当前pair合约所持有的token数量，
    * blockTimestampLast主要用于判断是不是区块的第一笔交易。reserve0、reserve1和blockTimestampLast三者的位数加起来正好是uint的位数。
    */
    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    //价格最后累计，是用于Uniswap v2所提供的价格预言机上，该数值会在每个区块的第一笔交易进行更新
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    /*
    * kLast这个变量在没有开启收费的时候，是等于0的，
    * 只有当开启平台收费的时候，这个值才等于k值，因为一般开启平台收费，那么k值就不会一直等于两个储备量向乘的结果来
    */
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event
    // 锁定变量，防止重入
    uint private unlocked = 1;
    /*
    * @dev 修饰方法，锁定运行防止重入
    */
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }
    // token0的储备量，token1的储备量，blockTimestampLast：上一个区块的时间戳。
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }
    //转账
    function _safeTransfer(address token, address to, uint value) private {
        //使用call方法的优势在于可以在不知道token合约具体代码的前提下调用其方法。
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
    }
    //铸造事件
    event Mint(address indexed sender, uint amount0, uint amount1);
    //销毁事件
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    //交换事件
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    //同步事件
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() public {
        factory = msg.sender;
    }
    /**
    * initialze方法是Solidity中一个比较特殊的方法，它仅仅只有在合约创建之后调用一次，为什么使用initialze方法初始化pair合约而不是在构造函数中初始化，
    * 这是因为pair合约是通过create2部署的，create2部署合约的特点就在于部署合约的地址是可预测的，并且后一次部署的合约可以把前一次部署的合约给覆盖，这样可以实现合约的升级。
    * 如果想要实现升级，就需要构造函数不能有任何参数，这样才能让每次部署的地址都保持一致，具体细节可以查看create2的文档。 在这个initialize方法中，主要是将两个token的地址分别赋予。
     */
    // called once by the factory at time of deployment
    //在工厂合约部署时，调用只调一次
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }
     /** 
      * 私有更新储备量方法主要用于每次添加流动性或者减少流动性之后调用，用于将余额同步给储备量。
      * 并且会判断时间流逝，在每一个区块的第一次调用时候，更新价格累加器，用于Uniswap v2的价格预言机。
      *   update reserves and, on the first call per block, price accumulators
      */
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        // 确认余额0和余额1小于等于最大的uint112
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW');
         // 区块时间戳，将时间戳转换成uint32
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
         // 计算时间流逝
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
         // 如果时间流逝>0，并且储备量0、1不等于0，也就是第一个调用
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            // 价格0最后累计 += 储备量1 * 2**112 / 储备量0 * 时间流逝
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            // 价格1最后累计 += 储备量0 * 2**112 / 储备量1 * 时间流逝
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        // 余额0，1放入储备量0，1
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        // 更新最后时间戳
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }
    /**
     *  
     */ 
    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                 // 计算（_reserve0*_reserve1）的平方根
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                // 计算k值的平方根
                uint rootKLast = Math.sqrt(_kLast);
                 // 如果rootK>rootKLast
                if (rootK > rootKLast) {
                    // 分子 = erc20总量 * (rootK - rootKLast)
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                     // 分母 = rootK * 5 + rootKLast
                    uint denominator = rootK.mul(5).add(rootKLast);
                    // 流动性 = 分子 / 分母
                    uint liquidity = numerator / denominator;
                    //  如果流动性 > 0 将流动性铸造给feeTo地址
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }
    /**
     * mint函数的输入为一个地址to,输出为该地址所提供的流动性，在Uniswap中，流动性也被体现成token即LP token。 
     * 铸币流程发生在router合约向pair合约发送代币之后，因此此次的储备量和合约的token余额是不相等的，中间的差值就是需要铸币的token金额，即amount0和amount1
     */
    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        //获取pair，token0和token1的储备量
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        //获取pair在token0和token1的余额
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);
        
        //获取铸造费开关， 需要则，将流动性铸造给feeTo地址
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            // 流动性 = （数量0 * 数量1）的平方根 - 最小流动性1000
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
             // 在总量为0的初始状态，永久锁定最低流动性
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            // 流动性 = 最小值（amount0 * _totalSupply / _reserve0 和 (amount1 * _totalSupply) / reserve1）
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        // 铸造流动性给to地址
        _mint(to, liquidity);
        //更新储备量 
        _update(balance0, balance1, _reserve0, _reserve1);
        //计算新的K值
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }
    //流动性的提供者想要收回流动性，那么就需要调用该方法
    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
          // 获取储备量0，储备量1
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        // 带入变量
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        // 获取当前合约在token0,token1合约内的余额                           
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        // 从当前合约的balanceOf映射中获取当前合约自身流动性数量
        // 当前合约的余额是用户通过路由合约发送到pair合约要销毁的金额
        uint liquidity = balanceOf[address(this)];
        // 返回铸造费开关
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
         // amount0和amount1是用户能取出来多少的数额
        // amount0 = 流动性数量 * 余额0 / totalSupply 使用余额确保按比例分配
        // 取出来的时候包含了很多个千分之三的手续费
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
         // 确认amount0和amount1都大于0
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        // 销毁当前合约内的流动性数量
        _burn(address(this), liquidity);
         // 将amount0数量的_token0发送给to地址
        _safeTransfer(_token0, to, amount0);
         // 将amount1数量的_toekn1发给to地址
        _safeTransfer(_token1, to, amount1);
         // 更新balance0和balance1
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        //更新储备量
        _update(balance0, balance1, _reserve0, _reserve1);
        //记录kLast
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }
    /**
     * 交换token方法一般通过路由合约调用，功能是交换token，
     * 需要的参数包括：amount0Out：token0要交换出的数额；
     * amount1Out：token1要交换出的数额，to：交换token要发到的地址，一般是其它pair合约地址；data用于闪电贷回调使用。 
     */
    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        // 确保amount0Out、amount1Out至少0
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        // 确保取出的量不能大于它的 储备量
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
         // 标记_toekn{0,1}的作用域，避免堆栈太深
        address _token0 = token0;
        address _token1 = token1;
        // 确保to地址不等于token0和token1的地址
        require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
        // 发送token0代币
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        // 发送token1代币
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        // 闪电贷
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        // 余额0，1 = 当前合约在token0，1合约内的余额
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }
        // 如果余额0 > 大于储备0 - amount0Out 则 amount0In = 余额0 - （储备0 - amount0Out） 否则amount0In = 0
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        // // 确保输入数量0｜｜1大于0
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        { 
        //
        // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        // 调整后的余额0 = 余额0 * 1000 - （amount0In * 3）
        uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
         // 调整后的余额1 = 余额1 * 1000 - （amount1In * 3)
        uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
        // 确保balance0Adjusted * balance1Adjusted >= 储备0 * 储备1 * 1000000
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
        }
        // 更新储备量
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
    //skim方法的功能是强制让余额等于储备量，一般用于储备量溢出的情况下，将多余的余额转出到address(to)上，使余额重新等于储备量
    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
         // 将当前合约在token1,2的余额-储备量0，1安全发送到to地址上
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }
    //sync方法则是强制让储备量与余额对等，直接调用就是更新储备量的私有方法 
    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
