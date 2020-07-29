pragma solidity ^0.4.24;


contract Ownable {
    address private owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor()public{
        owner = msg.sender;
    }

    function CurrentOwner() public view returns (address){
        return owner;
    }

    modifier onlyOwner(){
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}


interface IERC20 {
    function burn(address spender, uint256 amount) external returns (bool);

}

contract ltjGame is Ownable {
    uint256 ethWei = 1 ether;
    uint256 hour2 = 7200;
    uint256 oneday = 60 * 60 * 24;

    struct Invest {

        address userAddress;
        uint256 inputAmount;
        uint256 day;
        uint256 resTime;
        uint256 times;
        uint256 lastTime;
        bool status;
    }


    address private feeAddr = 0xa;
    address private firstAccountAddr = 0xa;
    string defaultAddrCode = "PMCC";
    address private tokenAddr = 0xa;
    uint256 tokenRate = 100;

    Invest[] invests;
    uint256 beginTime;

    uint256 private fixedScale = 10000;
    uint256 private dyScale = 100;
    bool private gameStatus = true;
    IERC20 ltjToken;

    event investEvent(address indexed addr, uint256 indexed am);
    event submitStaticEvent(address indexed addr, uint256 indexed am, uint256 times);
    event submitDyEvent(address indexed addr, uint256 indexed am, uint256 times);

    constructor(uint256 startTime) public payable {
        uint256 inputAmount = 50 * ethWei;
        uint256 lv = getLevel(180, inputAmount);
        User memory user = User(firstAccountAddr, defaultAddrCode, "--a--", inputAmount, inputAmount, 0, 0, 0, 0, 0, lv, 2, 0, true);
        uint256 defaultCount = 20;
        teamCountMapping[defaultAddrCode] = defaultCount;
        address[] storage pls = teamUserMapping[firstAccountAddr];
        for (uint256 i = 0; i < defaultCount; i++) {
            pls.push(address(0));
        }
        teamUserMapping[firstAccountAddr] = pls;
        addressMapping[defaultAddrCode] = firstAccountAddr;
        userMapping[firstAccountAddr] = user;
        beginTime = startTime;
        ltjToken = IERC20(tokenAddr);
        addMaster(msg.sender);
    }

    function delMaster(address addr) public onlyOwner {
        require(addr != address(0) && addr != msg.sender);
        if (masterMap[addr]) {
            masterMap[addr] = false;
            emit SetMaster(addr, false);
        }
    }

    function isMaster(address addr) public onlyOwner view returns (bool){
        require(addr != address(0));
        return masterMap[addr];
    }

    modifier onlyMaster(){
        require(masterMap[msg.sender], "caller is not the master");
        _;
    }

    modifier gameActive(){
        require(gameStatus, "ina");
        _;
    }


    function invest(uint day, string recCode, string upCode) public payable gameActive {
        require(msg.value >= 1 * ethWei, "more than one");
        require(msg.value % ethWei == 0, "not allow decimal");
        require(day == 7 || day == 30 || day == 90 || day == 180, "invalid param");
        require(getUserByinviteCode(upCode) > 0, "invalid code");
        User memory user = userMapping[msg.sender];
        require(!user.exited, "invalid address");
        require(user.valid == 0 || user.valid == 1 || user.valid == 4, "do not repeat");
        require(!compareStr(recCode, ""), "invalid code#2");

        address userAddress = msg.sender;
        uint256 inputAmount = msg.value + user.inviteAmount;
        uint256 lv = getLevel(day, inputAmount);
        uint256 lsTime = calcLastTime(beginTime, now);
        Invest memory iv = Invest(userAddress, inputAmount, day, now, 0, lsTime, true);
        invests.push(iv);
        uint256 orderIndex = invests.length - 1;
        sendFee(inputAmount);
        uint256 tokenAmount = inputAmount * tokenRate;
        ltjToken.burn(userAddress, tokenAmount);
        if (user.valid == 0) {
            user = User(userAddress, recCode, upCode, inputAmount, inputAmount, 0, 0, 0, tokenAmount, 0, lv, 2, orderIndex, false);
            userMapping[userAddress] = user;
            indexMapping[curUserIndex] = userAddress;
            curUserIndex = curUserIndex + 1;
            addressMapping[recCode] = userAddress;

            teamCountMapping[upCode] = teamCountMapping[upCode] + 1;
            address upAddr = addressMapping[upCode];
            address[] storage uplayers = teamUserMapping[upAddr];
            uplayers.push(userAddress);
            teamUserMapping[upAddr] = uplayers;
        } else {
            user.inviteAmount = inputAmount;
            user.totalInviteAmount = user.totalInviteAmount + inputAmount;
            user.level = lv;
            user.valid = 2;
            user.inIndex = orderIndex;
            user.tokenCount = user.tokenCount + tokenAmount;
            userMapping[userAddress] = user;
        }
        emit investEvent(userAddress, inputAmount);
    }


    function settlementDay(address addr) private {
        User memory user = userMapping[addr];
        if (user.valid == 2) {
            Invest memory inv = invests[user.inIndex];
            if (inv.status && inv.times < inv.day && now >= inv.lastTime + oneday) {
                uint256 level = user.level;
                uint256 staticBonus = user.inviteAmount * level / fixedScale;
                user.releaseAmount = user.releaseAmount + staticBonus;
                userMapping[addr] = user;
                uint256 nTimes = inv.times + 1;
                invests[user.inIndex].times = nTimes;
                invests[user.inIndex].lastTime = calcLastTime(inv.lastTime, now);
                address upAddr = addressMapping[user.upCode];
                emit submitStaticEvent(addr, staticBonus, inv.times + 1);
                executeRec(addr, upAddr, 1);
                if (nTimes == inv.day) {
                    userMapping[addr].valid = 1;
                }
            }
        }
    }


    function withdraw() public payable gameActive {
        User memory user = userMapping[msg.sender];
        require(user.valid == 1, "invalid status");
        require(user.inviteAmount / 5 == msg.value, "invalid value");
        uint256 ba = address(this).balance - msg.value;
        require(ba >= user.inviteAmount, "balance not enough");
        msg.sender.transfer(user.inviteAmount);
        userMapping[msg.sender].exitTime = now;
        userMapping[msg.sender].valid = 3;
    }

    function withdraw80() public payable gameActive {
        User memory user = userMapping[msg.sender];
        require(user.valid == 3, "invalid status");
        require(now - user.exitTime <= hour2, "account invalid");
        require(user.inviteAmount * 80 / 100 == msg.value, "invalid value");
        uint256 tokenAmount = user.inviteAmount * tokenRate;
        ltjToken.burn(msg.sender, tokenAmount);
        Invest memory lastIv = invests[user.inIndex];
        uint256 lsTime = calcLastTime(beginTime, now);
        Invest memory iv = Invest(msg.sender, lastIv.inputAmount, lastIv.day, now, 0, lsTime, true);
        invests.push(iv);
        userMapping[msg.sender].totalInviteAmount = user.totalInviteAmount + user.inviteAmount;
        userMapping[msg.sender].inIndex = invests.length - 1;
        userMapping[msg.sender].valid = 2;
        userMapping[msg.sender].exitTime = 0;
        userMapping[msg.sender].tokenCount = userMapping[msg.sender].tokenCount + tokenAmount;
        emit investEvent(msg.sender, user.inviteAmount);
    }


    function resetA() public onlyMaster {
        delete invests;
    }

    function resetB(address[] addrList) public onlyMaster {
        for (uint256 i = 0; i < addrList.length; i++) {
            address addr = addrList[i];
            User memory user = userMapping[addr];
            user.inviteAmount = 0;
            user.totalInviteAmount = 0;
            user.releaseAmount = 0;
            user.dyAmount = 0;
            user.withdrawBonus = 0;
            user.tokenCount = 0;
            user.exitTime = 0;
            user.level = 0;
            user.valid = 4;
            user.inIndex = 0;
            userMapping[addr] = user;
        }
    }

    function outUserInfo(address addr) public view returns (string, string, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256){
        User memory user = userMapping[addr];
        return (user.recCode, user.upCode, user.inviteAmount, user.releaseAmount, user.dyAmount, user.withdrawBonus, user.tokenCount, getWebLevel(user.inviteAmount), getWebLineLevel(teamCountMapping[user.recCode]), user.exitTime, user.valid, user.totalInviteAmount);
    }

    function outUserOrder(address addr) public view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256){
        User memory user = userMapping[addr];
        Invest memory inv = invests[user.inIndex];

        return (user.valid, inv.inputAmount, inv.day, inv.resTime, inv.times, inv.lastTime, user.exitTime);

    }

    function outGameInfo() public view returns (uint256, uint256, bool){
        require(msg.sender == feeAddr);
        return (curUserIndex, invests.length, gameStatus);
    }


    function outLineCount(address addr) public view returns (uint256){
        address[] memory list = teamUserMapping[addr];
        return list.length;
    }

    function outTeamInfo(address addr) public view returns (uint256, uint256){
        uint256 t = 0;
        uint256 a = 0;
        (t, a) = calcTotal(addr);
        t += 1;
        return (t, a);
    }


    function getUserByinviteCode(string inviteCode) private view returns (uint256){

        address userAddressCode = addressMapping[inviteCode];
        User memory user = userMapping[userAddressCode];
        return user.valid;
    }

    function getBase(uint256 a, uint256 b) private pure returns (uint256){
        if (a >= b) {
            return b;
        }
        return a;
    }

    function getLevel(uint256 day, uint256 value) private view returns (uint256){
        if (day == 7) {
            if (value < 6 * ethWei) {
                return 50;
            } else if (value < 16 * ethWei) {
                return 70;
            } else {
                return 90;
            }
        } else if (day == 30) {
            if (value < 6 * ethWei) {
                return 75;
            } else if (value < 16 * ethWei) {
                return 100;
            } else {
                return 125;
            }
        } else if (day == 90) {
            if (value < 6 * ethWei) {
                return 100;
            } else if (value < 16 * ethWei) {
                return 130;
            } else {
                return 160;
            }
        } else {
            if (value < 6 * ethWei) {
                return 125;
            } else if (value < 16 * ethWei) {
                return 160;
            } else {
                return 195;
            }
        }
    }

    function getLineLevel(uint256 times) private pure returns (uint256){

        if (times == 1) {
            return 50;
        }
        if (times == 2) {
            return 20;
        }
        if (times == 3 || times == 4 || times == 5) {
            return 10;
        }

        if (times >= 6 && times <= 10) {
            return 5;
        }
        if (times >= 11) {
            return 3;
        }
        return 0;
    }

    function calcLastTime(uint256 lastTime, uint256 curTime) private view returns (uint256){
        if (curTime > lastTime) {
            uint256 count = (curTime - lastTime) / oneday;
            if (count > 0) {
                return lastTime + (oneday * count);
            }
        }
        return lastTime;
    }

    function compareStr(string _str, string str) public pure returns (bool) {
        return keccak256(abi.encodePacked(_str)) == keccak256(abi.encodePacked(str));
    }

    function getWebLevel(uint256 v) private view returns (uint256){
        if (v >= 1 * ethWei && v <= 5 * ethWei) {
            return 1;
        }
        if (v >= 6 * ethWei && v <= 15 * ethWei) {
            return 2;
        }
        if (v >= 16 * ethWei) {
            return 3;
        }
        return 0;
    }

    function getWebLineLevel(uint256 v) private pure returns (uint256){
        if (v == 0) {
            return 0;
        }
        if (v < 3) {
            return 1;
        }
        if (v < 5) {
            return 2;
        }
        if (v < 8) {
            return 3;
        }
        if (v < 15) {
            return 4;
        }
        return 5;
    }

    function calcTotal(address addr) private view returns (uint256, uint256){
        uint256 team = 0;
        uint256 amount = 0;
        User memory user = userMapping[addr];
        if (user.valid != 0) {
            amount = user.totalInviteAmount;
        }
        address[] memory list = teamUserMapping[addr];
        if (list.length > 0) {
            team = list.length;
            uint256 t = 0;
            uint256 a = 0;
            for (uint256 i = 0; i < list.length; i++) {
                (t, a) = calcTotal(list[i]);
                team += t;
                amount += a;
            }
        }
        return (team, amount);
    }
}
