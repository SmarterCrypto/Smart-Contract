pragma solidity ^0.4.11;
contract STC is StandardToken {
    // FIELDS
    string public name = "SmarterThanCrypto";
    string public symbol = "STC";
    uint256 public decimals = 18;
    string public version = "9.0";
    uint256 public tokenCap = 100000000 * 10**18;
    // crowdsale parameters
	uint256 public fundingStartTime;
    uint256 public fundingEndTime;
    // vesting fields
    address public vestingContract;
    bool private vestingSet = false;
    // root control
    address public fundWallet;
    // control of liquidity and limited control of updatePrice
    address public controlWallet;
    // time to wait between controlWallet price updates
    uint256 public waitTime = 1 hours;
    // fundWallet controlled state variables
    // halted: halt buying due to emergency, tradeable: signal that assets have been acquired
    bool public halted = false;
    bool public tradeable = false;
    // -- totalSupply defined in StandardToken
    // -- mapping to token balances done in StandardToken
    uint256 public previousUpdateTime = 0;
    Price public currentPrice;
    uint256 public minAmount = 0.04 ether;
    uint256 public OfferTime = 2592000;
 

    // map participant address to a withdrawal request
    mapping (address => Withdrawal) public withdrawals;
    // maps previousUpdateTime to the next price
    mapping (uint256 => Price) public prices;
    // maps addresses
    mapping (address => bool) public whitelist;
    // TYPES
    struct Price { // tokensPerEth
        uint256 numerator;
        uint256 denominator;
    }
    struct Withdrawal {
        uint256 tokens;
        uint256 time; // time for each withdrawal is set to the previousUpdateTime
    }

    // EVENTS
    event Buy(address indexed participant, address indexed beneficiary, uint256 ethValue, uint256 amountTokens);
    event AllocatePresale(address indexed participant, uint256 amountTokens);
    event Whitelist(address indexed participant);
    event PriceUpdate(uint256 numerator, uint256 denominator);
    event AddLiquidity(uint256 ethAmount);
    event RemoveLiquidity(uint256 ethAmount);
    event WithdrawRequest(address indexed participant, uint256 amountTokens);
    event Withdraw(address indexed participant, uint256 amountTokens, uint256 etherAmount);
    // MODIFIERS
    modifier isTradeable { // exempt vestingContract and fundWallet to allow dev allocations
        require(tradeable || msg.sender == fundWallet || msg.sender == vestingContract);
        _;
    }
    modifier onlyWhitelist {
        require(whitelist[msg.sender]);
        _;
    }
    modifier onlyFundWallet {
        require(msg.sender == fundWallet);
        _;
    }
    modifier onlyManagingWallets {
        require(msg.sender == controlWallet || msg.sender == fundWallet);
        _;
    }
    modifier only_if_controlWallet {
        if (msg.sender == controlWallet) _;
    }
    modifier require_waited {
        require(safeSub(now, waitTime) >= previousUpdateTime);
        _;
    }
    modifier only_if_increase (uint256 newNumerator) {
        if (newNumerator > currentPrice.numerator) _;
    }
    // CONSTRUCTOR
    function STC(address controlWalletInput, uint256 priceNumeratorInput, uint256 startTimeInput, uint256 endTimeInput) {
        require(controlWalletInput != address(0));
        require(priceNumeratorInput > 0);
        require(endTimeInput > startTimeInput);
        fundWallet = msg.sender;
        controlWallet = controlWalletInput;
        whitelist[fundWallet] = true;
        whitelist[controlWallet] = true;
        currentPrice = Price(priceNumeratorInput, 10000); // 1 token = 1 usd at ICO start
        fundingStartTime = startTimeInput;
        fundingEndTime = endTimeInput;
        previousUpdateTime = now;
    }
	
	function GetTime() public constant returns(uint256)  {
       return now;
    }
		
    // METHODS	
	function setOfferTime(uint256 newOfferTime) external onlyFundWallet {
		require(newOfferTime>0);
		require(newOfferTime<safeSub(fundingEndTime,fundingStartTime));
		OfferTime = newOfferTime;
    }
	
    function setVestingContract(address vestingContractInput) external onlyFundWallet {
        require(vestingContractInput != address(0));
        vestingContract = vestingContractInput;
        whitelist[vestingContract] = true;
        vestingSet = true;
    }
    // allows controlWallet to update the price within a time contstraint, allows fundWallet complete control
    function updatePrice(uint256 newNumerator) external onlyManagingWallets {
        require(newNumerator > 0);
        require_limited_change(newNumerator);
        // either controlWallet command is compliant or transaction came from fundWallet
        currentPrice.numerator = newNumerator;
        // maps time to new Price (if not during ICO)
        prices[previousUpdateTime] = currentPrice;
        previousUpdateTime = now;
        PriceUpdate(newNumerator, currentPrice.denominator);
    }
    function require_limited_change (uint256 newNumerator)
        private
        only_if_controlWallet
        require_waited
        only_if_increase(newNumerator)
    {
        uint256 percentage_diff = 0;
        percentage_diff = safeMul(newNumerator, 1000) / currentPrice.numerator;
        percentage_diff = safeSub(percentage_diff, 1000);
        // controlWallet can only increase price by max 20% and only every waitTime
        //require(percentage_diff <= 20);
    }
    function updatePriceDenominator(uint256 newDenominator) external onlyFundWallet {
        require(GetTime() > fundingEndTime);
        require(newDenominator > 0);
        currentPrice.denominator = newDenominator;
        // maps time to new Price
        prices[previousUpdateTime] = currentPrice;
        previousUpdateTime = now;
        PriceUpdate(currentPrice.numerator, newDenominator);
    }
    function allocateTokens(address participant, uint256 amountTokens) private {
        require(vestingSet);
        // 13% of total allocated for PR, Marketing, Team, Advisors
        uint256 developmentAllocation = safeMul(amountTokens, 14942528735632200) / 100000000000000000;
        // check that token cap is not exceeded
        uint256 newTokens = safeAdd(amountTokens, developmentAllocation);
        require(safeAdd(totalSupply, newTokens) <= tokenCap);
        // increase token supply, assign tokens to participant
        totalSupply = safeAdd(totalSupply, newTokens);
        balances[participant] = safeAdd(balances[participant], amountTokens);
        balances[vestingContract] = safeAdd(balances[vestingContract], developmentAllocation);
    }
    function allocatePresaleTokens(address participant, uint amountTokens) external onlyFundWallet {
        require(GetTime() < fundingEndTime);
        require(participant != address(0));
        whitelist[participant] = true; // automatically whitelist accepted presale
        allocateTokens(participant, amountTokens);
        Whitelist(participant);
        AllocatePresale(participant, amountTokens);
    }
    function verifyParticipant(address participant) external onlyManagingWallets {
        whitelist[participant] = true;
        Whitelist(participant);
    }
    function buy() external payable {
        buyTo(msg.sender);
    }
    function buyTo(address participant) public payable onlyWhitelist {
        require(!halted);
        require(participant != address(0));
        require(msg.value >= minAmount);
        require(GetTime() >= fundingStartTime && GetTime() < fundingEndTime);
        uint256 icoDenominator = icoDenominatorPrice();
         uint256 tokensToBuy = safeMul(msg.value, currentPrice.numerator) / icoDenominator;
        allocateTokens(participant, tokensToBuy);
        // send ether to fundWallet
        fundWallet.transfer(msg.value);
        Buy(msg.sender, participant, msg.value, tokensToBuy);
    }
    // time based on blocknumbers, assuming a blocktime of 30s
    function icoDenominatorPrice() public constant returns (uint256) {
        uint256 icoDuration = safeSub(GetTime(), fundingStartTime);
        uint256 denominator;
        if (icoDuration < 172800) { // time in sec = (48*60*60) = 172800
		   denominator = safeMul(currentPrice.denominator, 95) / 100;
           return denominator;
        } else if (icoDuration < OfferTime ) { // time in sec = (((4*7)+2)*24*60*60) = 2592000
            denominator = safeMul(currentPrice.denominator, 100) / 100;
           return denominator;
        } else {
            denominator = safeMul(currentPrice.denominator, 105) / 100;
           return denominator;
        }
    }
    function requestWithdrawal(uint256 amountTokensToWithdraw) external isTradeable onlyWhitelist {
        require(GetTime() > fundingEndTime);
        require(amountTokensToWithdraw > 0);
        address participant = msg.sender;
        require(balanceOf(participant) >= amountTokensToWithdraw);
        require(withdrawals[participant].tokens == 0); // participant cannot have outstanding withdrawals
        balances[participant] = safeSub(balances[participant], amountTokensToWithdraw);
        withdrawals[participant] = Withdrawal({tokens: amountTokensToWithdraw, time: previousUpdateTime});
        WithdrawRequest(participant, amountTokensToWithdraw);
    }
    function withdraw() external {
        address participant = msg.sender;
        uint256 tokens = withdrawals[participant].tokens;
        require(tokens > 0); // participant must have requested a withdrawal
        uint256 requestTime = withdrawals[participant].time;
        // obtain the next price that was set after the request
        Price price = prices[requestTime];
        require(price.numerator > 0); // price must have been set
        uint256 withdrawValue = safeMul(tokens, price.denominator) / price.numerator;
        // if contract ethbal > then send + transfer tokens to fundWallet, otherwise give tokens back
        withdrawals[participant].tokens = 0;
        if (this.balance >= withdrawValue)
            enact_withdrawal_greater_equal(participant, withdrawValue, tokens);
        else
            enact_withdrawal_less(participant, withdrawValue, tokens);
    }
    function enact_withdrawal_greater_equal(address participant, uint256 withdrawValue, uint256 tokens)
        private
    {
        assert(this.balance >= withdrawValue);
        balances[fundWallet] = safeAdd(balances[fundWallet], tokens);
        participant.transfer(withdrawValue);
        Withdraw(participant, tokens, withdrawValue);
    }
    function enact_withdrawal_less(address participant, uint256 withdrawValue, uint256 tokens)
        private
    {
        assert(this.balance < withdrawValue);
        balances[participant] = safeAdd(balances[participant], tokens);
        Withdraw(participant, tokens, 0); // indicate a failed withdrawal
    }
    function checkWithdrawValue(uint256 amountTokensToWithdraw) constant returns (uint256 etherValue) {
        require(amountTokensToWithdraw > 0);
        require(balanceOf(msg.sender) >= amountTokensToWithdraw);
        uint256 withdrawValue = safeMul(amountTokensToWithdraw, currentPrice.denominator) / currentPrice.numerator;
        require(this.balance >= withdrawValue);
        return withdrawValue;
    }
	function checkWithdrawValueForAddress(address participant,uint256 amountTokensToWithdraw) constant returns (uint256 etherValue) {
        require(amountTokensToWithdraw > 0);
        require(balanceOf(participant) >= amountTokensToWithdraw);
        uint256 withdrawValue = safeMul(amountTokensToWithdraw, currentPrice.denominator) / currentPrice.numerator;
        return withdrawValue;
    }
    // allow fundWallet or controlWallet to add ether to contract
    function addLiquidity() external onlyManagingWallets payable {
        require(msg.value > 0);
        AddLiquidity(msg.value);
    }
    // allow fundWallet to remove ether from contract
    function removeLiquidity(uint256 amount) external onlyManagingWallets {
        require(amount <= this.balance);
        fundWallet.transfer(amount);
        RemoveLiquidity(amount);
    }
    function changeFundWallet(address newFundWallet) external onlyFundWallet {
        require(newFundWallet != address(0));
        fundWallet = newFundWallet;
    }
    function changeControlWallet(address newControlWallet) external onlyFundWallet {
        require(newControlWallet != address(0));
        controlWallet = newControlWallet;
    }
    function changeWaitTime(uint256 newWaitTime) external onlyFundWallet {
        waitTime = newWaitTime;
    }
    function updatefundingStartTime(uint256 newfundingStartTime) external onlyFundWallet {
       // require(GetTime() < fundingStartTime);
       // require(GetTime() < newfundingStartTime);
        fundingStartTime = newfundingStartTime;
    }
    function updatefundingEndTime(uint256 newfundingEndTime) external onlyFundWallet {
      //  require(GetTime() < fundingEndTime);
      //  require(GetTime() < newfundingEndTime);
        fundingEndTime = newfundingEndTime;
    }
    function halt() external onlyFundWallet {
        halted = true;
    }
    function unhalt() external onlyFundWallet {
        halted = false;
    }
    function enableTrading() external onlyFundWallet {
        require(GetTime() > fundingEndTime);
        tradeable = true;
    }
    // fallback function
    function() payable {
        require(tx.origin == msg.sender);
        buyTo(msg.sender);
    }
    function claimTokens(address _token) external onlyFundWallet {
        require(_token != address(0));
        Token token = Token(_token);
        uint256 balance = token.balanceOf(this);
        token.transfer(fundWallet, balance);
     }
    // prevent transfers until trading allowed
    function transfer(address _to, uint256 _value) isTradeable returns (bool success) {
        return super.transfer(_to, _value);
    }
    function transferFrom(address _from, address _to, uint256 _value) isTradeable returns (bool success) {
        return super.transferFrom(_from, _to, _value);
    }
}
