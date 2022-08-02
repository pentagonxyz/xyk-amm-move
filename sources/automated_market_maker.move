// Constant product AMM (like Uniswap V2) for swapping Coin objects.
module aubrium::automated_market_maker{
    use sui::transfer::{Self};
    use sui::object::{Self, ID, Info};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin, TreasuryCap};

    
    ///*///////////////////////////////////////////////////////////////
    //                         MAIN OBJECTS                          //
    /////////////////////////////////////////////////////////////////*/

    // Minimum liquidity required in a pool.
    const MINIMUM_LIQUIDITY: u64 = 1000;

    // Represents a pool/pair of two contracts that can be exchanged for one another.
    struct Pair<phantom Asset1, phantom Asset2> has key, store {
        coin1: Coin<Asset1>,
        coin2: Coin<Asset2>,
        locked_liquidity: Coin<LiquidityCoin<Asset1, Asset2>>,
        lp_treasury_capability: TreasuryCap<LiquidityCoin<Asset1, Asset2>>,
        entrancy_locked: bool
    }

    // Object used to name/represent lp tokens.
    struct LiquidityCoin<phantom Asset1, phantom Asset2> has drop { }

    ///*///////////////////////////////////////////////////////////////
    //                        FLASH LOAN OBJECTS                     //
    /////////////////////////////////////////////////////////////////*/

    // Represents a flashloan receipt. Since it does not implement any abilities, it cannot be
    // stored or transferred. It also cannot be destroyed by anyone other than this module,
    // which means that the only way to get rid of it (and avoid the tx from reverting)
    // is to call the `repay` function.
    struct FlashloanReceipt {
        amount_out: u64,
    }

    ///*///////////////////////////////////////////////////////////////
    //                           ERROR CODES                         //
    /////////////////////////////////////////////////////////////////*/

    // Attempt to create a pair with the same assets as an existing pair.
    const EPairExists: u64 = 0;

    
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
            coin1: coin::zero<Asset1>(ctx),
            coin2: coin::zero<Asset2>(ctx),
            locked_liquidity: coin::zero<LiquidityCoin<Asset1, Asset2>>(ctx),
            lp_treasury_capability,
            entrancy_locked: false
        };

        // Make the pair object shared so that it can be accessed by anyone. 
        transfer::share_object(pair);
    }

}