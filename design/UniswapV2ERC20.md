 UniswapV2ERC20提供常规ERC20的规范操作，同时提供了eip-2612的permit实现。

 ## eip-712
 定义DOMAIN_SEPARATOR方法，这个方法会返回[EIP712](EIP-712: Ethereum typed structured data hashing and signing)所规定的DOMAIN_SEPARATOR值

 [eip-712](https://eips.ethereum.org/EIPS/eip-712)     
 [eip-712 cn](https://zhuanlan.zhihu.com/p/40596830)  
  
## EIP2612


permit授权方法 该方法的参数具体含义可以查询[EIP2612](EIP-2612: permit – 712-signed approvals)中的定义。
用户线下签名，授权代理服务商线上授权（服务商需要线上数据验证，用户需要使用相同方法进行线上验证）, 用户可以零gas交易，实际转嫁给服务商；


[eip-2612](https://eips.ethereum.org/EIPS/eip-2612)  
[零gas以太坊交易实现原理及源码](https://zhuanlan.zhihu.com/p/26922651)  
[ERC20Permit](https://github.com/Donaldhan/ERC20Permit)   
[makerdao dai](https://github.com/makerdao/dss/blob/master/src/dai.sol)     
[通过链下签名授权实现更少 Gas 的 ERC20代币](https://zhuanlan.zhihu.com/p/268699937)  


