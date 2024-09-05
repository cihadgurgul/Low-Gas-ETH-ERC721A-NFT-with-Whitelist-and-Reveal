// File: undefined/BooBunch.sol

pragma solidity ^0.8.4;

contract BooBunch is ERC721A, Ownable, Pausable, ReentrancyGuard {

    enum MintPhase {
        CLOSED,
        OGWL,
        PUBLIC
    }

    // Configuration: Metadata
    string public baseURI;

    // Configuration: General
    uint256 public immutable maxSupply = 5555;
    uint256 public price = 0.033 ether;
    MintPhase public phase = MintPhase.CLOSED;

    mapping(address => bool) public ogClaimed;
    mapping(address => bool) public whiteListClaimed;
    mapping(address => bool) public publicFreeClaimed;

    // Configuration: OG Mint
    bytes32 public ogMerkleRoot;
    uint256 public maxPerOgMinter = 4; // Actually 3, this is to avoid using <=

    // Configuration: WL Mint
    bytes32 public whitelistMerkleRoot;
    uint256 public maxPerWhitelistMinter = 3; // Actually 2, this is to avoid using <=

    // Configuration: Public Mint
    uint256 public maxPerFreePublicTx = 2; // Actually 1, this is to avoid using <=
    uint256 public maxPerPublicTx = 4; // Actually 3, this is to avoid using <=

    // Withdraw accounts
    address private constant WALLET_B = 0xaB636856459793ADDB093aEAAD4fB400f94e8A75;
    address private constant WALLET_C = 0x8E090D4b9C3E5c38Be4aA9D111ECea1834280fA2;

    constructor(
        string memory _initBaseUri
    ) ERC721A("BOO", "BOO") {
        setBaseURI(_initBaseUri);
    }

    // ERC721A overrides ===========================================================================

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }
    
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI = _baseURI();
        return bytes(baseURI).length != 0 ? string(abi.encodePacked(baseURI, _toString(tokenId), ".json")) : '';
    }

    // When the contract is paused, all token transfers are prevented in case of emergency
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 tokenId,
        uint256 quantity
    ) internal override(ERC721A) whenNotPaused {
        super._beforeTokenTransfers(from, to, tokenId, quantity);
    }

    // Admin functions =============================================================================

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function setOgMerkleRoot(bytes32 _ogMerkleRoot) external onlyOwner {
        ogMerkleRoot = _ogMerkleRoot;
    }

    function setwhitelistMerkleRoot(bytes32 _whitelistMerkleRoot) external onlyOwner {
        whitelistMerkleRoot = _whitelistMerkleRoot;
    }

    function setMaxPerOgMinter(uint256 _maxPerOgMinter) external onlyOwner {
        maxPerOgMinter = _maxPerOgMinter;
    }

    function setmaxPerWhitelistMinter(uint256 _maxPerWhitelistMinter) external onlyOwner {
        maxPerWhitelistMinter = _maxPerWhitelistMinter;
    }

    function setMaxPerPublicTx(uint256 _maxPerPublicTx) external onlyOwner {
        maxPerPublicTx = _maxPerPublicTx;
    }

    function setPhase(MintPhase _mintPhase) external onlyOwner {
        phase = _mintPhase;
    }

    // Update price in case of major ETH fluctuations
    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    /* solhint-disable avoid-low-level-calls */
    function withdraw() external nonReentrant onlyOwner {
        uint256 currentBalance = address(this).balance;

        (bool successB, ) = payable(WALLET_B).call{ value: (currentBalance * 92) / 100 }("");
        require(successB, "Failed to send to B");

        (bool successC, ) = payable(WALLET_C).call{ value: (currentBalance * 8) / 100 }("");
        require(successC, "Failed to send to C");

    } /* solhint-enable avoid-low-level-calls */

    // Public functions ============================================================================

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function totalMinted() public view returns (uint256) {
        return _totalMinted();
    }

    // Minting functions ===========================================================================

    function _mintPresale(
        address buyer,
        uint256 quantity,
        bytes32[] calldata proof,
        bytes32 merkleRoot,
        uint256 limit
    ) internal {
        string memory payload = string(abi.encodePacked(buyer));
        require(_verify(merkleRoot, _leaf(payload), proof), "Address is not allowed during OGWL Sale");
        require(quantity < limit, "Exceeds OGWL per transaction limit");
        require(numberMinted(_msgSender()) + quantity < limit, "Exceeds total OGWL limit");

        _safeMint(buyer, quantity);
    }

    function mintOg(uint256 quantity, bytes32[] calldata proof) external payable nonReentrant {
        require(phase == MintPhase.OGWL, "OG or WhiteList sale is not active");
        require(!ogClaimed[msg.sender], "Address has already been claimed!");

        _mintPresale(_msgSender(), quantity, proof, ogMerkleRoot, maxPerOgMinter);

        ogClaimed[msg.sender] = true;
    }

    function mintWhitelist(uint256 quantity, bytes32[] calldata proof) external payable nonReentrant {
        require(phase == MintPhase.OGWL, "OG or WhiteList sale is not active");
        require(!whiteListClaimed[msg.sender], "Address has already been claimed!");

        _mintPresale(_msgSender(), quantity, proof, whitelistMerkleRoot, maxPerWhitelistMinter);

        whiteListClaimed[msg.sender] = true;
    }

    function mintPublicFree(uint256 quantity) external payable nonReentrant {
        require(phase == MintPhase.PUBLIC, "Public sale is not active");
        require(totalMinted() + quantity <= 3333, "Exceeds Free Supply");
        require(quantity < maxPerFreePublicTx, "Exceeds max per transaction");
        require(!publicFreeClaimed[msg.sender], "Only 1 Free Per Wallet");

        _safeMint(_msgSender(), quantity);

        publicFreeClaimed[msg.sender] = true;
    }

    function mintPublic(uint256 quantity) external payable nonReentrant {
        require(phase == MintPhase.PUBLIC, "Public sale is not active");
        require(totalMinted() + quantity <= maxSupply, "Exceeds max supply");
        require(quantity < maxPerPublicTx, "Exceeds max per transaction");
        require(price * quantity == msg.value, "Incorrect amount of funds provided");

        _safeMint(_msgSender(), quantity);
    }

    // Merkle tree functions =======================================================================

    function _leaf(string memory payload) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(payload));
    }

    function _verify(
        bytes32 merkleRoot,
        bytes32 leaf,
        bytes32[] memory proof
    ) internal pure returns (bool) {
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }

}