address 0x2 {

module Map {
    native struct T<K, V> has copy, drop, store;

    native public fun empty<K, V>(): T<K, V>;

    native public fun get<K, V>(m: &T<K, V>, k: &K): &V;
    native public fun get_mut<K, V>(m: &mut T<K, V>, k: &K): &mut V;

    native public fun contains_key<K, V>(m: &T<K, V>, k: &K): bool;
    // throws on duplicate as I don't feel like mocking up Option
    native public fun insert<K, V>(m: &T<K, V>, k: K, v: V);
    // throws on miss as I don't feel like mocking up Option
    native public fun remove<K, V>(m: &T<K, V>, k: &K): V;
}

}

address 0x2 {

module Token {

    struct Coin<AssetType: copy + drop> has store {
        type: AssetType,
        value: u64,
    }

    // control the minting/creation in the defining module of `ATy`
    public fun create<ATy: copy + drop>(type: ATy, value: u64): Coin<ATy> {
        Coin { type, value }
    }

    public fun value<ATy: copy + drop>(coin: &Coin<ATy>): u64 {
        coin.value
    }

    public fun split<ATy: copy + drop>(coin: Coin<ATy>, amount: u64): (Coin<ATy>, Coin<ATy>) {
        let other = withdraw(&mut coin, amount);
        (coin, other)
    }

    public fun withdraw<ATy: copy + drop>(coin: &mut Coin<ATy>, amount: u64): Coin<ATy> {
        assert!(coin.value >= amount, 10);
        coin.value = coin.value - amount;
        Coin { type: *&coin.type, value: amount }
    }

    public fun join<ATy: copy + drop>(xus: Coin<ATy>, coin2: Coin<ATy>): Coin<ATy> {
        deposit(&mut xus, coin2);
        xus
    }

    public fun deposit<ATy: copy + drop>(coin: &mut Coin<ATy>, check: Coin<ATy>) {
        let Coin { value, type } = check;
        assert!(&coin.type == &type, 42);
        coin.value = coin.value + value;
    }

    public fun destroy_zero<ATy: copy + drop>(coin: Coin<ATy>) {
        let Coin { value, type: _ } = coin;
        assert!(value == 0, 11)
    }

}

}

address 0x4 {

module XYKAMM {
    use Std::Signer;
    use 0x2::Map;
    use 0x2::Token;
    
    const MINIMUM_LIQUIDITY: u64 = 1000;

    struct Pair<Asset0Type: copy + drop, Asset1Type: copy + drop> has key {
        coin0: Token::Coin<Asset0Type>,
        coin1: Token::Coin<Asset1Type>,
        totalSupply: u64
    }

    struct LiquidityAssetType<phantom Asset0Type: copy + drop, phantom Asset1Type: copy + drop> has copy, drop, store {
        pool_owner: address
    }

    fun accept<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(account: &signer, init0: Token::Coin<Asset0Type>, init1: Token::Coin<Asset1Type>) {
        let sender = Signer::address_of(account);
        assert!(!exists<Pair<Asset0Type, Asset1Type>>(sender), 1000); // PAIR_ALREADY_EXISTS
        move_to(account, Pair<Asset0Type, Asset1Type> { coin0: init0, coin1: init1, totalSupply: 0 })
    }

    fun min(x: u64, y: u64): u64 {
        x < y ? x : y
    }
    
    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    fun sqrt(y: u64): u64 {
        if (y > 3) {
            let z = y;
            let x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
            return z;
        } else if (y != 0) {
            return 1;
        }
    }

    public fun mint<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(account: &signer, pool_owner: address, coin0: Token::Coin<Asset0Type>, coin1: Token::Coin<Asset1Type>): Token::Coin<LiquidityAssetType<Asset0Type, Asset1Type>>
        acquires Pair
    {
        // get pair reserves
        let pair = borrow_global_mut<Pair<Asset0Type, Asset1Type>>(pool_owner);
        let reserve0 = Token::value(&pair.coin0);
        let reserve1 = Token::value(&pair.coin1);

        // get deposited amounts
        let amount0 = Token::value(&coin0);
        let amount1 = Token::value(&coin1);
        
        // calc liquidity to mint from deposited amounts
        let liquidity = 0;

        if (pair.totalSupply == 0) {
            liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            increase_total_supply_record<Asset0Type, Asset1Type>(pool_owner, MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = min(amount0 * pair.totalSupply / reserve0, amount1 * pair.totalSupply / reserve1);
        }

        assert!(liquidity > 0, 1001); // INSUFFICIENT_LIQUIDITY_MINTED
        
        // deposit tokens
        Token::deposit(&mut pair.coin0, coin0);
        Token::deposit(&mut pair.coin1, coin1);
        
        // mint liquidity and return it
        mint_liquidity<Asset0Type, Asset1Type>(pool_owner, liquidity);
    }

    public fun burn<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(&mut liquidity: Token::Coin<LiquidityAssetType<Asset0Type, Asset1Type>): (Token::Coin<Asset0Type>, Token::Coin<Asset1Type>)
        acquires Pair
    {
        // get pair reserves
        let pair = borrow_global_mut<Pair<Asset0Type, Asset1Type>>(liquidity.type.pool_owner);
        let reserve0 = Token::value(&pair.coin0);
        let reserve1 = Token::value(&pair.coin1);
        
        // get amounts to withdraw from burnt liquidity
        let liquidityValue = Token::value(&liquidity);
        amount0 = liquidityValue * reserve0 / pair.totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidityValue * reserve1 / pair.totalSupply; // using balances ensures pro-rata distribution
        assert!(amount0 > 0 && amount1 > 0, 1002); // INSUFFICIENT_LIQUIDITY_BURNED
        
        // burn liquidity
        burn_liquidity<Asset0Type, Asset1Type>(&mut liquidity);
        
        // withdraw tokens and return
        (Token::withdraw(&mut pair.coin0, amount0), Token::withdraw(&mut pair.coin1, amount1))
    }
    
    fun mint_liquidity<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(pool_owner: address, amount: u64): Token::Coin<LiquidityAssetType<Asset0Type, Asset1Type>>
        acquires Pair
    {
        increase_total_supply_record<Asset0Type, Asset1Type>(pool_owner, amount);
        Token::create(LiquidityAssetType<Asset0Type, Asset1Type>{pool_owner}, amount)
    }
    
    fun burn_liquidity<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(liquidity: Token::Coin<LiquidityAssetType<Asset0Type, Asset1Type>)
        acquires Pair
    {
        decrease_total_supply_record<Asset0Type, Asset1Type>(liquidity.type.pool_owner, Token::value(&liquidity));
        Token::destroy_zero(&mut liquidity);
    }

    fun increase_total_supply_record<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(pool_owner: address, mint_amount: u64)
        acquires Pair
    {
        let total_supply_ref = &mut borrow_global_mut<Pair<Asset0Type, Asset1Type>>(pool_owner).totalSupply;
        *total_supply_ref = *total_supply_ref + mint_amount
    }

    fun decrease_total_supply_record<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(pool_owner: address, burn_amount: u64)
        acquires Pair
    {
        let total_supply_ref = &mut borrow_global_mut<Pair<Asset0Type, Asset1Type>>(pool_owner).totalSupply;
        *total_supply_ref = *total_supply_ref - burn_amount
    }

    // swap from asset 0 to asset 1 on a pair
    public fun swap_0_to_1<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(pool_owner: address, coin0In: Token::Coin<Asset0Type>): (Token::Coin<Asset1Type>)
        acquires Pair
    {
        // get pair reserves
        let pair = borrow_global_mut<Pair<Asset0Type, Asset1Type>>(pool_owner);
        let reserve0 = Token::value(&pair.coin0);
        let reserve1 = Token::value(&pair.coin1);

        // get deposited amount
        let amount0In = Token::value(&coin0);
        assert!(amount0In > 0, 1003); // INSUFFICIENT_INPUT_AMOUNT
        
        // get amount out based on XY=K invariant
        let amountInWithFee = amount0In * 997;
        let numerator = amountInWithFee * reserve1;
        let denominator = (reserve0 * 1000) + amountInWithFee;
        let amount1Out = numerator / denominator;
        
        // more validation
        assert!(amount1Out > 0, 1004); // INSUFFICIENT_OUTPUT_AMOUNT
        assert!(amount1Out < reserve1, 1005); // INSUFFICIENT_LIQUIDITY
        
        // deposit tokens
        Token::deposit(&mut pair.coin0, coin0In);

        // withdraw tokens and return
        Token::withdraw(&mut pair.coin1, amount1Out)
    }

    // swap from asset 1 to asset 0 on a pair
    public fun swap_1_to_0<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(pool_owner: address, coin1In: Token::Coin<Asset1Type>): (Token::Coin<Asset0Type>)
        acquires Pair
    {
        // get pair reserves
        let pair = borrow_global_mut<Pair<Asset0Type, Asset1Type>>(pool_owner);
        let reserve0 = Token::value(&pair.coin0);
        let reserve1 = Token::value(&pair.coin1);

        // get deposited amount
        let amount1In = Token::value(&coin1);
        assert!(amount1In > 0, 1003); // INSUFFICIENT_INPUT_AMOUNT
        
        // get amount out based on XY=K invariant
        let amountInWithFee = amount1In * 997;
        let numerator = amountInWithFee * reserve0;
        let denominator = (reserve1 * 1000) + amountInWithFee;
        let amount0Out = numerator / denominator;
        
        // more validation
        assert!(amount0Out > 0, 1004); // INSUFFICIENT_OUTPUT_AMOUNT
        assert!(amount0Out < reserve0, 1005); // INSUFFICIENT_LIQUIDITY
        
        // deposit tokens
        Token::deposit(&mut pair.coin1, coin1In);

        // withdraw tokens and return
        Token::withdraw(&mut pair.coin0, amount0Out)
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    public fun get_amount_0_in<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(amount_1_out: u64): u64
        acquires Pair
    {
        // validation
        assert!(amount_1_out > 0, 1004); // INSUFFICIENT_OUTPUT_AMOUNT

        // get pair reserves
        let pair = borrow_global_mut<Pair<Asset0Type, Asset1Type>>(pool_owner);
        let reserve0 = Token::value(&pair.coin0);
        let reserve1 = Token::value(&pair.coin1);
        assert!(reserve0 > 0 && reserve1 > 0, 1005); // INSUFFICIENT_LIQUIDITY

        // calc amount in
        let numerator = reserve0 * amount_1_out * 1000;
        let denominator = reserve1 - (amount_1_out * 997);
        (numerator / denominator) + 1
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    public fun get_amount_1_in<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(amount_0_out: u64): u64
        acquires Pair
    {
        // validation
        assert!(amount_0_out > 0, 1004); // INSUFFICIENT_OUTPUT_AMOUNT

        // get pair reserves
        let pair = borrow_global_mut<Pair<Asset0Type, Asset1Type>>(pool_owner);
        let reserve0 = Token::value(&pair.coin0);
        let reserve1 = Token::value(&pair.coin1);
        assert!(reserve0 > 0 && reserve1 > 0, 1005); // INSUFFICIENT_LIQUIDITY

        // calc amount in
        let numerator = reserve1 * amount_0_out * 1000;
        let denominator = reserve0 - (amount_0_out * 997);
        (numerator / denominator) + 1
    }

    // finds the pair with the most liquidity (returns the pair with highest minimum reserve)
    // returns true for pair 1 or false for pair 0
    public fun maximin_reserves<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(pool_owner: address): (bool, u64, u64)
        acquires Pair
    {
        // make sure both pairs exist
        assert!(exists<Pair<Asset0Type, Asset1Type>>(sender), 1006); // PAIR_0_DOES_NOT_EXIST
        assert!(exists<Pair<Asset1Type, Asset0Type>>(sender), 1007); // PAIR_1_DOES_NOT_EXIST

        // get pair reserves
        let pair0 = borrow_global<Pair<Asset0Type, Asset1Type>>(pool_owner);
        let pair0reserve0 = Token::value(&pair0.coin0);
        let pair0reserve1 = Token::value(&pair0.coin1);
        let pair1 = borrow_global<Pair<Asset1Type, Asset0Type>>(pool_owner);
        let pair1reserve0 = Token::value(&pair1.coin0);
        let pair1reserve1 = Token::value(&pair1.coin1);

        // return pair with highest minimum
        min(pair1reserve0, pair1reserve1) > min(pair0reserve0, pair0reserve1) ? (true, pair1reserve0, pair1reserve1) : (false, pair0reserve0, pair0reserve1)
    }
}

}
