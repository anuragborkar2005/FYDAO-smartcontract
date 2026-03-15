// SPDX-License-Identifier : MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MilestoneEscrow is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable TOKEN; //USDC / stablecoin
    address public immutable CAMPAIGN_CREATOR;
    address public immutable GOVERNOR; //DAO Governor contract that can release

    uint256 public totalDeposited;
    uint256 public totalReleased;

    struct Milestone {
        string proofCid;
        uint256 amount;
        bool released;
    }

    Milestone[] public milestones;

    event Deposited(address indexed donor, uint256 amount);
    event MilestoneProposed(uint256 indexed id, string proofCid, uint256 amount);
    event MilestoneReleased(uint256 indexed id, uint256 amount, address to);

    modifier onlyGovernor() {
        _onlyGovernor();
        _;
    }

    function _onlyGovernor() internal view {
        require(msg.sender == address(GOVERNOR), "Only governor can call");
    }

    constructor(address _token, address _creator, address _governor) Ownable(msg.sender) {
        TOKEN = IERC20(_token);
        CAMPAIGN_CREATOR = _creator;
        GOVERNOR = _governor;
    }

    // Anyone (donors) can deposit stablecoins
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;
        emit Deposited(msg.sender, amount);
    }

    // Creator proposes a milestone (can be called multiple times)
    function proposeMilestone(string calldata proofCid, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        require(totalDeposited >= totalReleased + amount, "Not enough funds deposited");

        milestones.push(Milestone({proofCid: proofCid, amount: amount, released: false}));

        emit MilestoneProposed(milestones.length - 1, proofCid, amount);
    }

    // Called by DAO Governor after successful vote
    function releaseMilestone(uint256 milestoneId) external onlyOwner nonReentrant {
        require(milestoneId < milestones.length, "Invalid milestone ID");
        Milestone storage milestone = milestones[milestoneId];
        require(!milestone.released, "Already released");
        require(TOKEN.balanceOf(address(this)) >= milestone.amount, "Insufficient balance");

        milestone.released = true;
        totalReleased += milestone.amount;

        TOKEN.safeTransfer(CAMPAIGN_CREATOR, milestone.amount);

        emit MilestoneReleased(milestoneId, milestone.amount, CAMPAIGN_CREATOR);
    }

    // View helpers
    function getMilestoneCount() external view returns (uint256) {
        return milestones.length;
    }

    function getMilestone(uint256 id) external view returns (string memory proofCid, uint256 amount, bool released) {
        Milestone memory m = milestones[id];
        return (m.proofCid, m.amount, m.released);
    }

    // Emergency withdraw remaining funds by governor (only if needed - governance decision)
    function emergencyWithdraw(uint256 amount) external onlyGovernor nonReentrant {
        require(TOKEN.balanceOf(address(this)) >= amount, "Insufficient balance");
        TOKEN.safeTransfer(GOVERNOR, amount); // send to DAO timelock / treasury
    }
}
