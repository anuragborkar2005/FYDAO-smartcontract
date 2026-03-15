// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {DAOGovernor} from "../src/DAOGovernor.sol";
import {Campaign} from "../src/Campaign.sol";
import {CampaignFactory} from "../src/CampaignFactory.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        // 1. Mock USDC (deploy first so we can wrap it)
        MockUSDC usdc = new MockUSDC();

        // 2. Governance Token (wrap USDC, set deployer as owner)
        GovernanceToken tkn = new GovernanceToken(msg.sender, usdc);

        // 3. Timelock (min delay 0 for testing)
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        TimelockController timelock = new TimelockController(0 days, proposers, executors, msg.sender);

        // 4. DAO Governor
        DAOGovernor governor = new DAOGovernor(IVotes(address(tkn)), timelock);

        // Setup Timelock Roles
        timelock.grantRole(keccak256("PROPOSER_ROLE"), address(governor));
        timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));
        timelock.grantRole(keccak256("TIMELOCK_ADMIN_ROLE"), msg.sender);

        // 5. Campaign Implementation + Factory
        Campaign campaignImpl = new Campaign();
        CampaignFactory factory = new CampaignFactory(address(campaignImpl), address(governor), address(timelock));

        // Give deployer some governance tokens for testing
        tkn.mint(msg.sender, 10_000 ether);

        // Transfer token ownership to Governor
        tkn.transferOwnership(address(governor));

        vm.stopBroadcast();

        console.log("=== DEPLOYED ===");
        console.log("GovernanceToken:", address(tkn));
        console.log("Timelock:", address(timelock));
        console.log("Governor:", address(governor));
        console.log("MockUSDC:", address(usdc));
        console.log("CampaignFactory:", address(factory));
    }
}
