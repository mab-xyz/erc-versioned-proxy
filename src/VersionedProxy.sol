// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVersionedProxy
 * @dev Interface for versioned proxy contracts
 */
interface IVersionedProxy {
    /// @notice Emitted when a new implementation version is registered
    /// @param version The version identifier
    /// @param implementation The address of the implementation contract
    event VersionRegistered(bytes32 version, address implementation);
        
    /// @notice Emitted when the default version is changed
    /// @param oldVersion The previous default version
    /// @param newVersion The new default version
    event DefaultVersionChanged(bytes32 oldVersion, bytes32 newVersion);
    
    /// @notice Registers a new implementation version
    /// @param version The version identifier (e.g., "1.0.0")
    /// @param implementation The address of the implementation contract
    function registerVersion(bytes32 version, address implementation) external;
    
    /// @notice Removes a version from the registry
    /// @param version The version identifier to remove
    function removeVersion(bytes32 version) external;
    
    /// @notice Sets the default version to use when no version is specified
    /// @param version The version identifier to set as default
    function setDefaultVersion(bytes32 version) external;
    
    /// @notice Gets the implementation address for a specific version
    /// @param version The version identifier
    /// @return The implementation address for the specified version
    function getImplementation(bytes32 version) external view returns (address);
    
    /// @notice Gets the current default version
    /// @return The current default version identifier
    function getDefaultVersion() external view returns (bytes32);
    
    /// @notice Gets all registered versions
    /// @return An array of all registered version identifiers
    function getVersions() external view returns (bytes32[] memory);
    
    /// @notice Executes a call to a specific implementation version
    /// @param version The version identifier of the implementation to call
    /// @param data The calldata to forward to the implementation
    /// @return The return data from the implementation call
    function executeAtVersion(bytes32 version, bytes calldata data) external payable returns (bytes memory);
}

/**
 * @title VersionedProxy
 * @dev Reference implementation of the versioned proxy pattern
 */
contract VersionedProxy is IVersionedProxy {
    /// @dev EIP-1967 implementation slot
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    /// @dev Admin slot for access control
    bytes32 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    
    /// @dev Mapping of version identifiers to implementation addresses
    mapping(bytes32 => address) private _implementations;
    
    /// @dev Array of all registered version identifiers
    bytes32[] private _versions;
    
    /// @dev The current default version
    bytes32 private _defaultVersion;
    
    error UnauthorizedCaller();
    error VersionNotFound(bytes32 version);
    error VersionAlreadyExists(bytes32 version);
    error InvalidImplementation();
    error CallFailed();
    error CannotRemoveDefaultVersion();
    
    modifier onlyAdmin() {
        if (msg.sender != _getAdmin()) {
            revert UnauthorizedCaller();
        }
        _;
    }
    
    constructor(address admin) {
        _setAdmin(admin);
    }
    
    /// @inheritdoc IVersionedProxy
    function registerVersion(bytes32 version, address implementation) external onlyAdmin {
        if (implementation == address(0) || implementation.code.length == 0) {
            revert InvalidImplementation();
        }
        
        if (_implementations[version] != address(0)) {
            revert VersionAlreadyExists(version);
        }
        
        _implementations[version] = implementation;
        _versions.push(version);
        
        // If this is the first version, set it as default
        if (_defaultVersion == bytes32(0)) {
            _defaultVersion = version;
        }
        
        emit VersionRegistered(version, implementation);
    }
    
    /// @inheritdoc IVersionedProxy
    function removeVersion(bytes32 version) external onlyAdmin {
        if (_implementations[version] == address(0)) {
            revert VersionNotFound(version);
        }
        
        if (version == _defaultVersion) {
            revert CannotRemoveDefaultVersion();
        }
        
        delete _implementations[version];
        
        // Remove from versions array
        for (uint256 i = 0; i < _versions.length; i++) {
            if (_versions[i] == version) {
                _versions[i] = _versions[_versions.length - 1];
                _versions.pop();
                break;
            }
        }
    }
    
    /// @inheritdoc IVersionedProxy
    function setDefaultVersion(bytes32 version) external onlyAdmin {
        if (_implementations[version] == address(0)) {
            revert VersionNotFound(version);
        }
        
        bytes32 oldVersion = _defaultVersion;
        _defaultVersion = version;
        
        // Also update EIP-1967 slot for compatibility
        _setImplementation(_implementations[version]);
        
        emit DefaultVersionChanged(oldVersion, version);
    }
    
    /// @inheritdoc IVersionedProxy
    function getImplementation(bytes32 version) external view returns (address) {
        address implementation = _implementations[version];
        if (implementation == address(0)) {
            revert VersionNotFound(version);
        }
        return implementation;
    }
    
    /// @inheritdoc IVersionedProxy
    function getDefaultVersion() external view returns (bytes32) {
        return _defaultVersion;
    }
    
    /// @inheritdoc IVersionedProxy
    function getVersions() external view returns (bytes32[] memory) {
        return _versions;
    }
    
    /// @inheritdoc IVersionedProxy
    function executeAtVersion(bytes32 version, bytes calldata data) 
        external 
        payable 
        returns (bytes memory) 
    {
        address implementation = _implementations[version];
        if (implementation == address(0)) {
            revert VersionNotFound(version);
        }
        
        return _delegateCall(implementation, data);
    }
    
    /// @dev Fallback function forwards to default implementation
    fallback() external payable {
        address implementation = _implementations[_defaultVersion];
        if (implementation == address(0)) {
            revert VersionNotFound(_defaultVersion);
        }
        
        _delegate(implementation);
    }
    
    /// @dev Receive function to accept ETH
    receive() external payable {}
    
    /// @dev Performs a delegate call and returns the result
    function _delegateCall(address implementation, bytes memory data) 
        private 
        returns (bytes memory) 
    {
        (bool success, bytes memory returndata) = implementation.delegatecall(data);
        
        if (!success) {
            if (returndata.length > 0) {
                // Bubble up the revert reason
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert CallFailed();
            }
        }
        
        return returndata;
    }
    
    /// @dev Delegates execution to an implementation contract (for fallback)
    function _delegate(address implementation) private {
        assembly {
            // Copy msg.data
            calldatacopy(0, 0, calldatasize())
            
            // Delegate call to the implementation
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            
            // Copy the returned data
            returndatacopy(0, 0, returndatasize())
            
            switch result
            case 0 {
                // Delegatecall failed, revert with returned data
                revert(0, returndatasize())
            }
            default {
                // Delegatecall succeeded, return data
                return(0, returndatasize())
            }
        }
    }
    
    /// @dev Gets the admin address from storage
    function _getAdmin() private view returns (address admin) {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            admin := sload(slot)
        }
    }
    
    /// @dev Sets the admin address in storage
    function _setAdmin(address admin) private {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            sstore(slot, admin)
        }
    }
    
    /// @dev Sets the implementation address in EIP-1967 slot
    function _setImplementation(address implementation) private {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, implementation)
        }
    }
}