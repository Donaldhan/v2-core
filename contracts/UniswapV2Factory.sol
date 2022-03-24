pragma solidity =0.5.16;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';

contract UniswapV2Factory is IUniswapV2Factory {
    /**
     * 平台手续费相关与平台手续费相关有两个变量，均是address，
     * 其中address(feeTo)表示平台手续费收取的地址，address(feeToSetter)则表示可设置平台手续费收取地址的地址
     */
    address public feeTo;
    address public feeToSetter;
    /**
     * Pair合约相关
     * 与Pair合约相关有两个变量，其中变量getPair的类型是map,存放Pair合约两个token与Pair合约的地址，
     * 格式为address => (address => address)。变量allPairs存放所有Pair合约的地址 
     */
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    //Pair创建事件
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }
    /**
     *  create2(v, n, p, s)
     *  用 mem[p...(p + s)) 中的代码，在地址 keccak256(<address> . n . keccak256(mem[p...(p + s))) 上 创建新合约、发送 v wei 并返回新地址 
     *  部署Pair合约使用的是create2方法，使用该方法部署合约可以固定这个合约的地址，使这个合约的地址可预测，这样便于Router合约不进行任何调用，就可以计算得到Pair合约的地址。
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        //初始化UniswapV2Pair的字节码变量
        // bytecode为合约经过编译之后的源代码
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        //// 将token0和token1打包后创建哈希
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        //// 内联汇编
        assembly {
            // 通过create2方法布置合约，并且加salt，返回合约的地址是固定的，可预测的
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        // 调用pair地址的合约的`initialine`方法，传入变量token0和token1
        IUniswapV2Pair(pair).initialize(token0, token1);
         // 配对映射中设置token0=>token1 = pair
        getPair[token0][token1] = pair;
        // 配对映射中设置token1=>token0 = pair
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
         // 配对数组中推入pair地址
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
    //设置平台手续费收取地址 
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }
    //平台手续费收取权限账户
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
