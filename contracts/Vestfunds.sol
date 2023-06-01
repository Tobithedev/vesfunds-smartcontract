// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./Token/index.sol";

contract Vestfunds is Ownable {
    using SafeMath for uint256;
    struct Campaign {
        uint256 id;
        address payable owner; // Address of the startup owner
        string name; // Name of the startup
        string symbol; // Symbol of the token to be created for the startup
        string description; // Description of the startup
        string team; // Teams of the startup
        uint256 target; // Total amount the startup wants to raise
        uint256 raisedAmount; // Amount raised so far
        uint256 equity;
        uint256 circulationSupply;
        uint256 tokenPrice; // Price of each token in USDT
        uint256 deadline; // Deadline for the campaign in UNIX timestamp format
        bool isFunded; // Flag to indicate whether the campaign has been funded
        bool isClosed; // Flag to indicate whether the campaign has been closed
        VestfundsCustomToken token; // ERC20 token contract created for the campaign
        bool withdrawn;
        string image;
    }

    // Mapping of campaign ID to campaign information
    Campaign[] public campaigns;
    mapping(address => uint256[]) private campaignsByOwner;

    // Event triggered when a new campaign is created
    event CampaignCreated(
        uint256 campaignId,
        address owner,
        string name,
        string symbol,
        uint256 target,
        uint256 deadline
    );

    // Event triggered when a campaign is funded
    event CampaignFunded(uint256 campaignId, address funder, uint256 amount);

    // Event triggered when a campaign is closed
    event CampaignClosed(uint256 campaignId);

    // Function to create a new campaign
    function createCampaign(
        string memory name,
        string memory symbol,
        string memory _description,
        string memory _team,
        uint256 target,
        uint256 totalSupply,
        uint256 _equity,
        uint256 deadline,
        uint256 tokenPrice,
        string memory _image
    ) external returns (uint256) {
        require(bytes(name).length > 0, "Startup name cannot be empty");
        require(bytes(symbol).length > 0, "Token symbol cannot be empty");
        require(target > 0, "Target amount must be greater than zero");
        require(deadline > block.timestamp, "Deadline must be a future date");
        require(tokenPrice > 0, "Token price must be greater than zero");

        // Create the ERC20 token contract for the campaign
        VestfundsCustomToken token = new VestfundsCustomToken(name, symbol);

        // Mint all the tokens to the campaign owner
        token.mint(msg.sender, totalSupply);

        // Add the campaign information to the campaigns mapping
        Campaign memory campaign = Campaign({
            id: campaigns.length,
            owner: payable(msg.sender),
            name: name,
            symbol: symbol,
            description: _description,
            team: _team,
            target: target,
            raisedAmount: 0,
            equity: _equity,
            circulationSupply: totalSupply / _equity,
            tokenPrice: tokenPrice,
            deadline: deadline,
            isFunded: false,
            isClosed: false,
            token: token,
            withdrawn: false,
            image: _image
        });

        campaigns.push(campaign);
        campaignsByOwner[msg.sender].push(campaign.id);
        // Trigger the CampaignCreated event
        emit CampaignCreated(
            campaign.id,
            msg.sender,
            name,
            symbol,
            target,
            deadline
        );

        // Return the ID of the new campaign
        return campaign.id;
    }

    function invest(uint256 _campaignId, uint256 _amount) public {
         Campaign storage campaign = campaigns[_campaignId];

        require(!campaign.isClosed, "Campaign is completed");
        require(campaign.deadline > block.timestamp, "Campaign has ended");
        require(_amount > 5, "Amount must be greater than five");

        uint256 tokensToMint = _amount / campaign.tokenPrice;
        require(
            _amount < campaign.circulationSupply,
            "Insufficient tokens left"
        );
        campaign.raisedAmount += _amount;
        campaign.token.transfer(msg.sender, tokensToMint);
        if (campaign.raisedAmount >= campaign.target) {
            campaign.isClosed = true;
            campaign.owner.transfer(campaign.raisedAmount);
        }
        emit CampaignFunded(_campaignId, msg.sender, _amount);
    }

    function getCampaignsByOwner(
        address _owner
    ) public view returns (uint256[] memory) {
        uint256[] memory campaignsByOwner = new uint256[](campaigns.length);
        uint256 counter = 0;
        for (uint256 i = 0; i < campaigns.length; i++) {
            if (campaigns[i].owner == _owner) {
                campaignsByOwner[counter] = i;
                counter++;
            }
        }
        uint256[] memory result = new uint256[](counter);
        for (uint256 i = 0; i < counter; i++) {
            result[i] = campaignsByOwner[i];
        }
        return result;
    }

    function withdraw(uint256 _campaignId, address _treasuryAddress) public onlyOwner {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            msg.sender == campaign.owner,
            "Only the owner of the campaign can withdraw the funds."
        );
        require(
            !campaign.withdrawn,
            "The funds for this campaign have already been withdrawn."
        );
        require(
            campaign.raisedAmount >= campaign.target,
            "The target has not been reached yet."
        );

        uint256 amount = campaign.raisedAmount;
        uint256 treasuryAmount = (amount * 3) / 100;
        uint256 ownerAmount = amount - treasuryAmount;
        campaign.raisedAmount = 0;

        (bool success, ) = campaign.owner.call{value: ownerAmount}("");
        require(success, "Transfer to owner failed.");

        (success, ) = (_treasuryAddress).call{
            value: treasuryAmount
        }("");
        require(success, "Transfer to treasury failed.");

        campaign.withdrawn = true;
    }
}
