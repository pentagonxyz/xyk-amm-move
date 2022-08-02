// Constant product AMM (like Uniswap V2) for swapping Coin objects.
module aubrium::automated_market_maker{
    use sui::transfer::{Self};
    use sui::object::{Self, ID, Info};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::math::{Self};

    
    ///*///////////////////////////////////////////////////////////////
    //                         MAIN OBJECTS                          //
    /////////////////////////////////////////////////////////////////*/

    // Minimum liquidity required in a pool.
    const MINIMUM_LIQUIDITY: u64 = 1000;

    // Represents a pool/pair of two contracts that can be exchanged for one another.
    struct Pair<phantom Asset1, phantom Asset2> has key, store {
        info: Info,
        coin1: Coin<Asset1>,
        coin2: Coin<Asset2>,
        locked_liquidity: Coin<LiquidityCoin<Asset1, Asset2>>,
        lp_treasury_capability: TreasuryCap<LiquidityCoin<Asset1, Asset2>>,
    }

    // Object used to name/represent lp tokens.
    struct LiquidityCoin<phantom Asset1, phantom Asset2> has drop { }

    ///*///////////////////////////////////////////////////////////////
    //                           ERROR CODES                         //
    /////////////////////////////////////////////////////////////////*/

    // Attempt to create a pair with the same assets as an existing pair.
    const EPairExists: u64 = 0;

    // An insufficient amount of liquidity was provided/minted.
    const EInsufficientLiquidityMinted: u64 = 1;

    // An insufficient amount of liquidity was removed/burned.
    const EInsufficientLiquidityBurned: u64 = 2;

    // An insufficient number of coins was inputted for a swap.
    const EInsufficientInput: u64 = 3;

    // There is an insufficient amount of liquidity in the pool.
    const EInsufficientLiquidity: u64 = 4;

    // The amount of minimum output tokens requested is too large.
    const EInsufficientOutputAmount: u64 = 5;

    
    ///*///////////////////////////////////////////////////////////////
    //                        PAIR CREATION LOGIC                    //
    /////////////////////////////////////////////////////////////////*/

    // Creates a new pool/pair of coins.
    public fun new_pair<Asset1, Asset2>(ctx: &mut TxContext) {
        // Ensure that the pair does not already exist.
        assert!(!exists<Pair<Asset1, Asset2>>(@aubrium), EPairExists);
        assert!(!exists<Pair<Asset2, Asset1>>(@aubrium), EPairExists);

        // Create a new token to represent the pair's lp token.
        let lp_treasury_capability = coin::create_currency<LiquidityCoin<Asset1, Asset2>>(
            LiquidityCoin<Asset1, Asset2>{}, 
            ctx
        );

        // Create a new pair object.
        let pair = Pair<Asset1, Asset2> {
            info: object::new(ctx), 
            coin1: coin::zero<Asset1>(ctx),
            coin2: coin::zero<Asset2>(ctx),
            locked_liquidity: coin::zero<LiquidityCoin<Asset1, Asset2>>(ctx),
            lp_treasury_capability
        };

        // Make the pair object shared so that it can be accessed by anyone. 
        transfer::share_object(pair);
    }

    ///*///////////////////////////////////////////////////////////////
    //                    ADD/REMOVE LIQUIDITY LOGIC                 //
    /////////////////////////////////////////////////////////////////*/

    // Add liquidity to the pool and mint lp tokens to represent ownership over some of the assets in the pool.
    public fun add_liquidity<Asset1, Asset2>(
        pair: &mut Pair<Asset1, Asset2>, 
        coin1: Coin<Asset1>, 
        coin2: Coin<Asset2>,
        ctx: &mut TxContext
    ): Coin<LiquidityCoin<Asset1, Asset2>> {
        // Retrieve reserves.
        let reserve1 = coin::value(&pair.coin1);
        let reserve2 = coin::value(&pair.coin2);

        // Get deposit amounts.
        let deposit1 = coin::value(&coin1);
        let deposit2 = coin::value(&coin2);

        // Calculate the amount of lp tokens to mint.
        let liquidity: u64;
        let total_supply = coin::total_supply(&pair.lp_treasury_capability);

        // If the total supply is zero, calculate the amount using the inputted token amounts.
        if(total_supply == 0) {
            // Calculate the excess and locked liquidity.
            liquidity = (math::sqrt(deposit1 * deposit2) as u64) - MINIMUM_LIQUIDITY;
            let locked_liquidity = coin::mint<LiquidityCoin<Asset1, Asset2>>(
                &mut pair.lp_treasury_capability, 
                MINIMUM_LIQUIDITY, 
                ctx
            );

            // Permanently lock the first minimum_liquidity tokens.
            coin::join(&mut pair.locked_liquidity, locked_liquidity);

        } else {
            // Otherwise, calculate the amount using the total supply.
            liquidity = (math::min(deposit1 * total_supply / reserve1, deposit2 * total_supply / reserve2) as u64)
        };

        // Ensure that the minted lp tokens are sufficient.
        assert!(liquidity >= MINIMUM_LIQUIDITY, EInsufficientLiquidityMinted);

        // Deposit tokens into the pair.
        coin::join(&mut pair.coin1, coin1);
        coin::join(&mut pair.coin2, coin2);

        // Mint the liquidity tokens and return it, giving it to the caller.
        coin::mint<LiquidityCoin<Asset1, Asset2>>(
            &mut pair.lp_treasury_capability, 
            liquidity, 
            ctx
        )
    }

    // Burn lp tokens to remove liquidity from the pool.
    public fun remove_liquidity<Asset1, Asset2>(
        pair: &mut Pair<Asset1, Asset2>, 
        lp_tokens: Coin<LiquidityCoin<Asset1, Asset2>>,
        ctx: &mut TxContext
    ): (Coin<Asset1>, Coin<Asset2>) {
        // Ensure that the pair exists.
        assert!(exists<Pair<Asset1, Asset2>>(@aubrium), EPairExists);

        // Get reserves from the pool.
        let reserve1 = coin::value(&pair.coin1);
        let reserve2 = coin::value(&pair.coin2);

        // Get amounts to withdraw from the burned lp tokens.
        let lp_token_value = coin::value(&lp_tokens);
        let total_supply = coin::total_supply(&pair.lp_treasury_capability);
        let amount1 = ((lp_token_value * (reserve1) as u64) / total_supply);
        let amount2 = ((lp_token_value * (reserve2) as u64) / total_supply);

        // Ensure that enough liquidity was burned.
        assert!(amount1 > 0 && amount2 > 0, EInsufficientLiquidityBurned);

        // Burn liquidity.
        coin::burn<LiquidityCoin<Asset1, Asset2>>(&mut pair.lp_treasury_capability, lp_tokens);

        // Return the liquidity back to the liquidity provider.
        (
            coin::take<Asset1>(
                coin::balance_mut<Asset1>(&mut pair.coin1), 
                amount1, 
                ctx
            ), 
            coin::take<Asset2>(
                coin::balance_mut<Asset2>(&mut pair.coin2), 
                amount2, 
                ctx
            ), 
        )
    }

    ///*///////////////////////////////////////////////////////////////
    //                          SWAPPING LOGIC                       //
    /////////////////////////////////////////////////////////////////*/

    // Sell asset1 for asset2.
    public fun sell<Asset1, Asset2>(
        pair: &mut Pair<Asset1, Asset2>, 
        coin_in: Coin<Asset1>, min_amount_out: u64, 
        ctx: &mut TxContext
    ): Coin<Asset2> {
        // Get the amount of asset1 being sold.
        let amount_in = coin::value(&coin_in);

        // Get our pair reserves.
        let reserve_in = coin::value(&pair.coin1);
        let reserve_out = coin::value(&pair.coin2);

        // Get the amount of asset2 to buy.
        let amount_out = calculate_amount_out(reserve_in, reserve_out, amount_in);

        // Ensure that the amount of asset2 to buy is sufficient.
        assert!(amount_out >= min_amount_out, EInsufficientOutputAmount);
        assert!(amount_out <= reserve_out, EInsufficientLiquidity);

        // Sell input tokens for output tokens and return them.
        coin::join(&mut pair.coin1, coin_in);
        coin::take<Asset2>(coin::balance_mut<Asset2>(&mut pair.coin2), amount_out, ctx)

    }

    // Buy asset1 for asset2.
    public fun buy<Asset1, Asset2>(
        pair: &mut Pair<Asset1, Asset2>, 
        coin_in: Coin<Asset2>, min_amount_out: u64, 
        ctx: &mut TxContext
    ): Coin<Asset1> {
        // Get the amount of asset1 being sold.
        let amount_in = coin::value(&coin_in);

        // Get our pair reserves.
        let reserve_in = coin::value(&pair.coin2);
        let reserve_out = coin::value(&pair.coin1);

        // Get the amount of asset1 to buy.
        let amount_out = calculate_amount_out(reserve_in, reserve_out, amount_in);

        // Ensure that the amount of asset2 to buy is sufficient.
        assert!(amount_out >= min_amount_out, EInsufficientOutputAmount);
        assert!(amount_out <= reserve_out, EInsufficientLiquidity);

        // Sell input tokens for output tokens and return them.
        coin::join(&mut pair.coin2, coin_in);
        coin::take<Asset1>(coin::balance_mut<Asset1>(&mut pair.coin1), amount_out, ctx)
    }



    // Given the reserves and number of coins being sold, calculate the amount of coins to sell.
    fun calculate_amount_out(reserve_in: u64, reserve_out: u64, amount_in: u64): u64 {
        // Input validation.
        assert!(amount_in > 0, EInsufficientInput);
        assert!(reserve_in > 0 && reserve_out > 0, EInsufficientLiquidity);

        // Calculate the amount of asset2 to buy.
        let amount_in_with_fee = (amount_in as u128) * 997; // 0.3% fee.
        let numerator = amount_in_with_fee * (reserve_out as u128); 
        let denominator = ((reserve_in as u128) * 1000) + amount_in_with_fee;

        // Return the amount of asset2 to buy.
        (numerator/denominator as u64)
    }
}