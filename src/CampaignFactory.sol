// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Campaign} from "./Campaign.sol";

contract CampaignFactory {
    address public immutable IMPLEMENTATION;
    address public governor;
    address public timelock;

    event CampaignCreated(address campaign, address escrow, address creator);

    constructor(address _implementation, address _governor, address _timelock) {
        IMPLEMENTATION = _implementation;
        governor = _governor;
        timelock = _timelock;
    }

    function createCampaign(address stablecoin, string calldata metadataCid, uint256 trustScore)
        external
        returns (address campaignAddr, address escAddr)
    {
        address campaign = Clones.clone(IMPLEMENTATION);

        Campaign(campaign)
            .initialize(
                msg.sender, // creator
                governor, // governor
                stablecoin, // stablecoin
                metadataCid, // metadataCid
                timelock, // timelock
                trustScore // trustScore
            );
        escAddr = address(Campaign(campaign).escrow());
        emit CampaignCreated(campaign, escAddr, msg.sender);
        return (campaign, escAddr);
    }
}
