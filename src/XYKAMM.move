module Pentagon::Token {
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

module Pentagon::XYKAMM {
    use Std::Signer;

    use Pentagon::Token;
    
    const MINIMUM_LIQUIDITY: u64 = 1000;

    struct Pair<Asset0Type: copy + drop, Asset1Type: copy + drop> has key {
        coin0: Token::Coin<Asset0Type>,
        coin1: Token::Coin<Asset1Type>,
        totalSupply: u64
    }

    struct LiquidityAssetType<phantom Asset0Type: copy + drop, phantom Asset1Type: copy + drop> has copy, drop, store {
        pool_owner: address
    }

    public fun accept<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(account: &signer, init0: Token::Coin<Asset0Type>, init1: Token::Coin<Asset1Type>) {
        let sender = Signer::address_of(account);
        assert!(!exists<Pair<Asset0Type, Asset1Type>>(sender), 1000); // PAIR_ALREADY_EXISTS
        assert!(!exists<Pair<Asset1Type, Asset0Type>>(sender), 1000); // PAIR_ALREADY_EXISTS
        move_to(account, Pair<Asset0Type, Asset1Type> { coin0: init0, coin1: init1, totalSupply: 0 })
    }

    fun min(x: u64, y: u64): u64 {
        if (x < y) x else y
    }
    
    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    fun sqrt(y: u64): u64 {
        if (y > 3) {
            let z = y;
            let x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            };
            return z;
        } else if (y != 0) {
            return 1;
        }
    }

    public fun mint<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(account: &signer, pool_owner: address, coin0: Token::Coin<Asset0Type>, coin1: Token::Coin<Asset1Type>): Token::Coin<LiquidityAssetType<Asset0Type, Asset1Type>>
        acquires Pair
    {
        // get pair reserves
        assert!(exists<Pair<Asset0Type, Asset1Type>>(pool_owner), 1006); // PAIR_DOES_NOT_EXIST
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
        };

        assert!(liquidity > 0, 1001); // INSUFFICIENT_LIQUIDITY_MINTED
        
        // deposit tokens
        Token::deposit(&mut pair.coin0, coin0);
        Token::deposit(&mut pair.coin1, coin1);
        
        // mint liquidity and return it
        mint_liquidity<Asset0Type, Asset1Type>(pool_owner, liquidity);
    }

    public fun burn<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(liquidity: Token::Coin<LiquidityAssetType<Asset0Type, Asset1Type>>): (Token::Coin<Asset0Type>, Token::Coin<Asset1Type>)
        acquires Pair
    {
        // get pair reserves
        assert!(exists<Pair<Asset0Type, Asset1Type>>(liquidity.type.pool_owner), 1006); // PAIR_DOES_NOT_EXIST
        let pair = borrow_global_mut<Pair<Asset0Type, Asset1Type>>(liquidity.type.pool_owner);
        let reserve0 = Token::value(&pair.coin0);
        let reserve1 = Token::value(&pair.coin1);
        
        // get amounts to withdraw from burnt liquidity
        let liquidity_value = Token::value(&liquidity);
        amount0 = liquidity_value * reserve0 / pair.totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity_value * reserve1 / pair.totalSupply; // using balances ensures pro-rata distribution
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

    public fun swap<In: copy + drop + store, Out: copy + drop + store>(pool_owner: address, coin_in: Token::Coin<In>, amount_out_min: u64): (Token::Coin<Out>)
        acquires Pair
    {
        // get pair reserves
        let reverse_pair = false;
        let pair;
        let reserve_in;
        let reserve_out;

        if (exists<Pair<In, Out>>(pool_owner)) {
            pair = borrow_global_mut<Pair<In, Out>>(pool_owner);
            reserve_in = Token::value(&pair.coin0);
            reserve_out = Token::value(&pair.coin1);
        } else {
            assert!(exists<Pair<Out, In>>(pool_owner), 1006); // PAIR_DOES_NOT_EXIST
            reverse_pair = true;
            pair = borrow_global_mut<Pair<Out, In>>(pool_owner);
            reserve_in = Token::value(&pair.coin1);
            reserve_out = Token::value(&pair.coin0);
        };

        // get deposited amount
        let amount_in = Token::value(&coin_in);
        assert!(amount_in > 0, 1003); // INSUFFICIENT_INPUT_AMOUNT
        
        // get amount out based on XY=K invariant
        let amount_in_with_fee = amount_in * 997;
        let numerator = amount_in_with_fee * reserve_out;
        let denominator = (reserve_in * 1000) + amount_in_with_fee;
        let amount_out = numerator / denominator;
        
        // more validation
        assert!(amount_out > 0 && amount_out >= amount_out_min, 1004); // INSUFFICIENT_OUTPUT_AMOUNT
        assert!(amount_out < reserve_out, 1005); // INSUFFICIENT_LIQUIDITY
        
        // deposit input token, withdraw output tokens, and return them
        if (reverse_pair) {
            Token::deposit(&mut pair.coin1, coin_in);
            return Token::withdraw(&mut pair.coin0, amount_out);
        } else {
            Token::deposit(&mut pair.coin0, coin_in);
            return Token::withdraw(&mut pair.coin1, amount_out);
        }
    }

    public fun swap_to<In: copy + drop + store, Out: copy + drop + store>(pool_owner: address, coin_in: &mut Token::Coin<In>, amount_out: u64): Token::Coin<Out>
        acquires Pair
    {
        let amount_in = get_amount_in<In, Out>(pool_owner, amount_out);
        let coin_in_swap = Token::withdraw(&mut coin_in, amount_in);
        swap<In, Out>(pool_owner, &mut coin_in_swap, amount_out)
    }

    fun get_reserves<In: copy + drop + store, Out: copy + drop + store>(pool_owner: address): (u64, u64)
        acquires Pair
    {
        let reserve_in;
        let reserve_out;

        if (exists<Pair<In, Out>>(pool_owner)) {
            let pair = borrow_global_mut<Pair<In, Out>>(pool_owner);
            reserve_in = Token::value(&pair.coin0);
            reserve_out = Token::value(&pair.coin1);
        } else {
            assert!(exists<Pair<Out, In>>(pool_owner), 1006); // PAIR_DOES_NOT_EXIST
            let pair = borrow_global_mut<Pair<Out, In>>(pool_owner);
            reserve_in = Token::value(&pair.coin1);
            reserve_out = Token::value(&pair.coin0);
        };

        (reserve_in, reserve_out)
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    public fun get_amount_out<In: copy + drop + store, Out: copy + drop + store>(pool_owner: address, amount_in: u64): u64
        acquires Pair
    {
        // validation
        assert!(amount_in > 0, 1004); // INSUFFICIENT_INPUT_AMOUNT

        // get pair reserves
        let (reserve_in, reserve_out) = get_reserves<In, Out>(pool_owner);
        assert!(reserve_in > 0 && reserve_out > 0, 1005); // INSUFFICIENT_LIQUIDITY

        // calc amount out
        let amount_in_with_fee = amount_in * 997;
        let numerator = amount_in_with_fee * reserve_out;
        let denominator = (reserve_in * 1000) + amount_in_with_fee;
        numerator / denominator
    }

    // given an output amount of an asset, returns a required input amount of the other asset
    public fun get_amount_in<In: copy + drop + store, Out: copy + drop + store>(pool_owner: address, amount_out: u64): u64
        acquires Pair
    {
        // validation
        assert!(amount_out > 0, 1004); // INSUFFICIENT_OUTPUT_AMOUNT

        // get pair reserves
        let (reserve_in, reserve_out) = get_reserves<In, Out>(pool_owner);
        assert!(reserve_in > 0 && reserve_out > 0, 1005); // INSUFFICIENT_LIQUIDITY

        // calc amount in
        let numerator = reserve_in * amount_out * 1000;
        let denominator = reserve_out - (amount_out * 997);
        (numerator / denominator) + 1
    }

    // returns 1 if found Pair<Asset0Type, Asset1Type>, 2 if found Pair<Asset1Type, Asset0Type>, or 0 if pair does not exist
    // for use with mint and burn functions--we must know the correct pair asset ordering
    public fun find_pair<Asset0Type: copy + drop + store, Asset1Type: copy + drop + store>(): u8 {
        if (exists<Pair<Asset0Type, Asset1Type>>(pool_owner)) return 1;
        if (exists<Pair<Asset1Type, Asset0Type>>(pool_owner)) return 2;
        return 0;
    }
}
