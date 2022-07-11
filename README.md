# Aubrium: An XY=K AMM on Aptos

Aubrium is a constant product (XY=K) AMM (like Uniswap V2) built in Move on Aptos for swapping [`Coin`s](https://github.com/aptos-labs/aptos-core/blob/main/aptos-move/framework/aptos-framework/sources/Coin.move).

## Public Functions

* `public fun accept<Asset0Type, Asset1Type>(root: &signer)`
* `public fun mint<Asset0Type, Asset1Type>(coin0: Coin<Asset0Type>, coin1: Coin<Asset1Type>): Coin<LiquidityCoin<Asset0Type, Asset1Type>> acquires Pair`
* `public fun burn<Asset0Type, Asset1Type>(liquidity: Coin<LiquidityCoin<Asset0Type, Asset1Type>>): (Coin<Asset0Type>, Coin<Asset1Type>) acquires Pair`
* `public fun swap<In, Out>(coin_in: Coin<In>, amount_out_min: u64): Coin<Out> acquires Pair`
* `public fun swap_to<In, Out>(coin_in: &mut Coin<In>, amount_out: u64): Coin<Out> acquires Pair`
* `public fun get_amount_out<In, Out>(amount_in: u64): u64 acquires Pair`
* `public fun get_amount_in<In, Out>(amount_out: u64): u64 acquires Pair`
* `public fun find_pair<Asset0Type, Asset1Type>(): u8`
