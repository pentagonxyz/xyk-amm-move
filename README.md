# Aubrium: An Constant Product AMM on Sui and Aptos

Aubrium is a constant product (XY=K) AMM (like Uniswap V2) built in Sui Move and Aptos Move for swapping `coin`s.

## Sui: Public Functions

### Initialize Pair

* `public fun new_pair<Asset1, Asset2>(ctx: &mut TxContext)`

### Mint and Burn Liquidity

* `public fun add_liquidity<Asset1, Asset2>(pair: &mut Pair<Asset1, Asset2>, coin1: Coin<Asset1>, coin2: Coin<Asset2>, ctx: &mut TxContext): Coin<LiquidityCoin<Asset1, Asset2>>`
* `public fun remove_liquidity<Asset1, Asset2>(pair: &mut Pair<Asset1, Asset2>, lp_tokens: Coin<LiquidityCoin<Asset1, Asset2>>, ctx: &mut TxContext): (Coin<Asset1>, Coin<Asset2>)`

### Swaps

* `public fun sell<Asset1, Asset2>(pair: &mut Pair<Asset1, Asset2>, coin_in: Coin<Asset1>, min_amount_out: u64, ctx: &mut TxContext): Coin<Asset2>`
* `public fun buy<Asset1, Asset2>(pair: &mut Pair<Asset1, Asset2>, coin_in: Coin<Asset2>, min_amount_out: u64, ctx: &mut TxContext): Coin<Asset1>`

### View Functions

* `public fun calculate_amount_out(reserve_in: u64, reserve_out: u64, amount_in: u64): u64`

## Aptos: Public Functions

### Initialize Pair

* `public fun accept<Asset0Type, Asset1Type>(root: &signer)`

### Mint and Burn Liquidity

* `public fun mint<Asset0Type, Asset1Type>(coin0: Coin<Asset0Type>, coin1: Coin<Asset1Type>): Coin<LiquidityCoin<Asset0Type, Asset1Type>>`
* `public fun burn<Asset0Type, Asset1Type>(liquidity: Coin<LiquidityCoin<Asset0Type, Asset1Type>>): (Coin<Asset0Type>, Coin<Asset1Type>)`

### Swaps

* `public fun swap<In, Out>(coin_in: Coin<In>, amount_out_min: u64): Coin<Out>`
* `public fun swap_to<In, Out>(coin_in: &mut Coin<In>, amount_out: u64): Coin<Out>`

### Flashloans

* `public fun flashloan<Out, Base>(amount_out: u64): (Coin<Out>, FlashloanReceipt<Out, Base>)`
* `public fun repay_out<Out, Base>(coin_repay: Coin<Out>, flashloan_receipt: FlashloanReceipt<Out, Base>)`
* `public fun repay_base<Out, Base>(coin_repay: Coin<Base>, flashloan_receipt: FlashloanReceipt<Out, Base>)`

### View Functions

* `public fun get_reserves<In, Out>(): (u64, u64)`
* `public fun get_amount_out<In, Out>(amount_in: u64): u64`
* `public fun get_amount_in<In, Out>(amount_out: u64): u64`
* `public fun find_pair<Asset0Type, Asset1Type>(): u8`
