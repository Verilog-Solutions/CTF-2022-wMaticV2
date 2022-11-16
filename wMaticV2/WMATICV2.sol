// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20} from "./interfaces/IERC20.sol";
import {IWMATIC} from "./interfaces/IWMATIC.sol";
import {IWMATICV2} from "./interfaces/IWMATICV2.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libraries/TransferHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title The core logic for the WMATICV2 contract

contract WMATICV2 is IWMATICV2, ReentrancyGuard, Ownable {
    /*
    ======== Verilog CTF - Web3Dubai Conference @ 2022 =============================== 
    This is our newly designed WMATICV2 token, unlike the old version of the WMATIC
    the new contract will be more stylish with supports of depositing multi MATIC
    derivative assets to convert into WMATICV2 token.

    Scenarios:
    deposit MATIC -> mint WMATICV2 token
    deposit WMATIC -> mint WMATICV2 token
    deposit WMATIC <> WMATICV2 LP -> mint WMATICV2 token (early stage incentive for switching)

    Besides, our team designed a early stage bounty insurance contract to monitor the 
    safety of the WMATICV2. 

    Find your way to hack around ! But I am sure its really safe.
    */

    string public name = "Wrapped Matic Version 2";
    string public symbol = "WMATICV2";
    uint8 public decimals = 18;
    uint256 private _totalSupply;
    uint256 private _balanceOfMatic;
    address public WMATIC;
    address public LP;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(address _wmatic) {
        WMATIC = _wmatic;
    }

    // errors
    error CallFailed();

    receive() external payable {
        _depositMATIC(msg.sender);
    }

    function setLP(address _lpToken) external onlyOwner {
        require(_lpToken != address(0), "NON ZERO ADDRESS");
        LP = _lpToken;
    }

    function depositMATIC() public payable nonReentrant {
        _depositMATIC(msg.sender);
    }

    function depositWMATIC(uint256 amount) external nonReentrant {
        _depositWMATIC(amount);
    }

    ///@notice need to approve both LP token & WMATIC token to the contract
    function depositLP(uint256 amount) external nonReentrant {
        require(LP != address(0), "SET LP");
        require(IERC20(LP).balanceOf(msg.sender) >= amount, "NO ENOUGH BALANCE");
        uint256 beforeBalance = IERC20(LP).balanceOf(address(this));
        IERC20(LP).transferFrom(msg.sender, address(this), amount);
        uint256 afterBalance = IERC20(LP).balanceOf(address(this));
        require(afterBalance - beforeBalance >= amount, "TRANSFER NOT ENOUGH");
        // redeem back WMATIC & WMATICV2 back to user
        IUniswapV2Pair(LP).transferFrom(msg.sender, LP, amount);
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(LP).burn(msg.sender);
        // transfer the WMATIC to this address and convert it to V2
        if (IUniswapV2Pair(LP).token0() == address(this)) {
            // if token0 is WMATICV2 -> amount1 is WMATIC
            _depositWMATIC(amount1);
            transfer(msg.sender, amount0);
        } else {
            // if token0 is WMATIC -> amount1 is WMATICV2
            _depositWMATIC(amount0);
            transfer(msg.sender, amount1);
        }
    }

    function redeem(uint256 amount) public nonReentrant {
        require(balanceOf[msg.sender] >= amount, "NO ENOUGH BALANCE");
        balanceOf[msg.sender] -= amount;
        _totalSupply -= amount;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert CallFailed();
        }
        _updateBalanceOfMatic(amount, false);
        emit Withdrawal(msg.sender, amount);
    }

    function redeemWMATIC(uint256 amount) public nonReentrant {
        require(balanceOf[msg.sender] >= amount, "NO ENOUGH BALANCE");
        balanceOf[msg.sender] -= amount;
        _totalSupply -= amount;
        TransferHelper.safeTransfer(WMATIC, msg.sender, amount);
        _updateBalanceOfMatic(amount, false);
        emit Withdrawal(msg.sender, amount);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balance() external view override returns (uint256) {
        return _balanceOfMatic;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        require(balanceOf[src] >= wad);
        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        emit Transfer(src, dst, wad);
        return true;
    }

    function _depositMATIC(address to) internal {
        if (to != WMATIC) {
            balanceOf[to] += msg.value;
        }
        _totalSupply += msg.value;
        _updateBalanceOfMatic(msg.value, true);
        emit Deposit(to, msg.value);
    }

    function _depositWMATIC(uint256 amount) internal {
        require(IERC20(WMATIC).balanceOf(msg.sender) >= amount, "NO ENOUGH BALANCE");
        uint256 beforeBalance = IERC20(WMATIC).balanceOf(address(this));
        IERC20(WMATIC).transferFrom(msg.sender, address(this), amount);
        uint256 afterBalance = IERC20(WMATIC).balanceOf(address(this));
        require(afterBalance - beforeBalance >= amount, "TRANSFER NOT ENOUGH");
        balanceOf[msg.sender] += amount;
        _totalSupply += amount;
        _updateBalanceOfMatic(amount, true);
    }

    function _updateBalanceOfMatic(uint256 amount, bool add) internal {
        _balanceOfMatic = add ? _balanceOfMatic += amount : _balanceOfMatic -= amount;
    }

    /// @notice owner can withdraw all the funds after 2022 Nov 20 12:00 PM
    /// @notice This function is not witnin the CTF attack surface, only for admin purposes
    function withdraw(address token) external onlyOwner {
        require(block.timestamp >= 1668974400, "POOL NOT EXPIRED");
        if (token == address(0)) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        } else {
            TransferHelper.safeTransfer(token, msg.sender, IERC20(token).balanceOf(address(this)));
        }
    }
}
