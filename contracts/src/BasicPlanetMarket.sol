// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./outerspace/interfaces/IOuterSpace.sol";
import "./outerspace/interfaces/IApprovalReceiver.sol";

contract BasicPlanetMarket is IApprovalReceiver {
    event PlanetsForSale(
        address indexed owner,
        uint256 id,
        uint256 price,
        uint256[] planets,
        uint256[] minNumSpaceships
    );
    event SaleCancelled(uint256 indexed id, address indexed owner);

    event PlanetsSold(uint256 indexed id, address indexed owner, address indexed newOwner);

    struct PlanetsSale {
        address payable seller;
        uint256 price;
        uint256[] planets;
        uint256[] minNumSpaceships;
        uint256 timestamp;
    }

    mapping(uint256 => PlanetsSale) internal _sales;

    uint256 internal _counter;

    IOuterSpace internal immutable _outerspace;

    constructor(IOuterSpace outerspace) {
        _outerspace = outerspace;
    }

    ///@dev useful to get data without any off-chain caching, but does not scale to many locations
    function getSales(uint256[] calldata ids) external view returns (PlanetsSale[] memory sales) {
        sales = new PlanetsSale[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            sales[i] = _sales[ids[i]];
        }
    }

    function onApprovalForAllBy(address payable owner, bytes calldata data) external {
        require(msg.sender == address(_outerspace), "APPROVEDBY_EXPECTS_OUTERSPACE");
        (uint256 price, uint256[] memory planets, uint256[] memory minNumSpaceships) = abi.decode(
            data,
            (uint256, uint256[], uint256[])
        );
        _setSpaceshipsForSale(owner, price, planets, minNumSpaceships);
    }

    function setPlanetsForSale(
        uint256 price,
        uint256[] calldata planets,
        uint256[] calldata minNumSpaceships
    ) external {
        _setSpaceshipsForSale(payable(msg.sender), price, planets, minNumSpaceships);
    }

    function cancelSale(uint256 id) external {
        PlanetsSale storage sale = _sales[id];
        require(sale.seller == msg.sender, "NOT_SELLER");
        _sales[id].seller = payable(address(0));
        _sales[id].timestamp = 0;

        emit SaleCancelled(id, msg.sender);
    }

    function purchase(uint256 id, address newOwner) external payable {
        PlanetsSale memory sale = _sales[id];
        require(sale.timestamp > 0, "SALE_OVER");

        for (uint256 i = 0; i < sale.planets.length; i++) {
            uint256 location = sale.planets[i];
            uint256 minSpaceships = sale.minNumSpaceships[i];
            // (address owner, uint40 ownershipStartTime) = _outerspace.ownerAndOwnershipStartTimeOf(location);
            IOuterSpace.ExternalPlanet memory planetUpdated = _outerspace.getUpdatedPlanetState(location);
            require(planetUpdated.owner == sale.seller, "NOT_OWNER");
            require(sale.timestamp > planetUpdated.ownershipStartTime, "OWNERSHIP_CHANGED_SALE_OUTDATED");
            require(planetUpdated.numSpaceships >= minSpaceships, "PLANET_LOW_SPACESHIPS");
            _outerspace.safeTransferFrom(address(this), newOwner, location);
        }

        uint256 toPay = sale.price;
        require(msg.value >= toPay, "NOT_ENOUGH_FUND");
        sale.seller.transfer(toPay);
        if (msg.value > toPay) {
            payable(msg.sender).transfer(msg.value - toPay);
        }

        emit PlanetsSold(id, sale.seller, newOwner);

        _sales[id].seller = payable(address(0));
        _sales[id].timestamp = 0;
    }

    // ----------------------------------------
    // INTERNAL
    // ----------------------------------------

    function _setSpaceshipsForSale(
        address payable seller,
        uint256 price,
        uint256[] memory planets,
        uint256[] memory minNumSpaceships
    ) internal {
        uint256 id = ++_counter;
        _sales[id].timestamp = uint40(block.timestamp);
        _sales[id].seller = seller;
        _sales[id].price = price;
        _sales[id].planets = planets;
        _sales[id].minNumSpaceships = minNumSpaceships;

        emit PlanetsForSale(seller, id, price, planets, minNumSpaceships);
    }
}
