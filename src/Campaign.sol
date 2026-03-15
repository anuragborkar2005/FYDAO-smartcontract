// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MilestoneEscrow} from "./MilestoneEscrow.sol";

contract Campaign is Initializable {
    using SafeERC20 for IERC20;

    address creator;
    address governor;
    IERC20 public stablecoin;
    string public metadataCid;
    uint256 public trustScore;
    address public timelock;
    bool public isLive;

    MilestoneEscrow public escrow;

    struct Milestone {
        string proofCid;
        uint256 amount;
        bool released;
    }

    Milestone[] public milestones;

    event CampaignLive();

    event MilestoneProposed(uint256 indexed id, string proofCid, uint256 amount);

    function initialize(
        address _creator,
        address _governor,
        address _stablecoin,
        string calldata _metadataCid,
        address _timelock,
        uint256 _trustScore
    ) external initializer {
        creator = _creator;
        governor = _governor;
        stablecoin = IERC20(_stablecoin);
        timelock = _timelock;
        metadataCid = _metadataCid;
        trustScore = _trustScore;

        escrow = new MilestoneEscrow(_stablecoin, _creator, governor);
        stablecoin.approve(address(escrow), type(uint256).max);
    }

    function approveAndGoLive() external {
        require(msg.sender == address(timelock), "Only Governor");
        isLive = true;
        emit CampaignLive();
    }

    function donate(uint256 amount) external {
        require(isLive, "Campaign is not live");
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);
        escrow.deposit(amount);
    }

    function proposeMilestone(string calldata proofCid, uint256 amount) external {
        require(msg.sender == creator, "Only Creator");
        require(isLive, "Not Live");
        escrow.proposeMilestone(proofCid, amount);
        emit MilestoneProposed(escrow.getMilestoneCount() - 1, proofCid, amount);
    }

    function releaseMilestone(uint256 id) external {
        require(msg.sender == timelock, "Only Governor");
        escrow.releaseMilestone(id);
    }

    // TODO: For hybrid voting — add donor-weighted functions here later
}
