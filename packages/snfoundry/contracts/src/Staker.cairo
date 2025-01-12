use openzeppelin_token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IStaker<T> {
    // Core functions
    fn execute(ref self: T);
    fn stake(ref self: T, amount: u256);
    fn withdraw(ref self: T);
    // Getters
    fn balances(self: @T, account: ContractAddress) -> u256;
    fn completed(self: @T) -> bool;
    fn deadline(self: @T) -> u64;
    fn example_external_contract(self: @T) -> ContractAddress;
    fn open_for_withdraw(self: @T) -> bool;
    fn eth_token_dispatcher(self: @T) -> IERC20CamelDispatcher;
    fn threshold(self: @T) -> u256;
    fn total_balance(self: @T) -> u256;
    fn time_left(self: @T) -> u64;
}

#[starknet::contract]
pub mod Staker {
    use contracts::ExampleExternalContract::{
        IExampleExternalContractDispatcher, IExampleExternalContractDispatcherTrait,
    };
    use starknet::storage::Map;
    use starknet::{get_block_timestamp, get_caller_address, get_contract_address};
    use super::{ContractAddress, IERC20CamelDispatcher, IERC20CamelDispatcherTrait, IStaker};

    const THRESHOLD: u256 = 1000000000000000000; // ONE_ETH_IN_WEI: 10 ^ 18;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Stake: Stake,
    }

    #[derive(Drop, starknet::Event)]
    struct Stake {
        #[key]
        sender: ContractAddress,
        amount: u256,
    }

    #[storage]
    struct Storage {
        eth_token_dispatcher: IERC20CamelDispatcher,
        balances: Map<ContractAddress, u256>,
        deadline: u64,
        open_for_withdraw: bool,
        external_contract_address: ContractAddress,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        eth_contract: ContractAddress,
        external_contract_address: ContractAddress,
    ) {
        self.eth_token_dispatcher.write(IERC20CamelDispatcher { contract_address: eth_contract });
        self.external_contract_address.write(external_contract_address);
        self.deadline.write(get_block_timestamp() + 1);

    }

    #[abi(embed_v0)]
    impl StakerImpl of IStaker<ContractState> {
        // ToDo Checkpoint 3: Assert that the staking period has not ended
        fn stake(
            ref self: ContractState, amount: u256,
        ) { 
            let sender = get_caller_address();
            let contract_address = get_contract_address();
            
            let token = self.eth_token_dispatcher();
            let sender_balance = token.balanceOf(sender);
            assert(sender_balance >= amount, 'Insufficient balance');
            
            let allowance = token.allowance(sender, contract_address);
            assert(allowance >= amount, 'Insufficient allowance');

            token.transferFrom(sender, contract_address, amount);
            
            // Update internal balances
            let current_balance = self.balances.read(sender);
            self.balances.write(sender, current_balance + amount);
            self.balances.write(get_contract_address(), self.total_balance() + amount);
            // Emit stake event
            self.emit(Stake { sender, amount });
        }

        // Function to execute the transfer or allow withdrawals after the deadline
        // ToDo Checkpoint 3: Assert that the staking period has ended
        // ToDo Checkpoint 3: Protect the function calling `not_completed` function before the
        // execution
        fn execute(ref self: ContractState) {
            assert!(self.time_left()<=0, "Staking period has not ended");
            let total_balance = self.total_balance();
            let threshold = self.threshold();
            assert!(total_balance >= threshold, "Total balance is less than threshold");
            if total_balance >= threshold {
                self.complete_transfer(total_balance);
            } else {
                self.open_for_withdraw.write(true);
            }
        }

        // ToDo Checkpoint 3: Implement your `withdraw` function here
        fn withdraw(ref self: ContractState) {}

        fn balances(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn total_balance(self: @ContractState) -> u256 {
            self.balances.read(get_contract_address())
        }

        fn deadline(self: @ContractState) -> u64 {
            self.deadline.read()
        }

        fn threshold(self: @ContractState) -> u256 {
            THRESHOLD
        }

        fn eth_token_dispatcher(self: @ContractState) -> IERC20CamelDispatcher {
            self.eth_token_dispatcher.read()
        }

        fn open_for_withdraw(self: @ContractState) -> bool {
            self.open_for_withdraw.read()
        }

        fn example_external_contract(self: @ContractState) -> ContractAddress {
            self.external_contract_address.read()
        }
        // Read Function to check if the external contract is completed.
        // ToDo Checkpoint 3: Implement your completed function here
        fn completed(self: @ContractState) -> bool {
            false
        }

        fn time_left(self: @ContractState) -> u64 {
            let deadline = self.deadline();
            let current_time = get_block_timestamp();
            if current_time >= deadline {
                return 0;
            }
            return deadline - current_time;
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn complete_transfer(
            ref self: ContractState, amount: u256,
        ) { // Note: Staker contract should approve to transfer the staked_amount to the external contract
            let external_contract = self.example_external_contract();
            let token = self.eth_token_dispatcher();

            token.transfer(external_contract, amount);
            IExampleExternalContractDispatcher{contract_address: external_contract}.complete();
            self.balances.write(get_contract_address(), 0)
        }
        // ToDo Checkpoint 3: Implement your not_completed function here
        fn not_completed(ref self: ContractState) {}
    }
}