// SPDX-License-Identifier: NONE
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./MiMCSponge.sol";
import "./ReentrancyGuard.sol";
import "./IGhoToken.sol";

interface IVerifier {
    function verifyProof(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[3] memory input
    ) external;
}

contract GhoTip is ReentrancyGuard, Ownable {
    address verifier;
    Hasher hasher;
    IGhoToken ghoToken;

    uint8 public treeLevel = 10;
    // uint256 public denomination = 0.1 ether;
    uint256 public denomination = 0.5 ether;
    // for different amount GhoTip contracts, the only difference is the number of demoniation. Currently, 0.1 ether and 0.5 ether are deployed

    uint256 public nextLeafIdx = 0;
    mapping(uint8 => uint256) lastLevelHash;
    mapping(uint256 => bool) public nullifierHashes;
    mapping(uint256 => bool) public commitments;

    uint256[10] levelDefaults = [
        23183772226880328093887215408966704399401918833188238128725944610428185466379,
        24000819369602093814416139508614852491908395579435466932859056804037806454973,
        90767735163385213280029221395007952082767922246267858237072012090673396196740,
        36838446922933702266161394000006956756061899673576454513992013853093276527813,
        68942419351509126448570740374747181965696714458775214939345221885282113404505,
        50082386515045053504076326033442809551011315580267173564563197889162423619623,
        73182421758286469310850848737411980736456210038565066977682644585724928397862,
        60176431197461170637692882955627917456800648458772472331451918908568455016445,
        105740430515862457360623134126179561153993738774115400861400649215360807197726,
        76840483767501885884368002925517179365815019383466879774586151314479309584255
    ];

    event Deposit(
        uint256 root,
        uint256[10] hashPairings,
        uint8[10] pairDirection
    );
    event VerifyProof(uint256 nullifierHash, bool verifyOK);

    constructor(
        address _hasher,
        address _verifier,
        address _ghoToken
    ) Ownable(msg.sender) {
        hasher = Hasher(_hasher);
        ghoToken = IGhoToken(_ghoToken);
        verifier = _verifier;
    }

    function deposit(uint256 _commitment) external payable nonReentrant {
        require(!commitments[_commitment], "existing-commitment");
        require(nextLeafIdx < 2 ** treeLevel, "tree-full");
        ghoToken.transferFrom(msg.sender, address(this), denomination);

        uint256 newRoot;
        uint256[10] memory hashPairings;
        uint8[10] memory hashDirections;

        uint256 currentIdx = nextLeafIdx;
        uint256 currentHash = _commitment;

        uint256 left;
        uint256 right;
        uint256[2] memory ins;

        for (uint8 i = 0; i < treeLevel; i++) {
            if (currentIdx % 2 == 0) {
                left = currentHash;
                right = levelDefaults[i];
                hashPairings[i] = levelDefaults[i];
                hashDirections[i] = 0;
            } else {
                left = lastLevelHash[i];
                right = currentHash;
                hashPairings[i] = lastLevelHash[i];
                hashDirections[i] = 1;
            }
            lastLevelHash[i] = currentHash;

            ins[0] = left;
            ins[1] = right;

            uint256 h = hasher.MiMC5Sponge{gas: 150000}(ins, _commitment);

            currentHash = h;
            currentIdx = currentIdx / 2;
        }

        newRoot = currentHash;
        nextLeafIdx += 1;

        commitments[_commitment] = true;
        emit Deposit(newRoot, hashPairings, hashDirections);
    }

    function getVerifyResult(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[2] memory input
    ) external payable nonReentrant {
        uint256 _nullifierHash = input[1];

        require(!nullifierHashes[_nullifierHash], "already-verified");

        uint256 _addr = uint256(uint160(msg.sender));

        (bool verifyOK, ) = verifier.call(
            abi.encodeCall(
                IVerifier.verifyProof,
                (a, b, c, [input[0], _nullifierHash, _addr])
            )
        );

        require(verifyOK, "invalid-proof");

        nullifierHashes[_nullifierHash] = true;

        emit VerifyProof(_nullifierHash, verifyOK);
    }

    function withdraw() external nonReentrant onlyOwner {
        uint256 amount = ghoToken.balanceOf(address(this));
        payable(msg.sender).transfer(amount);
    }
}
