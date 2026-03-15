// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {DAOGovernor} from "../src/DAOGovernor.sol";
import {Campaign} from "../src/Campaign.sol";
import {CampaignFactory} from "../src/CampaignFactory.sol";
import {MilestoneEscrow} from "../src/MilestoneEscrow.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CampaignFlowTest is Test {
    using SafeERC20 for MockUSDC;

    GovernanceToken rep;
    DAOGovernor governor;
    TimelockController timelock;
    MockUSDC usdc;
    CampaignFactory factory;
    Campaign campaign;
    MilestoneEscrow escrow;

    address creator = makeAddr("creator");
    address donor = makeAddr("donor");
    address voter = address(this);

    uint256 constant VOTING_DELAY = 1 days;
    uint256 constant VOTING_PERIOD = 1 weeks;
    uint256 constant TIMELOCK_DELAY = 1 days;

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    function setUp() public {
        usdc = new MockUSDC();
        rep = new GovernanceToken(msg.sender, usdc);

        // Mint + delegate BEFORE proposing, to ensure voting weight at snapshot
        vm.startPrank(msg.sender);
        rep.mint(voter, 500_000 ether);
        vm.stopPrank();
        rep.delegate(voter);

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(0);
        executors[0] = address(0);

        timelock = new TimelockController(
            TIMELOCK_DELAY,
            proposers,
            executors,
            msg.sender
        );
        governor = new DAOGovernor(IVotes(address(rep)), timelock);

        vm.startPrank(msg.sender);
        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(EXECUTOR_ROLE, address(governor));
        vm.stopPrank();

        Campaign impl = new Campaign();
        factory = new CampaignFactory(
            address(impl),
            address(governor),
            address(timelock)
        );

        vm.prank(creator);
        (address campAddr, address escAddr) = factory.createCampaign(
            address(usdc),
            "ipfs://QmExampleCampaignMetadata",
            92
        );

        campaign = Campaign(campAddr);
        escrow = MilestoneEscrow(escAddr);
    }

    function test_full_flow() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(campaign);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("approveAndGoLive()");
        string memory desc = "Approve emergency medical campaign #123";

        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        // Move to voting start (Active)
        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        governor.castVote(proposalId, 1);

        // Move past voting period (Succeeded)
        vm.roll(governor.proposalDeadline(proposalId) + 1);

        bytes32 descHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descHash);

        // Move past timelock delay
        skip(TIMELOCK_DELAY + 1);
        vm.roll(block.number + 1);
        governor.execute(targets, values, calldatas, descHash);

        assertTrue(campaign.isLive(), "Campaign should be live");

        // Donate
        uint256 donation = 12_000 * 10 ** 6;
        usdc.safeTransfer(donor, donation);
        vm.startPrank(donor);
        usdc.approve(address(campaign), donation);
        campaign.donate(donation);
        vm.stopPrank();
        assertEq(usdc.balanceOf(address(escrow)), donation);

        // Propose milestone
        string memory proofCid = "ipfs://QmProofOfHospitalBillAndTreatment";
        uint256 milestoneAmount = 5_000 * 10 ** 6;
        vm.prank(creator);
        campaign.proposeMilestone(proofCid, milestoneAmount);

        (string memory savedCid, uint256 savedAmt, bool released) = escrow
            .getMilestone(0);
        assertEq(savedCid, proofCid);
        assertEq(savedAmt, milestoneAmount);
        assertFalse(released);

        // Release milestone
        targets[0] = address(campaign);
        calldatas[0] = abi.encodeWithSignature("releaseMilestone(uint256)", 0);
        desc = "Release milestone 1 - medical treatment proof";

        proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        governor.castVote(proposalId, 1);

        vm.roll(governor.proposalDeadline(proposalId) + 1);

        descHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descHash);

        skip(TIMELOCK_DELAY + 1);
        vm.roll(block.number + 1);
        governor.execute(targets, values, calldatas, descHash);

        (, , released) = escrow.getMilestone(0);
        assertTrue(released);
        assertEq(usdc.balanceOf(creator), milestoneAmount);
        assertEq(usdc.balanceOf(address(escrow)), donation - milestoneAmount);
    }
}
