pragma solidity ^0.8.0;

import { aTokenMock, IERC20 } from "./ATokenMock.sol";

contract LendingPoolMock {

	aTokenMock public aToken;
	uint256 constant INTEREST_RATE = 105; // linear 5% yearly yield for simplicity

	constructor(address _aTokenAddress) {
		aToken = aTokenMock(_aTokenAddress);
	}

	function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
		accrueInterest();
		IERC20(asset).transferFrom(msg.sender, address(this), amount);
		aToken.mint(onBehalfOf, amount);
	}

	function withdraw(address asset, uint256 amount, address to) external {
		accrueInterest();
		uint256 interest = (amount * INTEREST_RATE) / 100;
		require(IERC20(asset).balanceOf(address(this)) >= interest, "insufficient liquidity in the pool");

		aToken.burn(msg.sender, amount);
		IERC20(asset).transfer(to, interest);
	}

	function accrueInterest() public {
		uint256 poolBalance = IERC20(address(aToken)).balanceOf(address(this));
		uint256 interest = (poolBalance * INTEREST_RATE) / 100 - poolBalance;
		aToken.mint(address(this), interest);
	}
}