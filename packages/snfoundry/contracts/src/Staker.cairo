use openzeppelin_token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IStaker<T> {
    // Core functions
    fn execute(ref self: T);
    fn stake(ref self: T, amount: u256);
    fn withdraw(ref self: T);
    fn on_receive(ref self: T, amount: u256);
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
        self.deadline.write(get_block_timestamp() + (72*60*60));

    }

    #[abi(embed_v0)]
    impl StakerImpl of IStaker<ContractState> {
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
            
            assert!(self.time_left()>0, "Staking period has ended");
            token.transferFrom(sender, contract_address, amount);
            
            // Update internal balances
            let current_balance = self.balances.read(sender);
            self.balances.write(sender, current_balance + amount);
            self.balances.write(get_contract_address(), self.total_balance() + amount);
            // Emit stake event
            self.emit(Stake { sender, amount });
        }

        fn execute(ref self: ContractState) {
            self.not_completed();
            assert!(self.time_left()<=0, "Staking period has not ended");

            let total_balance = self.total_balance();
            let threshold = self.threshold();

            if total_balance >= threshold {
                self.complete_transfer(total_balance);
            } else {
                self.open_for_withdraw.write(true);
            }
        }

        fn withdraw(ref self: ContractState) {
            self.not_completed();
            assert!(self.open_for_withdraw(), "Withdraw is not open");
            let sender = get_caller_address();
            let amount = self.balances.read(sender);
            assert!(amount > 0, "No balance to withdraw");

            let token = self.eth_token_dispatcher();
            token.transfer(sender, amount);
            self.balances.write(sender, 0);
            self.balances.write(get_contract_address(), self.total_balance() - amount);

        }

        fn on_receive(ref self: ContractState, amount: u256) {
            self.stake(amount);
        }

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

        fn completed(self: @ContractState) -> bool {
            IExampleExternalContractDispatcher{contract_address: self.example_external_contract()}.completed()
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
        fn not_completed(ref self: ContractState) {
            assert!(!self.completed(), "External contract already completed");
        }
    }
}