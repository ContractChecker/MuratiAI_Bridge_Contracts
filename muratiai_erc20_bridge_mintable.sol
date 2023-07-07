// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function mint(address to, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            codehash := extcodehash(account)
        }
        return (codehash != accountHash && codehash != 0x0);
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
    }

    function functionCall(
        address target,
        bytes memory data
    ) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return
            functionCallWithValue(
                target,
                data,
                value,
                "Address: low-level call with value failed"
            );
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(
            address(this).balance >= value,
            "Address: insufficient balance for call"
        );
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(
        address target,
        bytes memory data,
        uint256 weiValue,
        string memory errorMessage
    ) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: weiValue}(
            data
        );
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _transferOwnership(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract MURATIAI_ERC20_BRIDGE is Context, Ownable {
    using Address for address;

    struct Fees {
        mapping(uint256 => uint256) fee;
        mapping(uint256 => uint256) tax;
        address feeReceiver;
    }

    string private _name = "MURATIAI ERC20 Bridge";
    string private _symbol = "MURATIAI ERC20 Bridge";

    address payable public feeReceiver;
    uint256 public bridgeFee;
    uint256 public bridgeTax;
    uint256 public bridgeActivationTime;

    mapping(uint256 => mapping(uint256 => uint256)) public validNonce;
    mapping(uint256 => uint256) public nonces;

    mapping(address => bool) public isOperator;
    mapping(address => bool) public excludedFromRestrictions;

    mapping(address => bool) public isAllowedToken;
    mapping(address => mapping(uint256 => address)) public tokenToBridge;
    address[] public allowedTokens;
    mapping(address => Fees) public fees;
    mapping(address => uint256) public bridgeLimits;

    bool public isBridgeActive = false;

    modifier onlyBridgeActive() {
        if (!excludedFromRestrictions[msg.sender]) {
            require(isBridgeActive, "Bridge is not active");
        }
        _;
    }

    modifier onlyOperator() {
        require(
            isOperator[msg.sender] == true,
            "Error: Caller is not the operator!"
        );
        _;
    }

    event Crossed(
        address indexed sender,
        address indexed tokenFrom,
        address indexed tokenTo,
        uint256 value,
        uint256 fromChainID,
        uint256 chainID,
        uint256 nonce
    );

    constructor(address payable _feeReceiver) {
        feeReceiver = _feeReceiver;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function setBridgeFee(uint256 _bridgeFee) external onlyOwner {
        bridgeFee = _bridgeFee;
    }

    function setBridgeTax(uint256 _bridgeTax) external onlyOwner {
        bridgeTax = _bridgeTax;
    }

    function setFee(
        address _token,
        uint256 _chainID,
        uint256 _fee,
        uint256 _tax,
        address fee_receiver
    ) external onlyOwner {
        fees[_token].fee[_chainID] = _fee;
        fees[_token].tax[_chainID] = _tax;
        fees[_token].feeReceiver = fee_receiver;
    }

    function setFeeReceiver(address payable _feeReceiver) external onlyOwner {
        feeReceiver = _feeReceiver;
    }

    function setOperator(address _operator, bool _value) external onlyOwner {
        require(isOperator[_operator] != _value, "Error: Already set!");
        isOperator[_operator] = _value;
    }

    function setExcludeFromRestrictions(
        address _user,
        bool _value
    ) external onlyOwner {
        require(
            excludedFromRestrictions[_user] != _value,
            "Error: Already set!"
        );
        excludedFromRestrictions[_user] = _value;
    }

    function setBridgeActive(bool _isBridgeActive) external onlyOwner {
        if (bridgeActivationTime == 0) {
            bridgeActivationTime = block.timestamp;
        }
        isBridgeActive = _isBridgeActive;
    }

    function setAllowedToken(address _token, bool _value) external onlyOwner {
        isAllowedToken[_token] = _value;
        if (_value) {
            allowedTokens.push(_token);
        } else {
            for (uint256 i = 0; i < allowedTokens.length; i++) {
                if (allowedTokens[i] == _token) {
                    allowedTokens[i] = allowedTokens[allowedTokens.length - 1];
                    allowedTokens.pop();
                    break;
                }
            }
        }
    }

    function setTokenToBridge(
        address _token,
        uint256 _chainID,
        address _bridge
    ) external onlyOwner {
        tokenToBridge[_token][_chainID] = _bridge;
    }

    function setBridgeLimits(
        address _token,
        uint256 _limit
    ) external onlyOwner {
        bridgeLimits[_token] = _limit;
    }

    function addNewToken(
        address _token,
        uint256 _chainID,
        address _bridge,
        uint256 _fee,
        uint256 _tax,
        address fee_receiver
    ) external onlyOwner {
        isAllowedToken[_token] = true;
        tokenToBridge[_token][_chainID] = _bridge;
        fees[_token].fee[_chainID] = _fee;
        fees[_token].tax[_chainID] = _tax;
        fees[_token].feeReceiver = fee_receiver;
    }

    function getBridgeFee() external view returns (uint256) {
        return bridgeFee;
    }

    function getBridgeTax() external view returns (uint256) {
        return bridgeTax;
    }

    function getTokenFees(
        address _token,
        uint256 _chainID
    ) external view returns (uint256, uint256) {
        return (fees[_token].fee[_chainID], fees[_token].tax[_chainID]);
    }

    function getBridgeActivationTime() external view returns (uint256) {
        return bridgeActivationTime;
    }

    function getNonce(uint256 _chainID) external view returns (uint256) {
        return nonces[_chainID];
    }

    function getValidNonce(
        uint256 _chainID,
        uint256 _nonce
    ) external view returns (uint256) {
        return validNonce[_chainID][_nonce];
    }

    function getIsOperator(address _operator) external view returns (bool) {
        return isOperator[_operator];
    }

    function getIsAllowedToken(address _token) external view returns (bool) {
        return isAllowedToken[_token];
    }

    function getIsAllowedTokens() external view returns (address[] memory) {
        return allowedTokens;
    }

    function getTokenToBridge(
        address _token,
        uint256 _chainID
    ) external view returns (address) {
        return tokenToBridge[_token][_chainID];
    }

    function getIsBridgeActive() external view returns (bool) {
        return isBridgeActive;
    }

    function getExcludedFromRestrictions(
        address _user
    ) external view returns (bool) {
        return excludedFromRestrictions[_user];
    }

    function transfer(
        address receiver,
        address _tokenFrom,
        address _tokenTo,
        uint256 amount,
        uint256 fromChainID,
        uint256 _txNonce
    ) external onlyOperator {
        require(
            validNonce[fromChainID][_txNonce] == 0,
            "Error: This transfer has been proceed!"
        );
        require(
            tokenToBridge[_tokenTo][fromChainID] == _tokenFrom,
            "Bridge is not set"
        );
        require(isAllowedToken[_tokenTo], "Token is not allowed");
        IERC20(_tokenTo).mint(receiver, amount);
        validNonce[fromChainID][_txNonce] = 1;
    }

    function cross(
        address _token,
        uint256 amount,
        uint256 chainID
    ) external payable onlyBridgeActive {
        require(isAllowedToken[_token], "Token is not allowed");
        require(
            tokenToBridge[_token][chainID] != address(0),
            "Bridge is not set"
        );
        require(
            bridgeLimits[_token] == 0 || amount >= bridgeLimits[_token],
            "Amount is less than bridge limit"
        );
        require(
            IERC20(_token).allowance(_msgSender(), address(this)) >= amount,
            "Not enough allowance"
        );

        IERC20(_token).burnFrom(_msgSender(), amount);
        amount -= handleFee(_token, chainID, amount);

        emit Crossed(
            _msgSender(),
            _token,
            tokenToBridge[_token][chainID],
            amount,
            block.chainid,
            chainID,
            nonces[chainID]
        );
        nonces[chainID] += 1;
    }

    function handleFee(
        address _token,
        uint256 _chainID,
        uint256 amount
    ) internal returns (uint256) {
        uint256 fee = fees[_token].fee[_chainID];
        uint256 tax = fees[_token].tax[_chainID];
        address _feeReceiver = fees[_token].feeReceiver;
        uint256 taxAmount = 0;
        uint256 bridgeTaxAmount = 0;
        require(msg.value >= bridgeFee + fee, "Fee is not enough");
        if (fee > 0) {
            payable(_feeReceiver).transfer(fee);
        }
        if (tax > 0) {
            taxAmount = (amount * tax) / 1000;
            IERC20(_token).mint(_feeReceiver, taxAmount);
        }
        if (bridgeFee > 0) {
            payable(feeReceiver).transfer(bridgeFee);
        }
        if (bridgeTax > 0) {
            bridgeTaxAmount = (amount * bridgeTax) / 1000;
            IERC20(_token).mint(feeReceiver, bridgeTaxAmount);
        }
        if (msg.value > bridgeFee + fee) {
            payable(_msgSender()).transfer(msg.value - (bridgeFee + fee));
        }

        return taxAmount + bridgeTaxAmount;
    }

    function claimStuckBalance() external onlyOwner {
        payable(_msgSender()).transfer(address(this).balance);
    }

    function claimStuckTokens(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).transfer(
            _msgSender(),
            IERC20(tokenAddress).balanceOf(address(this))
        );
    }

    function claimStuckBalanceAmount(uint256 _amount) external onlyOwner {
        require(_amount <= address(this).balance, "Not enough balance");
        payable(_msgSender()).transfer(_amount);
    }

    function claimStuckTokensAmount(
        address tokenAddress,
        uint256 _amount
    ) external onlyOwner {
        IERC20(tokenAddress).transfer(_msgSender(), _amount);
    }

    receive() external payable {}
}
