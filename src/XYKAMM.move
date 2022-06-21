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

    struct LiquidityRecord<phantom Asset0Type: copy + drop, phantom Asset1Type: copy + drop> has key {
        // pool owner => amount
        record: Map::T<address, u64>
    }

    fun accept<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(account: &signer, init0: Token::Coin<Asset0Type>, init1: Token::Coin<Asset1Type>) {
        let sender = Signer::address_of(account);
        assert!(!exists<Pair<Asset0Type, Asset1Type>>(sender), 1000);
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

    public fun mint<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(account: &signer, pool_owner: address, coin0: Token::Coin<Asset0Type>, coin1: Token::Coin<Asset1Type>): u64
        acquires Pair, LiquidityRecord
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
        
        // mint liquidity and return minted quantity
        mint_liquidity<Asset0Type, Asset1Type>(account, pool_owner, liquidity);
        liquidity
    }

    public fun burn<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(account: &signer, pool_owner: address, liquidity: u64): (Token::Coin<Asset0Type>, Token::Coin<Asset1Type>)
        acquires Pair, LiquidityRecord
    {
        // get pair reserves
        let pair = borrow_global_mut<Pair<Asset0Type, Asset1Type>>(pool_owner);
        let reserve0 = Token::value(&pair.coin0);
        let reserve1 = Token::value(&pair.coin1);
        
        // get amounts to withdraw from burnt liquidity
        amount0 = liquidity * reserve0 / pair.totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity * reserve1 / pair.totalSupply; // using balances ensures pro-rata distribution
        assert!(amount0 > 0 && amount1 > 0, 1002); // INSUFFICIENT_LIQUIDITY_BURNED
        
        // burn liquidity
        burn_liquidity<Asset0Type, Asset1Type>(account, pool_owner, liquidity);
        
        // withdraw tokens and return
        (Token::withdraw(&mut pair.coin0, amount0), Token::withdraw(&mut pair.coin1, amount1))
    }
    
    fun mint_liquidity<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(account: &signer, pool_owner: address, amount: u64)
        acquires Pair, LiquidityRecord
    {
        increase_total_supply_record<Asset0Type, Asset1Type>(pool_owner, amount);
        increase_liquidity_record<Asset0Type, Asset1Type>(account, pool_owner, amount);
    }
    
    fun burn_liquidity<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(account: &signer, pool_owner: address, amount: u64)
        acquires Pair, LiquidityRecord
    {
        decrease_total_supply_record<Asset0Type, Asset1Type>(pool_owner, amount);
        decrease_liquidity_record<Asset0Type, Asset1Type>(account, pool_owner, amount);
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

    fun increase_liquidity_record<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(account: &signer, pool_owner: address, amount: u64)
        acquires LiquidityRecord
    {
        let sender = Signer::address_of(account);
        if (!exists<LiquidityRecord<Asset0Type, Asset1Type>>(sender)) {
            move_to(account, LiquidityRecord<Asset0Type, Asset1Type> { record: Map::empty() })
        };
        let record = &mut borrow_global_mut<LiquidityRecord<Asset0Type, Asset1Type>>(sender).record;
        if (Map::contains_key(record, &pool_owner)) {
            let old_amount = Map::remove(record, &pool_owner);
            amount = amount + old_amount;
        };
        Map::insert(record, pool_owner, amount)
    }

    fun decrease_liquidity_record<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(account: &signer, pool_owner: address, amount: u64)
        acquires LiquidityRecord
    {
        let sender = Signer::address_of(account);
        let record = &mut borrow_global_mut<LiquidityRecord<Asset0Type, Asset1Type>>(sender).record;
        let old_amount = Map::remove(record, &pool_owner);
        amount = old_amount - amount;
        Map::insert(record, pool_owner, amount)
    }
    
    public fun swap<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(pool_owner: address, coin0In: Token::Coin<Asset0Type>, coin1In: Token::Coin<Asset1Type>, amount0Out: u64, amount1Out: u64): (Token::Coin<Asset0Type>, Token::Coin<Asset1Type>)
        acquires Pair
    {
        // input validation
        assert!(amount0Out > 0 || amount1Out > 0, 1003); // INSUFFICIENT_OUTPUT_AMOUNT
        
        // get pair reserves
        let pair = borrow_global_mut<Pair<Asset0Type, Asset1Type>>(pool_owner);
        let reserve0 = Token::value(&pair.coin0);
        let reserve1 = Token::value(&pair.coin1);
        
        // more validation
        assert!(amount0Out < reserve0 && amount1Out < reserve1, 1004); // INSUFFICIENT_LIQUIDITY

        // get deposited amounts
        let amount0In = Token::value(&coin0);
        let amount1In = Token::value(&coin1);
        
        // more validation
        assert!(amount0In > 0 || amount1In > 0, 1005); // INSUFFICIENT_INPUT_AMOUNT
        
        // validate XY=K
        let balance0 = reserve0 + amount0In - amount0Out;
        let balance1 = reserve1 + amount1In - amount1Out;
        let balance0Adjusted = balance0 * 1000 - (amount0In * 3);
        let balance1Adjusted = balance1 * 1000 - (amount1In * 3);
        assert!(balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1000000, 1006); // K
        
        // deposit tokens
        Token::deposit(&mut pair.coin0, coin0In);
        Token::deposit(&mut pair.coin1, coin1In);

        // withdraw tokens and return
        (Token::withdraw(&mut pair.coin0, amount0Out), Token::withdraw(&mut pair.coin1, amount1Out))
    }
}

}
