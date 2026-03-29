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

    // Accounts
    address creator = makeAddr("creator");
    address donor1 = makeAddr("donor1");
    address donor2 = makeAddr("donor2");

    // DAO Members
    address voterA = makeAddr("voterA");
    address voterB = makeAddr("voterB");
    address voterC = makeAddr("voterC");

    uint256 constant TIMELOCK_DELAY = 1 days;
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    function setUp() public {
        usdc = new MockUSDC();
        rep = new GovernanceToken(address(this), usdc);

        // 1. Setup Multiple DAO Members with voting power
        _setupVoter(voterA, 300_000 ether); // 30% weight
        _setupVoter(voterB, 150_000 ether); // 15% weight
        _setupVoter(voterC, 50_000 ether); // 5% weight

        // 2. Setup Timelock and Governor
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, address(this));
        governor = new DAOGovernor(IVotes(address(rep)), timelock);

        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(EXECUTOR_ROLE, address(governor));

        // 3. Setup Factory and Create Campaign
        Campaign impl = new Campaign();
        factory = new CampaignFactory(address(impl), address(governor), address(timelock));

        vm.prank(creator);
        (address campAddr, address escAddr) =
            factory.createCampaign(address(usdc), "ipfs://QmExampleCampaignMetadata", 92);

        campaign = Campaign(campAddr);
        escrow = MilestoneEscrow(escAddr);
    }

    function _setupVoter(address voter, uint256 amount) internal {
        rep.mint(voter, amount);
        vm.prank(voter);
        rep.delegate(voter);
    }

    function test_multi_user_flow() public {
        // --- STEP 1: DAO VOTING BY MULTIPLE MEMBERS ---
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(campaign);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("approveAndGoLive()");
        string memory desc = "Approve Campaign #123";

        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        // Multiple members cast votes
        vm.prank(voterA);
        governor.castVote(proposalId, 1); // For
        vm.prank(voterB);
        governor.castVote(proposalId, 1); // For
        vm.prank(voterC);
        governor.castVote(proposalId, 0); // Against (simulating dissent)

        vm.roll(governor.proposalDeadline(proposalId) + 1);

        bytes32 descHash = keccak256(bytes(desc));
        governor.queue(targets, values, calldatas, descHash);
        uint256 eta = governor.proposalEta(proposalId);
        vm.warp(eta + 1);
        vm.roll(block.number + 1);
        governor.execute(targets, values, calldatas, descHash);

        assertTrue(campaign.isLive());

        // --- STEP 2: MULTIPLE DONORS CONTRIBUTING ---
        uint256 amt1 = 5_000 * 10 ** 6;
        uint256 amt2 = 7_000 * 10 ** 6;

        _handleDonation(donor1, amt1);
        _handleDonation(donor2, amt2);

        assertEq(usdc.balanceOf(address(escrow)), amt1 + amt2);

        // --- STEP 3: MILESTONE RELEASE BY DAO ---
        uint256 milestoneAmount = 4_000 * 10 ** 6;
        vm.prank(creator);
        campaign.proposeMilestone("ipfs://QmProof", milestoneAmount);

        targets[0] = address(campaign);
        calldatas[0] = abi.encodeWithSignature("releaseMilestone(uint256)", 0);
        desc = "Release First Milestone";

        proposalId = governor.propose(targets, values, calldatas, desc);
        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        // Voters approve the release
        vm.prank(voterA);
        governor.castVote(proposalId, 1);
        vm.prank(voterB);
        governor.castVote(proposalId, 1);

        vm.roll(governor.proposalDeadline(proposalId) + 1);
        governor.queue(targets, values, calldatas, keccak256(bytes(desc)));
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calldatas, keccak256(bytes(desc)));

        assertEq(usdc.balanceOf(creator), milestoneAmount);
    }

    function _handleDonation(address donor, uint256 amount) internal {
        usdc.mint(donor, amount);
        vm.startPrank(donor);
        usdc.approve(address(campaign), amount);
        campaign.donate(amount);
        vm.stopPrank();
    }
}
