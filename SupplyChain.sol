pragma solidity ^0.5.1;
/**
    @title Simple Supply Chain Service for One Buyer and One Seller
    @author muveex
    @notice May contain security flaws.
*/
contract supply_chain_simple {
    enum Progress { Null, InStock, Deposited, InTransit, Delivered}
    struct Product{
        uint productID;
        uint price;          // In Ether. Decimal not supported. 
        uint numInStock;
        Progress progress;   // To simplify the problem, the product can not be separated before end
    }
    
    struct Transaction {
        uint productID;
        uint startTime;
        uint _balance;
        bool buyerVoted;
        bool buyerOK;
        bool sellerVoted;
        bool sellerOK;        
    }

    address payable public bank;
    address payable public buyer;
    address payable public seller;

    
    mapping (uint => Product) inventory;
    mapping (uint => Transaction) txs;
    
    event LogProductInfo (
        uint productID,
        uint price,
        uint numInStock,
        Progress progress
    );
    
    event LogTxInfo (
        uint productID,
        uint startTime,
        Progress progress,
        uint _balance,
        bool buyerVoted,
        bool buyerOK,
        bool sellerVoted,
        bool sellerOK
    );

    constructor(address payable _buyer, address payable _seller) public {
        require((msg.sender != _buyer) && (msg.sender!= _seller), 'Bank address duplicated.');
        require(_buyer != _seller, 'Buyer and seller address duplicated.');
        buyer = _buyer;
        seller = _seller;
        bank = msg.sender;
    }
    
    
/*
    <-- Modifiers -->
*/
    modifier validAccount() {
        require ((buyer == msg.sender || seller == msg.sender), "Invalid account.");
        _;
    }
    modifier isBuyer() {
        require (buyer == msg.sender, "Account is not buyer.");
        _;
    }
    modifier isSeller() {
        require (seller == msg.sender, "Account is not seller.");
        _;
    }
    modifier isBank() {
        require (bank == msg.sender, "Account is not bank service.");
        _;
    }
    /*
    modifier isDispute(uint _productID) {
        require (
            txs[_productID].buyerVoted  && txs[_productID].sellerVoted, 
            "Not voted yet."
        );
        require (
            (txs[_productID].buyerOK && !txs[_productID].sellerOK)
            ||(!txs[_productID].buyerOK && txs[_productID].sellerOK), 
        "Not in dispute."
        );
        _;
    }
    */
    modifier isValidProduct(uint _productID) {
        require ((inventory[_productID].progress != Progress.Null), "Invalid productID.");
        _;
    }
    modifier notBeforeTransit(uint _productID) {
        require(
            (inventory[_productID].progress != Progress.Deposited),
            "Incorrect product state: Deposited."
        );
        _; 
    }
    modifier notShipInProgress(uint _productID) {
        require (
            (inventory[_productID].progress != Progress.InTransit),
            "Shipping in progress."
        );
        _;
    }
    modifier notTransactInProgress(uint _productID) {
        require(
            (inventory[_productID].progress != Progress.Delivered),
            "Transaction in progress."
        );
        _;
    }    

    
/*
    <-- Main functions -->
*/    
    // addProduct can also be used to reset product information.
    function addProduct(uint _productID, uint _price, uint _numInStock) public
        isSeller()        
        notBeforeTransit(_productID)
        notShipInProgress(_productID)
        notTransactInProgress(_productID)
    {
        inventory[_productID].productID = _productID;
        inventory[_productID].price = _price;
        inventory[_productID].numInStock = _numInStock; // Seller need to set rather than add numbers.
        inventory[_productID].progress = Progress.InStock;
        emit LogProductInfo(_productID, _price, _numInStock, inventory[_productID].progress);
    }
    
    function removeProduct(uint _productID) public
        isSeller()
        isValidProduct(_productID)
        notBeforeTransit(_productID)
        notShipInProgress(_productID)
        notTransactInProgress(_productID)
    {
        delete inventory[_productID];
    }
    
    function hasDepositBeforeTransit(uint _productID) public view returns(bool) {
        // Seller use this function to check if the buyer has already deposited for the product.
        if (inventory[_productID].progress == Progress.Deposited) {
            return true;
        } else {
            return false;
        }
    }
    
    function startShipping (uint _productID, uint _numProductToShip) public
        isSeller()
        notShipInProgress(_productID)
        notTransactInProgress(_productID)
        isValidProduct(_productID)
    {
        require(hasDepositBeforeTransit(_productID), 'Buyer has not deposited yet.');
        require(_numProductToShip != 0, 'Please input number of products to ship.');        
        require(inventory[_productID].numInStock >= _numProductToShip, 'Not enough stock.');
//        getProduct(_productID);
        inventory[_productID].numInStock -= _numProductToShip;
        inventory[_productID].progress = Progress.InTransit;
//        getProduct(_productID);
    }
    
    
    
    function deposit(uint _productID) public payable
        isBuyer()
        notBeforeTransit(_productID)
        notShipInProgress(_productID)
        notTransactInProgress(_productID)
        isValidProduct(_productID)
    {
        require(inventory[_productID].progress == Progress.InStock, 'Product is not in stock.');
        require((inventory[_productID].price * 1 ether == msg.value), 'Deposit is not equal to price.');
        txs[_productID]._balance += msg.value;
        txs[_productID].startTime = now;                                //block.timestamp
        inventory[_productID].progress = Progress.Deposited;
    }
    
    function transferDeposit(uint _productID) public
        validAccount()
        isValidProduct(_productID)
    {
        if (msg.sender == buyer) {
            if ((inventory[_productID].progress == Progress.Null)
            || (inventory[_productID].progress == Progress.InStock)
            || (inventory[_productID].progress == Progress.Deposited)) {
                revert('Invalid product state.');
            }
            
            if (inventory[_productID].progress == Progress.InTransit) {
                txs[_productID].buyerVoted = true;
                txs[_productID].buyerOK = true;
                inventory[_productID].progress = Progress.Delivered;                

            } else if (inventory[_productID].progress == Progress.Delivered) {
                // Do Nothing
                
            }
        } else if (msg.sender == seller) {
            // Allow seller to pre-authorize
            if (inventory[_productID].progress == Progress.Null) {
                revert('Product not registered yet.');
            }
            txs[_productID].sellerVoted = true;
            txs[_productID].sellerOK = true;
        }
        // Note: bool var was initialized as false in solidity.
        if ((txs[_productID].buyerOK && txs[_productID].sellerOK) 
            && (txs[_productID].buyerVoted && txs[_productID].sellerVoted)) {
//            bank.transfer(_balance / 100);
//            seller.transfer(address(this).balance);
            
//            getTxInfo(_productID);
            
            seller.transfer(txs[_productID]._balance);
            delete txs[_productID];
            inventory[_productID].progress = Progress.InStock;
            
//            getTxInfo(_productID);
        }
    }
    
    function cancel(uint _productID) public
        validAccount()
        isValidProduct(_productID)
    {
        if (msg.sender == buyer) {
            if ((inventory[_productID].progress == Progress.Null)
                || (inventory[_productID].progress == Progress.InStock)) {
                    revert('Invalid product state: No deposit made yet.');
                }            
            txs[_productID].buyerVoted = true;
            txs[_productID].buyerOK = false;
        } else if (msg.sender == seller) {
            if ((inventory[_productID].progress == Progress.Null)
                || (inventory[_productID].progress == Progress.InStock)) {
                    revert('No pending shipment/Transaction yet.');
                }
            txs[_productID].sellerVoted = true;
            txs[_productID].sellerOK = false;
        }
        // Note: bool var was initialized as false.
        if ((!txs[_productID].buyerOK && !txs[_productID].sellerOK) 
            && (txs[_productID].buyerVoted && txs[_productID].sellerVoted)) {
//            bank.transfer(_balance / 100);
            
//            getTxInfo(_productID);
            
            buyer.transfer(txs[_productID]._balance);
            delete txs[_productID];
            inventory[_productID].progress = Progress.InStock;
            
//            getTxInfo(_productID);
        }        
    }
    
    // Off-chain third party payment processor will decide where the money should go to.
    // Then seller will be responsible to set numInStock or other product info using addProduct()
    function resolveDispute(uint _productID, address payable target) public payable
        isBank()
        isValidProduct(_productID)
        //isDispute(_productID)
    {
        require(isDispute_(_productID), 'Not in dispute');
        require(
            ((target == buyer)
            || (target == seller)),
            'Invalid transfer target. Must be buyer or seller.'
        );
//        getTxInfo(_productID);
        
        target.transfer(txs[_productID]._balance);
        delete txs[_productID];
        inventory[_productID].progress = Progress.InStock;
        
//        getTxInfo(_productID);
        
    }
    
    
/*
    <-- Helper functions -->
*/
    function getProduct(uint _productID) public {
        uint id = inventory[_productID].productID;
        uint price = inventory[_productID].price;
        uint numInStock = inventory[_productID].numInStock;
        Progress progress = inventory[_productID].progress;
        emit LogProductInfo(id, price, numInStock, progress);
    }
    
    function getTxInfo(uint _productID) public {
        emit LogTxInfo (
            _productID,
            txs[_productID].startTime,
            inventory[_productID].progress,
            txs[_productID]._balance,
            txs[_productID].buyerVoted,
            txs[_productID].buyerOK,
            txs[_productID].sellerVoted,
            txs[_productID].sellerOK
        );
    }    
    
    function getContractBalance() view public returns (uint amount) {
        // Note: In Ethereum, the amount is sent to contract address rather than
        // the contract owner's address.
        return address(this).balance;
    }
    
    
    function isDispute_(uint _productID) view public returns(bool _isDispute){
        if (txs[_productID].buyerVoted  && txs[_productID].sellerVoted) {
            if ((txs[_productID].buyerOK && !txs[_productID].sellerOK)
                && (!txs[_productID].buyerOK && txs[_productID].sellerOK)) {
                return true;
            }
            else {
            return false;
            }
        } else {
            return false;
        }
    }
    
    function isBuyer_() public view returns (bool) {
        return msg.sender == buyer;
        
    }
    
    function isSeller_() public view returns (bool) {
        return msg.sender == seller;
    }
    
    function isBank_() public view returns (bool) {
        return msg.sender == bank;
    }
    
}
