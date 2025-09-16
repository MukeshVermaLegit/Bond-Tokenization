// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract BondToken is ERC20 {
    IERC20 public usdc; // Mock USDC used for deposits & payouts

    uint256 public faceValue; // Principal per bond
    uint256 public couponRate; // Annual interest (e.g., 5% = 500 -> basis points)
    uint256 public maturityDate; // UNIX timestamp maturity

    uint256 public lastCouponTimestamp;
    mapping(address => uint256) public claimedInterest;

    constructor(address _usdc, uint256 _faceValue, uint256 _couponRate, uint256 _maturityDate)
        ERC20("BondToken", "BOND")
    {
        require(_maturityDate > block.timestamp, "Invalid maturity");
        usdc = IERC20(_usdc);
        faceValue = _faceValue;
        couponRate = _couponRate;
        maturityDate = _maturityDate;
        lastCouponTimestamp = block.timestamp;
    }

    /// @notice Buy bonds by depositing USDC
    function buy(uint256 amount) external {
        uint256 totalCost = faceValue * amount;
        require(usdc.transferFrom(msg.sender, address(this), totalCost), "Payment failed");
        _mint(msg.sender, amount);
    }

    /// @notice Calculate accrued interest for an address
    function pendingInterest(address user) public view returns (uint256) {
        uint256 holderBalance = balanceOf(user);
        if (holderBalance == 0) return 0;

        uint256 monthsElapsed = (block.timestamp - lastCouponTimestamp) / 30 days;
        uint256 yearlyInterest = (faceValue * holderBalance * couponRate) / 10000; // basis points
        uint256 monthlyInterest = yearlyInterest / 12;

        return monthsElapsed * monthlyInterest - claimedInterest[user];
    }

    /// @notice Claim coupon interest
    function claimInterest() external {
        uint256 interest = pendingInterest(msg.sender);
        require(interest > 0, "No interest");

        claimedInterest[msg.sender] += interest;

        // For mock USDC, we need to mint the interest payment
        // In production, this would require the contract to be pre-funded
        (bool success,) = address(usdc).call(abi.encodeWithSignature("mint(address,uint256)", address(this), interest));
        require(success, "Mint failed");

        require(usdc.transfer(msg.sender, interest), "Transfer failed");
    }

    /// @notice Redeem principal + final interest at maturity
    function redeem() external {
        require(block.timestamp >= maturityDate, "Not matured yet");
        uint256 bonds = balanceOf(msg.sender);
        require(bonds > 0, "No bonds");

        uint256 principal = bonds * faceValue;
        uint256 interest = pendingInterest(msg.sender);

        _burn(msg.sender, bonds);
        claimedInterest[msg.sender] += interest;

        // For mock USDC, we need to mint the interest payment
        // In production, this would require the contract to be pre-funded
        if (interest > 0) {
            (bool success,) =
                address(usdc).call(abi.encodeWithSignature("mint(address,uint256)", address(this), interest));
            require(success, "Mint failed");
        }

        require(usdc.transfer(msg.sender, principal + interest), "Redeem failed");
    }
}
