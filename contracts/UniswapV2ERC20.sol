pragma solidity =0.5.16;

import './interfaces/IUniswapV2ERC20.sol';
import './libraries/SafeMath.sol';

contract UniswapV2ERC20 is IUniswapV2ERC20 {
    using SafeMath for uint;

    string public constant name = 'Uniswap V2';
    string public constant symbol = 'UNI-V2';
    uint8 public constant decimals = 18;
    uint  public totalSupply;//总供应量
    mapping(address => uint) public balanceOf;//账户余额
    mapping(address => mapping(address => uint)) public allowance;//账户允许者使用数量

    bytes32 public DOMAIN_SEPARATOR;
    //定义PERMIT_TYPEHASH方法,这个方法会返回[EIP2612](EIP-2612: permit – 712-signed approvals)所规定的链下信息加密的类型
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    //定义nonces方法，这个方法会返回EIP2612所规定每次授权的信息中所携带的nonce值是多少，可以方式授权过程遭受到重放攻击
    mapping(address => uint) public nonces;//账户nonce

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    constructor() public {
        uint chainId;
        assembly {
            // 内联汇编，获取链的标识
            chainId := chainid
        }
        //https://eips.ethereum.org/EIPS/eip-712
        //https://zhuanlan.zhihu.com/p/40596830
        //定义DOMAIN_SEPARATOR方法，这个方法会返回[EIP712](EIP-712: Ethereum typed structured data hashing and signing)所规定的DOMAIN_SEPARATOR值
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }
    //挖币
    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }
    //销毁币
    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }
    //授权
    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }
    //转移
    function _transfer(address from, address to, uint value) private {
        //没有check from的账户余额是否足够
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }
    //授权
    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }
    //转账
    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }
    //自转账，或授权者转账
    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != uint(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }
    // permit授权方法 该方法的参数具体含义可以查询[EIP2612](EIP-2612: permit – 712-signed approvals)中的定义。
    // 零gas以太坊交易实现原理及源码:https://zhuanlan.zhihu.com/p/269226515
    // https://github.com/Donaldhan/ERC20Permit
    //通过链下签名授权实现更少 Gas 的 ERC20代币:https://zhuanlan.zhihu.com/p/268699937
    //https://eips.ethereum.org/EIPS/eip-2612
    // https://github.com/makerdao/dss/blob/master/src/dai.sol
    // 用户线下签名，授权代理服务商线上授权（服务商需要线上数据验证，用户需要使用相同方法进行线上验证）
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        //大于当前时间戳
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');
        //abi.encodePacked(...) returns (bytes)：对给定参数执行 紧打包编码
        //
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        //ecrecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) returns (address)：基于椭圆曲线签名找回与指定公钥关联的地址，发生错误的时候返回 0
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}
