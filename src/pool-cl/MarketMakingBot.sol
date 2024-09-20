// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { PoolKey } from "pancake-v4-core/src/types/PoolKey.sol";
import { BalanceDelta, toBalanceDelta } from "pancake-v4-core/src/types/BalanceDelta.sol";
import { ICLPoolManager } from "pancake-v4-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import { CLBaseHook } from "./CLBaseHook.sol";

contract MarketMakingBot is CLBaseHook {
    using SafeMath for uint256;

    struct LiquidityOrder {
        uint256 amount;
        uint256 price; // Target price for liquidity placement
        uint256 timestamp; // Time when the order was placed
    }

    mapping(address => LiquidityOrder[]) public liquidityOrders;
    mapping(address => uint256) public yieldBalance; // LP earnings
    address[] public liquidityProviders;

    event LiquidityAdded(address indexed provider, uint256 amount, uint256 price, uint256 timestamp);
    event LiquidityRemoved(address indexed provider, uint256 amount, uint256 timestamp);
    event YieldShared(address indexed provider, uint256 yieldAmount, uint256 timestamp);

    constructor(ICLPoolManager _poolManager) CLBaseHook(_poolManager) {}

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: true,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: true,
                afterRemoveLiquidity: true,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnsDelta: false,
                afterSwapReturnsDelta: false,
                afterAddLiquidityReturnsDelta: true,
                afterRemoveLiquidityReturnsDelta: true
            })
        );
    }

    // Function to add liquidity at a specific price (order book style)
    function addLiquidity(
        address provider,
        uint256 amount,
        uint256 price
    ) external returns (bool) {
        require(amount > 0, "Invalid liquidity amount");

        LiquidityOrder memory order = LiquidityOrder({
            amount: amount,
            price: price,
            timestamp: block.timestamp
        });

        liquidityOrders[provider].push(order);
        liquidityProviders.push(provider);

        emit LiquidityAdded(provider, amount, price, block.timestamp);

        return true;
    }

    // Function to rebalance liquidity based on current market price
    function rebalanceLiquidity(address provider, uint256 newPrice) external {
        LiquidityOrder[] storage orders = liquidityOrders[provider];
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].price != newPrice) {
                // Rebalance the order to the new price
                orders[i].price = newPrice;
            }
        }
    }

    // Function to remove liquidity from a specific price level
    function removeLiquidity(address provider, uint256 amount, uint256 price) external returns (bool) {
        LiquidityOrder[] storage orders = liquidityOrders[provider];
        uint256 remainingAmount = amount;

        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].price == price && remainingAmount > 0) {
                if (orders[i].amount >= remainingAmount) {
                    orders[i].amount = orders[i].amount.sub(remainingAmount);
                    remainingAmount = 0;
                } else {
                    remainingAmount = remainingAmount.sub(orders[i].amount);
                    orders[i].amount = 0;
                }
            }
        }

        emit LiquidityRemoved(provider, amount, block.timestamp);

        return true;
    }

    // Calculate yield and share it among LPs based on their liquidity
    function shareYield() external {
        uint256 totalLiquidity = getTotalLiquidity();
        for (uint256 i = 0; i < liquidityProviders.length; i++) {
            address provider = liquidityProviders[i];
            uint256 providerLiquidity = getTotalLiquidityForProvider(provider);

            // Calculate the share of yield for the provider
            uint256 yield = calculateYield(providerLiquidity, totalLiquidity);
            yieldBalance[provider] = yieldBalance[provider].add(yield);

            emit YieldShared(provider, yield, block.timestamp);
        }
    }

    // Helper function to calculate the total liquidity in the pool
    function getTotalLiquidity() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < liquidityProviders.length; i++) {
            total = total.add(getTotalLiquidityForProvider(liquidityProviders[i]));
        }
        return total;
    }

    // Helper function to calculate the total liquidity for a specific provider
    function getTotalLiquidityForProvider(address provider) public view returns (uint256) {
        LiquidityOrder[] storage orders = liquidityOrders[provider];
        uint256 total = 0;
        for (uint256 i = 0; i < orders.length; i++) {
            total = total.add(orders[i].amount);
        }
        return total;
    }

    // Calculate the yield for a provider based on their share of the total liquidity
    function calculateYield(uint256 providerLiquidity, uint256 totalLiquidity) public pure returns (uint256) {
        // proportional yield based on liquidity share
        return providerLiquidity.mul(1000).div(totalLiquidity); // Simplified yield calculation
    }
}
