pragma solidity ^0.8.0;

interface IERC20 {
	function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
	function transfer(address recipient, uint256 amount) external returns (bool);
	function mint(address to, uint256 amount) external returns (bool);
	function burn(address from, uint256 amount) external returns (bool);
	function balanceOf(address account) external view returns (uint256);
}

contract aTokenMock is IERC20 {
	string public name = "Mock aToken";
	string public symbol = "aM";
	uint8 public decimals = 6;

	mapping(address => uint256) private _balances;
	uint256 private _totalSupply;

	function totalSupply() public view returns (uint256) {
		return _totalSupply;
	}

	function balanceOf(address account) public view returns (uint256) {
		return _balances[account];
	}

	function mint(address to, uint256 amount) public override returns (bool) {
		_totalSupply += amount;
		_balances[to] += amount;
		return true;
	}

	function mint(uint256 amount) external returns (bool) {
		return mint(msg.sender, amount);
	}

	function burn(address from, uint256 amount) external override returns (bool) {
		require(_balances[from] >= amount, "Insufficient balance");
		_balances[from] -= amount;
		_totalSupply -= amount;
		return true;
	}

	function transfer(address recipient, uint256 amount) external override returns (bool) {
		require(_balances[msg.sender] >= amount, "Insufficient balance");
		_balances[msg.sender] -= amount;
		_balances[recipient] += amount;
		return true;
	}

	function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
		require(_balances[sender] >= amount, "Insufficient balance");
		_balances[sender] -= amount;
		_balances[recipient] += amount;
		return true;
	}
}