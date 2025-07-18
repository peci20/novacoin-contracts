// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/// @author thirdweb

//   $$\     $$\       $$\                 $$\                         $$\
//   $$ |    $$ |      \__|                $$ |                        $$ |
// $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\
// \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\
//   $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
//   $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
//   \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
//    \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/

//Interface
import { ITokenERC20 } from "../interface/token/ITokenERC20.sol";

import "../../infra/interface/IThirdwebContract.sol";
import "../../extension/interface/IPlatformFee.sol";
import "../../extension/interface/IPrimarySale.sol";

// Token
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

// Security
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

// Signature utils
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";

// Meta transactions
import "../../external-deps/openzeppelin/metatx/ERC2771ContextUpgradeable.sol";

// Utils
import "../../extension/Multicall.sol";
import "../../lib/CurrencyTransferLib.sol";
import "../../lib/FeeType.sol";

contract TokenERC20 is
    Initializable,
    IThirdwebContract,
    IPrimarySale,
    IPlatformFee,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable,
    Multicall,
    ERC20BurnableUpgradeable,
    ERC20VotesUpgradeable,
    ITokenERC20,
    AccessControlEnumerableUpgradeable
{
    using ECDSAUpgradeable for bytes32;

    bytes32 private constant MODULE_TYPE = bytes32("TokenERC20");
    uint256 private constant VERSION = 1;

    address public constant DEFAULT_FEE_RECIPIENT = 0x1Af20C6B23373350aD464700B5965CE4B0D2aD94;
    uint16 private constant DEFAULT_FEE_BPS = 50;

    bytes32 private constant TYPEHASH =
        keccak256(
            "MintRequest(address to,address primarySaleRecipient,uint256 quantity,uint256 price,address currency,uint128 validityStartTimestamp,uint128 validityEndTimestamp,bytes32 uid)"
        );

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");

    /// @dev Returns the URI for the storefront-level metadata of the contract.
    string public contractURI;

    /// @dev Max bps in the thirdweb system
    uint128 internal constant MAX_BPS = 10_000;

    /// @dev The % of primary sales collected by the contract as fees.
    uint128 private platformFeeBps;

    /// @dev The adress that receives all primary sales value.
    address internal platformFeeRecipient;

    /// @dev The adress that receives all primary sales value.
    address public primarySaleRecipient;

    /// @dev Mapping from mint request UID => whether the mint request is processed.
    mapping(bytes32 => bool) private minted;

    constructor() initializer {}

    /// @dev Initializes the contract, like a constructor.
    function initialize(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        address[] memory _trustedForwarders,
        address _primarySaleRecipient,
        address _platformFeeRecipient,
        uint256 _platformFeeBps
    ) external initializer {
        __ReentrancyGuard_init();
        __ERC2771Context_init_unchained(_trustedForwarders);
        __ERC20Permit_init(_name);
        __ERC20_init_unchained(_name, _symbol);

        contractURI = _contractURI;
        primarySaleRecipient = _primarySaleRecipient;
        platformFeeRecipient = _platformFeeRecipient;

        require(_platformFeeBps <= MAX_BPS, "exceeds MAX_BPS");
        platformFeeBps = uint128(_platformFeeBps);

        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(TRANSFER_ROLE, _defaultAdmin);
        _setupRole(MINTER_ROLE, _defaultAdmin);
        _setupRole(TRANSFER_ROLE, address(0));

        emit PrimarySaleRecipientUpdated(_primarySaleRecipient);
        emit PlatformFeeInfoUpdated(_platformFeeRecipient, _platformFeeBps);
    }

    /// @dev Returns the module type of the contract.
    function contractType() external pure virtual returns (bytes32) {
        return MODULE_TYPE;
    }

    /// @dev Returns the version of the contract.
    function contractVersion() external pure virtual returns (uint8) {
        return uint8(VERSION);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._afterTokenTransfer(from, to, amount);
    }

    /// @dev Runs on every transfer.
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);

        if (!hasRole(TRANSFER_ROLE, address(0)) && from != address(0) && to != address(0)) {
            require(hasRole(TRANSFER_ROLE, from) || hasRole(TRANSFER_ROLE, to), "transfers restricted.");
        }
    }

    function _mint(address account, uint256 amount) internal virtual override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._burn(account, amount);
    }

    /**
     * @dev Creates `amount` new tokens for `to`.
     *
     * See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mintTo(address to, uint256 amount) public virtual nonReentrant {
        require(hasRole(MINTER_ROLE, _msgSender()), "not minter.");
        _mintTo(to, amount);
    }

    /// @dev Verifies that a mint request is signed by an account holding MINTER_ROLE (at the time of the function call).
    function verify(MintRequest calldata _req, bytes calldata _signature) public view returns (bool, address) {
        address signer = recoverAddress(_req, _signature);
        return (!minted[_req.uid] && hasRole(MINTER_ROLE, signer), signer);
    }

    /// @dev Mints tokens according to the provided mint request.
    function mintWithSignature(MintRequest calldata _req, bytes calldata _signature) external payable nonReentrant {
        address signer = verifyRequest(_req, _signature);
        address receiver = _req.to;

        collectPrice(_req);

        _mintTo(receiver, _req.quantity);

        emit TokensMintedWithSignature(signer, receiver, _req);
    }

    /// @dev Lets a module admin set the default recipient of all primary sales.
    function setPrimarySaleRecipient(address _saleRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        primarySaleRecipient = _saleRecipient;
        emit PrimarySaleRecipientUpdated(_saleRecipient);
    }

    /// @dev Lets a module admin update the fees on primary sales.
    function setPlatformFeeInfo(
        address _platformFeeRecipient,
        uint256 _platformFeeBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_platformFeeBps <= MAX_BPS, "exceeds MAX_BPS");

        platformFeeBps = uint64(_platformFeeBps);
        platformFeeRecipient = _platformFeeRecipient;

        emit PlatformFeeInfoUpdated(_platformFeeRecipient, _platformFeeBps);
    }

    /// @dev Returns the platform fee bps and recipient.
    function getPlatformFeeInfo() external view returns (address, uint16) {
        return (platformFeeRecipient, uint16(platformFeeBps));
    }

    /// @dev Collects and distributes the primary sale value of tokens being claimed.
    function collectPrice(MintRequest calldata _req) internal {
        if (_req.price == 0) {
            require(msg.value == 0, "!Value");
            return;
        }

        uint256 platformFeesTw = (_req.price * DEFAULT_FEE_BPS) / MAX_BPS;
        uint256 platformFees = (_req.price * platformFeeBps) / MAX_BPS;

        if (_req.currency == CurrencyTransferLib.NATIVE_TOKEN) {
            require(msg.value == _req.price, "must send total price.");
        } else {
            require(msg.value == 0, "msg value not zero");
        }

        address saleRecipient = _req.primarySaleRecipient == address(0)
            ? primarySaleRecipient
            : _req.primarySaleRecipient;

        CurrencyTransferLib.transferCurrency(_req.currency, _msgSender(), DEFAULT_FEE_RECIPIENT, platformFeesTw);
        CurrencyTransferLib.transferCurrency(_req.currency, _msgSender(), platformFeeRecipient, platformFees);
        CurrencyTransferLib.transferCurrency(
            _req.currency,
            _msgSender(),
            saleRecipient,
            _req.price - platformFees - platformFeesTw
        );
    }

    /// @dev Mints `amount` of tokens to `to`
    function _mintTo(address _to, uint256 _amount) internal {
        _mint(_to, _amount);
        emit TokensMinted(_to, _amount);
    }

    /// @dev Verifies that a mint request is valid.
    function verifyRequest(MintRequest calldata _req, bytes calldata _signature) internal returns (address) {
        (bool success, address signer) = verify(_req, _signature);
        require(success, "invalid signature");

        require(
            _req.validityStartTimestamp <= block.timestamp && _req.validityEndTimestamp >= block.timestamp,
            "request expired"
        );
        require(_req.to != address(0), "recipient undefined");
        require(_req.quantity > 0, "zero quantity");

        minted[_req.uid] = true;

        return signer;
    }

    /// @dev Returns the address of the signer of the mint request.
    function recoverAddress(MintRequest calldata _req, bytes calldata _signature) internal view returns (address) {
        return _hashTypedDataV4(keccak256(_encodeRequest(_req))).recover(_signature);
    }

    /// @dev Resolves 'stack too deep' error in `recoverAddress`.
    function _encodeRequest(MintRequest calldata _req) internal pure returns (bytes memory) {
        return
            abi.encode(
                TYPEHASH,
                _req.to,
                _req.primarySaleRecipient,
                _req.quantity,
                _req.price,
                _req.currency,
                _req.validityStartTimestamp,
                _req.validityEndTimestamp,
                _req.uid
            );
    }

    /// @dev Sets contract URI for the storefront-level metadata of the contract.
    function setContractURI(string calldata _uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        contractURI = _uri;
    }

    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable, Multicall)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }
}
