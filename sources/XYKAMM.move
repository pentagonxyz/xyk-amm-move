module Aubrium::XYKAMM {
    use Std::ASCII;
    use Std::Option;
    use Std::Signer;

    use AptosFramework::Coin::{Self, Coin, BurnCapability, MintCapability};
    
    const MINIMUM_LIQUIDITY: u64 = 1000;

    struct Pair<phantom Asset0Type, phantom Asset1Type> has key {
        coin0: Coin<Asset0Type>,
        coin1: Coin<Asset1Type>,
        mint_capability: MintCapability<LiquidityCoin<Asset0Type, Asset1Type>>,
        burn_capability: BurnCapability<LiquidityCoin<Asset0Type, Asset1Type>>,
        locked_liquidity: Coin<LiquidityCoin<Asset0Type, Asset1Type>>,
        entrancy_locked: bool
    }

    struct LiquidityCoin<phantom Asset0Type, phantom Asset1Type> { }

    struct FlashloanReceipt<phantom Out, phantom Base> {
        amount_out: u64
    }

    public fun accept<Asset0Type, Asset1Type>(root: &signer) {
        // make sure pair does not exist already
        assert!(!exists<Pair<Asset0Type, Asset1Type>>(@Aubrium), 1000); // PAIR_ALREADY_EXISTS
        assert!(!exists<Pair<Asset1Type, Asset0Type>>(@Aubrium), 1000); // PAIR_ALREADY_EXISTS

        // initialize new coin type to represent this pair's liquidity
        // Coin::initialize checks that Signer::address_of(root) == @Aubrium so we don't have to check it here
        let (mint_capability, burn_capability) = Coin::initialize<LiquidityCoin<Asset0Type, Asset1Type>>(
            root,
            ASCII::string(b"XYK AMM LP"),
            ASCII::string(b"XYKLP"),
            18,
            true,
        );

        // create and store new pair
        move_to(root, Pair<Asset0Type, Asset1Type> {
            coin0: Coin::zero<Asset0Type>(),
            coin1: Coin::zero<Asset1Type>(),
            mint_capability,
            burn_capability,
            locked_liquidity: Coin::zero<LiquidityCoin<Asset0Type, Asset1Type>>(),
            entrancy_locked: false
        })
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
            return z
        };
        if (y > 0) 1 else 0
    }

    public fun mint<Asset0Type, Asset1Type>(coin0: Coin<Asset0Type>, coin1: Coin<Asset1Type>): Coin<LiquidityCoin<Asset0Type, Asset1Type>> acquires Pair {
        // get pair reserves
        assert!(exists<Pair<Asset0Type, Asset1Type>>(@Aubrium), 1006); // PAIR_DOES_NOT_EXIST
        let pair = borrow_global_mut<Pair<Asset0Type, Asset1Type>>(@Aubrium);
        assert!(!*&pair.entrancy_locked, 1000); // LOCKED
        let reserve0 = Coin::value(&pair.coin0);
        let reserve1 = Coin::value(&pair.coin1);

        // get deposited amounts
        let amount0 = Coin::value(&coin0);
        let amount1 = Coin::value(&coin1);
        
        // calc liquidity to mint from deposited amounts
        let liquidity;
        let total_supply = *Option::borrow(&Coin::supply<LiquidityCoin<Asset0Type, Asset1Type>>());

        if (total_supply == 0) {
            liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            let locked_liquidity = Coin::mint<LiquidityCoin<Asset0Type, Asset1Type>>(MINIMUM_LIQUIDITY, &pair.mint_capability); // permanently lock the first MINIMUM_LIQUIDITY tokens
            Coin::merge(&mut pair.locked_liquidity, locked_liquidity);
        } else {
            liquidity = min(amount0 * total_supply / reserve0, amount1 * total_supply / reserve1);
        };

        assert!(liquidity > 0, 1001); // INSUFFICIENT_LIQUIDITY_MINTED
        
        // deposit tokens
        Coin::merge(&mut pair.coin0, coin0);
        Coin::merge(&mut pair.coin1, coin1);
        
        // mint liquidity and return it
        Coin::mint<LiquidityCoin<Asset0Type, Asset1Type>>(liquidity, &pair.mint_capability)
    }

    public(script) fun mint_script<Asset0Type, Asset1Type>(account: &signer, amount0: u64, amount1: u64) acquires Pair {
        let coin0 = Coin::withdraw<Asset0Type>(account, amount0);
        let coin1 = Coin::withdraw<Asset1Type>(account, amount1);
        let sender = Signer::address_of(account);
        if (!Coin::is_account_registered<LiquidityCoin<Asset0Type, Asset1Type>>(sender)) Coin::register_internal<LiquidityCoin<Asset0Type, Asset1Type>>(account);
        Coin::deposit(sender, mint(coin0, coin1));
    }

    public fun burn<Asset0Type, Asset1Type>(liquidity: Coin<LiquidityCoin<Asset0Type, Asset1Type>>): (Coin<Asset0Type>, Coin<Asset1Type>) acquires Pair {
        // get pair reserves
        assert!(exists<Pair<Asset0Type, Asset1Type>>(@Aubrium), 1006); // PAIR_DOES_NOT_EXIST
        let pair = borrow_global_mut<Pair<Asset0Type, Asset1Type>>(@Aubrium);
        assert!(!*&pair.entrancy_locked, 1000); // LOCKED
        let reserve0 = Coin::value(&pair.coin0);
        let reserve1 = Coin::value(&pair.coin1);
        
        // get amounts to withdraw from burnt liquidity
        let liquidity_value = Coin::value(&liquidity);
        let total_supply = *Option::borrow(&Coin::supply<LiquidityCoin<Asset0Type, Asset1Type>>());
        let amount0 = liquidity_value * reserve0 / total_supply; // using balances ensures pro-rata distribution
        let amount1 = liquidity_value * reserve1 / total_supply; // using balances ensures pro-rata distribution
        assert!(amount0 > 0 && amount1 > 0, 1002); // INSUFFICIENT_LIQUIDITY_BURNED
        
        // burn liquidity
        Coin::burn(liquidity, &pair.burn_capability);
        
        // withdraw tokens and return
        (Coin::extract(&mut pair.coin0, amount0), Coin::extract(&mut pair.coin1, amount1))
    }

    public(script) fun burn_script<Asset0Type, Asset1Type>(account: &signer, liquidity: u64) acquires Pair {
        let liquidity_coin = Coin::withdraw<LiquidityCoin<Asset0Type, Asset1Type>>(account, liquidity);
        let sender = Signer::address_of(account);
        if (!Coin::is_account_registered<Asset0Type>(sender)) Coin::register_internal<Asset0Type>(account);
        if (!Coin::is_account_registered<Asset1Type>(sender)) Coin::register_internal<Asset1Type>(account);
        let (coin0, coin1) = burn(liquidity_coin);
        Coin::deposit(sender, coin0);
        Coin::deposit(sender, coin1);
    }

    public fun swap<In, Out>(coin_in: Coin<In>, amount_out_min: u64): Coin<Out> acquires Pair {
        // get amount in
        let amount_in = Coin::value(&coin_in);

        // get amount out + deposit + withdraw
        if (exists<Pair<In, Out>>(@Aubrium)) {
            // get pair reserves
            let pair = borrow_global_mut<Pair<In, Out>>(@Aubrium);
            assert!(!*&pair.entrancy_locked, 1000); // LOCKED
            let reserve_in = Coin::value(&pair.coin0);
            let reserve_out = Coin::value(&pair.coin1);

            // get amount out
            let amount_out = get_amount_out_internal(reserve_in, reserve_out, amount_in);

            // validation
            assert!(amount_out > 0 && amount_out >= amount_out_min, 1004); // INSUFFICIENT_OUTPUT_AMOUNT
            assert!(amount_out < reserve_out, 1005); // INSUFFICIENT_LIQUIDITY
        
            // deposit input token, withdraw output tokens, and return them
            Coin::merge(&mut pair.coin0, coin_in);
            Coin::extract(&mut pair.coin1, amount_out)
        } else {
            // assert pair exists
            assert!(exists<Pair<Out, In>>(@Aubrium), 1006); // PAIR_DOES_NOT_EXIST

            // get pair reserves
            let pair = borrow_global_mut<Pair<Out, In>>(@Aubrium);
            assert!(!*&pair.entrancy_locked, 1000); // LOCKED
            let reserve_in = Coin::value(&pair.coin1);
            let reserve_out = Coin::value(&pair.coin0);

            // get amount out
            let amount_out = get_amount_out_internal(reserve_in, reserve_out, amount_in);

            // validation
            assert!(amount_out > 0 && amount_out >= amount_out_min, 1004); // INSUFFICIENT_OUTPUT_AMOUNT
            assert!(amount_out < reserve_out, 1005); // INSUFFICIENT_LIQUIDITY

            // deposit input token, withdraw output tokens, and return them
            Coin::merge(&mut pair.coin1, coin_in);
            Coin::extract(&mut pair.coin0, amount_out)
        }
    }

    public(script) fun swap_script<In, Out>(account: &signer, amount_in: u64, amount_out_min: u64) acquires Pair {
        let coin_in = Coin::withdraw<In>(account, amount_in);
        let sender = Signer::address_of(account);
        if (!Coin::is_account_registered<Out>(sender)) Coin::register_internal<Out>(account);
        Coin::deposit(sender, swap<In, Out>(coin_in, amount_out_min));
    }

    // TODO: add amount_in_max param or expect coin_in param to be split up beforehand?
    public fun swap_to<In, Out>(coin_in: &mut Coin<In>, amount_out: u64): Coin<Out> acquires Pair {
        let amount_in = get_amount_in<In, Out>(amount_out);
        let coin_in_swap = Coin::extract(coin_in, amount_in);
        swap<In, Out>(coin_in_swap, amount_out)
    }

    public(script) fun swap_to_script<In, Out>(account: &signer, amount_out: u64, amount_in_max: u64) acquires Pair {
        let amount_in = get_amount_in<In, Out>(amount_out);
        assert!(amount_in <= amount_in_max, 1000); // EXCESSIVE_INPUT_AMOUNT
        let coin_in = Coin::withdraw<In>(account, amount_in);
        let sender = Signer::address_of(account);
        if (!Coin::is_account_registered<Out>(sender)) Coin::register_internal<Out>(account);
        Coin::deposit(sender, swap<In, Out>(coin_in, amount_out));
    }

    // function that returns tokens and a receipt that must be passed back into repay_out or repay_base along with flashloan repayment
    public fun flashloan<Out, Base>(amount_out: u64): (Coin<Out>, FlashloanReceipt<Out, Base>) acquires Pair {
        // input validation
        assert!(amount_out > 0, 1004); // INSUFFICIENT_OUTPUT_AMOUNT

        // get amount out + deposit + withdraw
        if (exists<Pair<Out, Base>>(@Aubrium)) {
            // get pair reserves
            let pair = borrow_global_mut<Pair<Out, Base>>(@Aubrium);
            assert!(!*&pair.entrancy_locked, 1000); // LOCKED
            let reserve_out = Coin::value(&pair.coin0);

            // validation
            assert!(amount_out < reserve_out, 1005); // INSUFFICIENT_LIQUIDITY

            // prevent reentrancy
            *&mut pair.entrancy_locked = true;
        
            // withdraw output tokens and return them along with receipt
            (Coin::extract(&mut pair.coin0, amount_out), FlashloanReceipt<Out, Base> { amount_out })
        } else {
            // assert pair exists
            assert!(exists<Pair<Base, Out>>(@Aubrium), 1006); // PAIR_DOES_NOT_EXIST

            // get pair reserves
            let pair = borrow_global_mut<Pair<Base, Out>>(@Aubrium);
            assert!(!*&pair.entrancy_locked, 1000); // LOCKED
            let reserve_out = Coin::value(&pair.coin1);

            // validation
            assert!(amount_out < reserve_out, 1005); // INSUFFICIENT_LIQUIDITY

            // prevent reentrancy
            *&mut pair.entrancy_locked = true;

            // withdraw output tokens and return them along with receipt
            (Coin::extract(&mut pair.coin1, amount_out), FlashloanReceipt<Out, Base> { amount_out })
        }
    }

    public fun repay_out<Out, Base>(coin_repay: Coin<Out>, flashloan_receipt: FlashloanReceipt<Out, Base>) acquires Pair {
        // destroy flashloan receipt, get amount sent out, and calc min amount in
        let FlashloanReceipt { amount_out } = flashloan_receipt;
        let min_repay_amount = (amount_out * 1000 / 997) + 1;

        // get amount repaid and ensure it is enough
        let repay_amount = Coin::value(&coin_repay);
        assert!(repay_amount >= min_repay_amount, 1000); // INSUFFICIENT_INPUT_AMOUNT

        // repay flashloan
        if (exists<Pair<Out, Base>>(@Aubrium)) {
            let pair = borrow_global_mut<Pair<Out, Base>>(@Aubrium);
            *&mut pair.entrancy_locked = false;
            Coin::merge(&mut pair.coin0, coin_repay);
        } else {
            assert!(exists<Pair<Base, Out>>(@Aubrium), 1006); // PAIR_DOES_NOT_EXIST
            let pair = borrow_global_mut<Pair<Base, Out>>(@Aubrium);
            *&mut pair.entrancy_locked = false;
            Coin::merge(&mut pair.coin1, coin_repay);
        }
    }

    public fun repay_base<Out, Base>(coin_repay: Coin<Base>, flashloan_receipt: FlashloanReceipt<Out, Base>) acquires Pair {
        // destroy flashloan receipt, get amount sent out, and calc min amount in
        let FlashloanReceipt { amount_out } = flashloan_receipt;
        let min_repay_amount = get_amount_in<Base, Out>(amount_out);

        // get amount in
        let repay_amount = Coin::value(&coin_repay);
        assert!(repay_amount >= min_repay_amount, 1000); // INSUFFICIENT_INPUT_AMOUNT

        // repay flashloan
        if (exists<Pair<Out, Base>>(@Aubrium)) {
            let pair = borrow_global_mut<Pair<Out, Base>>(@Aubrium);
            *&mut pair.entrancy_locked = false;
            Coin::merge(&mut pair.coin1, coin_repay);
        } else {
            assert!(exists<Pair<Base, Out>>(@Aubrium), 1006); // PAIR_DOES_NOT_EXIST
            let pair = borrow_global_mut<Pair<Base, Out>>(@Aubrium);
            *&mut pair.entrancy_locked = false;
            Coin::merge(&mut pair.coin0, coin_repay);
        }
    }

    public fun get_reserves<In, Out>(): (u64, u64) acquires Pair {
        let reserve_in;
        let reserve_out;

        if (exists<Pair<In, Out>>(@Aubrium)) {
            let pair = borrow_global_mut<Pair<In, Out>>(@Aubrium);
            reserve_in = Coin::value(&pair.coin0);
            reserve_out = Coin::value(&pair.coin1);
        } else {
            assert!(exists<Pair<Out, In>>(@Aubrium), 1006); // PAIR_DOES_NOT_EXIST
            let pair = borrow_global_mut<Pair<Out, In>>(@Aubrium);
            reserve_in = Coin::value(&pair.coin1);
            reserve_out = Coin::value(&pair.coin0);
        };

        (reserve_in, reserve_out)
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    fun get_amount_out_internal(reserve_in: u64, reserve_out: u64, amount_in: u64): u64 {
        // validation
        assert!(amount_in > 0, 1004); // INSUFFICIENT_INPUT_AMOUNT
        assert!(reserve_in > 0 && reserve_out > 0, 1005); // INSUFFICIENT_LIQUIDITY

        // calc amount out
        let amount_in_with_fee = amount_in * 997;
        let numerator = amount_in_with_fee * reserve_out;
        let denominator = (reserve_in * 1000) + amount_in_with_fee;
        numerator / denominator
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    public fun get_amount_out<In, Out>(amount_in: u64): u64 acquires Pair {
        // get pair reserves
        let (reserve_in, reserve_out) = get_reserves<In, Out>();

        // return amount out
        get_amount_out_internal(reserve_in, reserve_out, amount_in)
    }

    // given an output amount of an asset, returns a required input amount of the other asset
    public fun get_amount_in<In, Out>(amount_out: u64): u64 acquires Pair {
        // validation
        assert!(amount_out > 0, 1004); // INSUFFICIENT_OUTPUT_AMOUNT

        // get pair reserves
        let (reserve_in, reserve_out) = get_reserves<In, Out>();
        assert!(reserve_in > 0 && reserve_out > 0, 1005); // INSUFFICIENT_LIQUIDITY

        // calc amount in
        let numerator = reserve_in * amount_out * 1000;
        let denominator = reserve_out - (amount_out * 997);
        (numerator / denominator) + 1
    }

    // returns 1 if found Pair<Asset0Type, Asset1Type>, 2 if found Pair<Asset1Type, Asset0Type>, or 0 if pair does not exist
    // for use with mint and burn functions--we must know the correct pair asset ordering
    public fun find_pair<Asset0Type, Asset1Type>(): u8 {
        if (exists<Pair<Asset0Type, Asset1Type>>(@Aubrium)) return 1;
        if (exists<Pair<Asset1Type, Asset0Type>>(@Aubrium)) return 2;
        0
    }

    public(script) fun accept_script<Asset0Type, Asset1Type>(root: &signer) {
        accept<Asset0Type, Asset1Type>(root)
    }

    public(script) fun get_reserves_script<In, Out>(): (u64, u64) acquires Pair {
        get_reserves<In, Out>()
    }

    public(script) fun get_amount_out_script<In, Out>(amount_in: u64): u64 acquires Pair {
        get_amount_out<In, Out>(amount_in)
    }

    public(script) fun get_amount_in_script<In, Out>(amount_out: u64): u64 acquires Pair {
        get_amount_in<In, Out>(amount_out)
    }

    public(script) fun find_pair_script<Asset0Type, Asset1Type>(): u8 {
        find_pair<Asset0Type, Asset1Type>()
    }

    #[test_only]
    struct FakeMoneyA { }

    #[test_only]
    struct FakeMoneyB { }

    #[test_only]
    struct FakeMoneyCapabilities<phantom FakeMoneyType> has key {
        mint_cap: MintCapability<FakeMoneyType>,
        burn_cap: BurnCapability<FakeMoneyType>,
    }

    #[test(root = @Aubrium, coin_creator = @0x1000)]
    public(script) fun end_to_end(root: signer, coin_creator: signer) acquires Pair {
        // init 2 fake coins
        let (mint_cap_a, burn_cap_a) = Coin::initialize<FakeMoneyA>(
            &coin_creator,
            ASCII::string(b"Fake Money A"),
            ASCII::string(b"FMA"),
            6,
            true
        );

        let (mint_cap_b, burn_cap_b) = Coin::initialize<FakeMoneyB>(
            &coin_creator,
            ASCII::string(b"Fake Money B"),
            ASCII::string(b"FMB"),
            6,
            true
        );

        // mint liquidity
        let coin0 = Coin::mint<FakeMoneyA>(50000000, &mint_cap_a);
        let coin1 = Coin::mint<FakeMoneyB>(100000000, &mint_cap_b);
        let liquidity = mint(coin0, coin1);
        assert!(Coin::value(&liquidity) == 70709678, 1000);

        // mint more liquidity
        let coin0 = Coin::mint<FakeMoneyA>(50000000, &mint_cap_a);
        let coin1 = Coin::mint<FakeMoneyB>(100000000, &mint_cap_b);
        let liquidity2 = mint(coin0, coin1);
        assert!(Coin::value(&liquidity2) == 70710678, 1000);

        // swap A to B
        let coin0_in = Coin::mint<FakeMoneyA>(10000000, &mint_cap_a);
        let coin1_out = swap<FakeMoneyA, FakeMoneyB>(coin0_in, 0);
        assert!(Coin::value(&coin1_out) == 18132217, 1000);

        // swap B to A
        let coin0_out = swap<FakeMoneyB, FakeMoneyA>(coin1_out, 0);
        assert!(Coin::value(&coin0_out) == 9945506, 1000);

        // merge and burn liquidity
        Coin::merge(&mut liquidity, liquidity2);
        let (coin0_from_burning, coin1_from_burning) = burn(liquidity);
        assert!(Coin::value(&coin0_from_burning) == 100053786, 1000); // 100054494 * ((70709678 + 70710678) / (70710678 * 2))
        assert!(Coin::value(&coin1_from_burning) == 200000000, 1000);

        // clean up: we can't drop coins so we burn them
        Coin::burn(coin0_out, &burn_cap_a);
        Coin::burn(coin0_from_burning, &burn_cap_a);
        Coin::burn(coin1_from_burning, &burn_cap_b);

        // clean up: we can't drop mint/burn caps so we store them
        move_to(&coin_creator, FakeMoneyCapabilities<FakeMoneyA>{
            mint_cap: mint_cap_a,
            burn_cap: burn_cap_a,
        });
        move_to(&coin_creator, FakeMoneyCapabilities<FakeMoneyB>{
            mint_cap: mint_cap_b,
            burn_cap: burn_cap_b,
        });
    }
}
