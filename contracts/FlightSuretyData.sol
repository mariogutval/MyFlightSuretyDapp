pragma solidity >=0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    enum airlineState {
        Applied,
        Registered,
        Paid
    }

    struct Airline{
        airlineState state;
        string name;
        address[] approvals;
    }

    struct InsuranceInfo{
        address passenger;
        uint256 value;
        insuranceState status;
    }

    enum insuranceState{
        Active,
        Closed
    }
    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false
    mapping(address => Airline) private airlines;
    mapping(address => uint256) private airlineFunding;
    address[] airlinesArray;
    mapping(address => bool) private authorizedCallers;
    mapping(bytes32 => InsuranceInfo[]) private insurances;
    mapping(address => uint256) private payoutValue;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor
                                (
                                )
                                public
    {
        contractOwner = msg.sender;
        airlines[contractOwner].state = airlineState.Paid;
        airlines[contractOwner].name = "Airline 1";
        airlinesArray.push(contractOwner);
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational()
    {
        require(operational, "Contract is currently not operational.");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner.");
        _;
    }

    modifier requireAuthorizedCaller()
    {
        require(authorizedCallers[msg.sender] || (msg.sender == contractOwner), "Caller is not authorized.");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function authorizeCaller(address contractAddress) external requireContractOwner requireIsOperational {
        authorizedCallers[contractAddress] = true;
    }

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */
    function isOperational()
                            public
                            view
                            returns(bool)
    {
        return operational;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */
    function setOperatingStatus
                            (
                                bool mode
                            )
                            external
                            requireContractOwner
    {
        operational = mode;
    }

    function vote
                            (
                                address voter,
                                address candidate
                            )
                            external
                            requireIsOperational
    {
        require(airlines[voter].state == airlineState.Paid, "This airline can not vote.");
        airlines[candidate].approvals.push(voter);
        if(airlines[candidate].approvals.length.mod(2) == 0){
            if (airlines[candidate].approvals.length >= airlinesArray.length.div(2)){
                airlines[candidate].state = airlineState.Registered;
            }
        }
        else{
            if (airlines[candidate].approvals.length > airlinesArray.length.div(2)){
                airlines[candidate].state = airlineState.Registered;
            }
        }
    }
    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function registerAirline
                            (
                                address _airline, string calldata _name
                            )
                            external
                            requireIsOperational
                            // requireAuthorizedCaller
    {
        airlines[_airline].name = _name;
        if(airlinesArray.length <= 4){
            airlines[_airline].state = airlineState.Registered;
        }
        else{
            airlines[_airline].state = airlineState.Applied;
        }
    }

   /**
    * @dev Buy insurance for a flight
    *
    */
    function buy
                            (
                                address _passenger,
                                bytes32 _flightKey
                            )
                            external
                            payable
    {
        require(msg.value <= 1, "Invalid amount.");
        insurances[_flightKey].push(InsuranceInfo({
            passenger: _passenger,
            value: msg.value,
            status: insuranceState.Active
        }));
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees
                                (
                                    bytes32 _flightKey
                                )
                                external
                                requireIsOperational
    {
        for(uint256 i = 0; i < insurances[_flightKey].length; i++){
            if(insurances[_flightKey][i].status == insuranceState.Active){
                insurances[_flightKey][i].status = insuranceState.Closed;
                payoutValue[insurances[_flightKey][i].passenger].add(insurances[_flightKey][i].value.div(2).mul(3));
            }
        }
    }

    /**
     *  @dev Closes insurance when flight status is different from "late due to airline".
    */
    function closeInsurees
                                (
                                    bytes32 _flightKey
                                )
                                external
                                requireIsOperational
    {
        for(uint256 i = 0; i < insurances[_flightKey].length; i++){
            insurances[_flightKey][i].status = insuranceState.Closed;
        }
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay
                            (
                                address payable _passenger
                            )
                            external
                            requireIsOperational
    {
        uint256 amount = payoutValue[_passenger];
        payoutValue[_passenger] = 0;
        _passenger.transfer(amount);
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */
    function fund
                            (
                            )
                            public
                            payable
    {
        airlineFunding[msg.sender].add(msg.value);
        if(airlineFunding[msg.sender] >= 10){
            airlines[msg.sender].state = airlineState.Paid;
            airlinesArray.push(msg.sender);
        }
    }

    function getFlightKey
                        (
                            address airline,
                            string memory flight,
                            uint256 timestamp
                        )
                        internal
                        pure
                        returns(bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    receive ()
                            external
                            payable
    {
        fund();
    }


}

