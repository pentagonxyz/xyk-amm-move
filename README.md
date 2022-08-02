# Aubrium: An Constant Product AMM on SUI

Aubrium is a constant product AMM (like Uniswap V2) built in Sui Move (for the Sui Blockchain) for swapping `Coins`

## Public Functions

### Initialize Pair

- `public fun accept<Asset0Type, Asset1Type>(root: &signer)`

### Mint and Burn Liquidity

- `public fun mint<Asset0Type, Asset1Type>(coin0: Coin<Asset0Type>, coin1: Coin<Asset1Type>): Coin<LiquidityCoin<Asset0Type, Asset1Type>> acquires Pair`
- `public fun burn<Asset0Type, Asset1Type>(liquidity: Coin<LiquidityCoin<Asset0Type, Asset1Type>>): (Coin<Asset0Type>, Coin<Asset1Type>) acquires Pair`

### Swaps

- `public fun swap<In, Out>(coin_in: Coin<In>, amount_out_min: u64): Coin<Out> acquires Pair`
- `public fun swap_to<In, Out>(coin_in: &mut Coin<In>, amount_out: u64): Coin<Out> acquires Pair`

### Flashloans

- `public fun flashloan<Out, Base>(amount_out: u64): (Coin<Out>, FlashloanReceipt<Out, Base>) acquires Pair`
- `public fun repay_out<Out, Base>(coin_repay: Coin<Out>, flashloan_receipt: FlashloanReceipt<Out, Base>) acquires Pair`
- `public fun repay_base<Out, Base>(coin_repay: Coin<Base>, flashloan_receipt: FlashloanReceipt<Out, Base>) acquires Pair`

### View Functions

- `public fun get_reserves<In, Out>(): (u64, u64) acquires Pair`
- `public fun get_amount_out<In, Out>(amount_in: u64): u64 acquires Pair`
- `public fun get_amount_in<In, Out>(amount_out: u64): u64 acquires Pair`
- `public fun find_pair<Asset0Type, Asset1Type>(): u8`
