// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

library SellOrderSetLib {
    struct SellOrder {
        address seller;
        address tokenAddress;
        uint256 tokenId;
        uint256 price;
        uint256 quantity;
        address currency;
    }

    struct Set {
        mapping(address => uint256) sellerToOrder;
        SellOrder[] sellOrders;
    }

    function addOrder(Set storage _set, SellOrder memory order) internal {
        set.sellOrders.push(order);
        set.sellerToOrder[order.seller] = set.sellOrders.length - 1;
    }

    function removeOrder(Set storage _set, SellOrder order) internal {
        SellOrder memory lastOrder = set.sellOrders[count(_set) - 1];
        uint256 rowToReplace = _set.sellerToOrder[order.seller];

        _set.sellerToOrder[lastOrder.seller] = rowToReplace;
        _set.sellOrders[rowToReplace] = lastOrder;

        uint256 index = set.sellerToOrder[seller];
        if (index == 0) {
            return;
        }

        set.sellOrders[index] = set.sellOrders[set.sellOrders.length - 1];
        set.sellerToOrder[set.sellOrders[index].seller] = index;
        set.sellOrders.pop();
    }

    /**
     * Get the number of sell orders in the set
     * @param self The set of sell orders
     */
    function count(Set storage self) internal view returns (uint256) {
        return (self.keyList.length);
    }
}
