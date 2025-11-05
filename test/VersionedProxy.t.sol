// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/VersionedProxy.sol";

/**
 * @dev Mock implementation contracts for testing
 */
contract ImplementationV1 {
    uint256 public value;
    
    function setValue(uint256 _value) payable external {
        value = _value;
    }
    
    function getValue() external view returns (uint256) {
        return value;
    }
    
    function getVersion() external pure returns (string memory) {
        return "1.0.0";
    }
}

contract ImplementationV2 {
    uint256 public value;
    uint256 public multiplier;
    
    function setValue(uint256 _value) external {
        value = _value * 2; // Different behavior in V2
    }
    
    function getValue() external view returns (uint256) {
        return value;
    }
    
    function setMultiplier(uint256 _multiplier) external {
        multiplier = _multiplier;
    }
    
    function getVersion() external pure returns (string memory) {
        return "2.0.0";
    }
}

contract ImplementationV3 {
    uint256 public value;
    
    function setValue(uint256 _value) external {
        value = _value;
    }
    
    function getValue() external view returns (uint256) {
        return value;
    }
    
    function getVersion() external pure returns (string memory) {
        return "3.0.0";
    }
    
    function newFunction() external pure returns (uint256) {
        return 42;
    }
}

/**
 * @title VersionedProxyTest
 * @dev Comprehensive test suite for VersionedProxy
 */
contract VersionedProxyTest is Test {
    VersionedProxy public proxy;
    ImplementationV1 public implV1;
    ImplementationV2 public implV2;
    ImplementationV3 public implV3;
    
    address public admin;
    address public user;
    
    bytes32 public constant VERSION_1_0_0 = keccak256("1.0.0");
    bytes32 public constant VERSION_2_0_0 = keccak256("2.0.0");
    bytes32 public constant VERSION_3_0_0 = keccak256("3.0.0");
    
    event VersionRegistered(bytes32 version, address implementation);
    event DefaultVersionChanged(bytes32 oldVersion, bytes32 newVersion);
    
    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");
        
        // Deploy implementations
        implV1 = new ImplementationV1();
        implV2 = new ImplementationV2();
        implV3 = new ImplementationV3();
        
        // Deploy proxy
        vm.prank(admin);
        proxy = new VersionedProxy(admin);
    }
    
    /*//////////////////////////////////////////////////////////////
                        REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_RegisterVersion() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit VersionRegistered(VERSION_1_0_0, address(implV1));
        
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        
        assertEq(proxy.getImplementation(VERSION_1_0_0), address(implV1));
        assertEq(proxy.getDefaultVersion(), VERSION_1_0_0); // First version becomes default
    }
    
    function test_RegisterMultipleVersions() public {
        vm.startPrank(admin);
        
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        proxy.registerVersion(VERSION_2_0_0, address(implV2));
        proxy.registerVersion(VERSION_3_0_0, address(implV3));
        
        vm.stopPrank();
        
        assertEq(proxy.getImplementation(VERSION_1_0_0), address(implV1));
        assertEq(proxy.getImplementation(VERSION_2_0_0), address(implV2));
        assertEq(proxy.getImplementation(VERSION_3_0_0), address(implV3));
        
        bytes32[] memory versions = proxy.getVersions();
        assertEq(versions.length, 3);
    }
    
    function test_RevertWhen_RegisterVersionUnauthorized() public {
        vm.prank(user);
        vm.expectRevert(VersionedProxy.UnauthorizedCaller.selector);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
    }
    
    function test_RevertWhen_RegisterInvalidImplementation() public {
        vm.startPrank(admin);
        
        // Zero address
        vm.expectRevert(VersionedProxy.InvalidImplementation.selector);
        proxy.registerVersion(VERSION_1_0_0, address(0));
        
        // EOA (no code)
        vm.expectRevert(VersionedProxy.InvalidImplementation.selector);
        proxy.registerVersion(VERSION_1_0_0, user);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_RegisterDuplicateVersion() public {
        vm.startPrank(admin);
        
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        
        vm.expectRevert(abi.encodeWithSelector(
            VersionedProxy.VersionAlreadyExists.selector,
            VERSION_1_0_0
        ));
        proxy.registerVersion(VERSION_1_0_0, address(implV2));
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                        REMOVAL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_RemoveVersion() public {
        vm.startPrank(admin);
        
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        proxy.registerVersion(VERSION_2_0_0, address(implV2));
        proxy.setDefaultVersion(VERSION_2_0_0);
        
        // Should be able to remove non-default version
        proxy.removeVersion(VERSION_1_0_0);
        
        vm.expectRevert(abi.encodeWithSelector(
            VersionedProxy.VersionNotFound.selector,
            VERSION_1_0_0
        ));
        proxy.getImplementation(VERSION_1_0_0);
        
        bytes32[] memory versions = proxy.getVersions();
        assertEq(versions.length, 1);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_RemoveDefaultVersion() public {
        vm.startPrank(admin);
        
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        
        vm.expectRevert(VersionedProxy.CannotRemoveDefaultVersion.selector);
        proxy.removeVersion(VERSION_1_0_0);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_RemoveNonExistentVersion() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(
            VersionedProxy.VersionNotFound.selector,
            VERSION_1_0_0
        ));
        proxy.removeVersion(VERSION_1_0_0);
    }
    
    function test_RevertWhen_RemoveVersionUnauthorized() public {
        vm.prank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        
        vm.prank(user);
        vm.expectRevert(VersionedProxy.UnauthorizedCaller.selector);
        proxy.removeVersion(VERSION_1_0_0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        DEFAULT VERSION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetDefaultVersion() public {
        vm.startPrank(admin);
        
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        proxy.registerVersion(VERSION_2_0_0, address(implV2));
        
        vm.expectEmit(true, true, false, true);
        emit DefaultVersionChanged(VERSION_1_0_0, VERSION_2_0_0);
        
        proxy.setDefaultVersion(VERSION_2_0_0);
        
        assertEq(proxy.getDefaultVersion(), VERSION_2_0_0);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_SetDefaultVersionNonExistent() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(
            VersionedProxy.VersionNotFound.selector,
            VERSION_1_0_0
        ));
        proxy.setDefaultVersion(VERSION_1_0_0);
    }
    
    function test_RevertWhen_SetDefaultVersionUnauthorized() public {
        vm.prank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        
        vm.prank(user);
        vm.expectRevert(VersionedProxy.UnauthorizedCaller.selector);
        proxy.setDefaultVersion(VERSION_1_0_0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        EXECUTE AT VERSION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ExecuteAtVersion() public {
        vm.prank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);
        proxy.executeAtVersion(VERSION_1_0_0, data);
        
        // Verify value was set in proxy storage
        bytes memory getData = abi.encodeWithSignature("getValue()");
        bytes memory result = proxy.executeAtVersion(VERSION_1_0_0, getData);
        uint256 value = abi.decode(result, (uint256));
        
        assertEq(value, 42);
    }
    
    function test_ExecuteAtVersionWithDifferentVersions() public {
        vm.startPrank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        proxy.registerVersion(VERSION_2_0_0, address(implV2));
        vm.stopPrank();
        
        // Set value using V1 (stores value as-is)
        bytes memory setData = abi.encodeWithSignature("setValue(uint256)", 10);
        proxy.executeAtVersion(VERSION_1_0_0, setData);
        
        bytes memory getData = abi.encodeWithSignature("getValue()");
        bytes memory result = proxy.executeAtVersion(VERSION_1_0_0, getData);
        assertEq(abi.decode(result, (uint256)), 10);
        
        // Set value using V2 (stores value * 2)
        proxy.executeAtVersion(VERSION_2_0_0, setData);
        result = proxy.executeAtVersion(VERSION_2_0_0, getData);
        assertEq(abi.decode(result, (uint256)), 20);
    }
    
    function test_ExecuteAtVersionWithPayable() public {
        vm.prank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        
        // Send ETH with call
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 100);
        proxy.executeAtVersion{value: 1 ether}(VERSION_1_0_0, data);
        
        assertEq(address(proxy).balance, 1 ether);
    }
    
    function test_RevertWhen_ExecuteAtVersionNonExistent() public {
        vm.expectRevert(abi.encodeWithSelector(
            VersionedProxy.VersionNotFound.selector,
            VERSION_1_0_0
        ));
        proxy.executeAtVersion(VERSION_1_0_0, "");
    }
    
    function test_ExecuteAtVersionBubblesRevert() public {
        vm.prank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        
        // Call non-existent function
        bytes memory data = abi.encodeWithSignature("nonExistentFunction()");
        
        vm.expectRevert();
        proxy.executeAtVersion(VERSION_1_0_0, data);
    }
    
    /*//////////////////////////////////////////////////////////////
                        FALLBACK TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_FallbackToDefaultVersion() public {
        vm.prank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        
        // Call through fallback
        ImplementationV1 proxied = ImplementationV1(address(proxy));
        proxied.setValue(123);
        
        assertEq(proxied.getValue(), 123);
        assertEq(proxied.getVersion(), "1.0.0");
    }
    
    function test_FallbackAfterDefaultVersionChange() public {
        vm.startPrank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        proxy.registerVersion(VERSION_2_0_0, address(implV2));
        vm.stopPrank();
        
        ImplementationV1 proxiedV1 = ImplementationV1(address(proxy));
        proxiedV1.setValue(10);
        assertEq(proxiedV1.getValue(), 10);
        
        // Change default version
        vm.prank(admin);
        proxy.setDefaultVersion(VERSION_2_0_0);
        
        // Now fallback uses V2 (which doubles the value)
        ImplementationV2 proxiedV2 = ImplementationV2(address(proxy));
        proxiedV2.setValue(10);
        assertEq(proxiedV2.getValue(), 20);
    }
    
    function test_RevertWhen_FallbackNoDefaultVersion() public {
        // Don't register any version
        ImplementationV1 proxied = ImplementationV1(address(proxy));
        
        vm.expectRevert();
        proxied.setValue(42);
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_BackwardCompatibility() public {
        vm.startPrank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        proxy.registerVersion(VERSION_2_0_0, address(implV2));
        proxy.registerVersion(VERSION_3_0_0, address(implV3));
        proxy.setDefaultVersion(VERSION_3_0_0);
        vm.stopPrank();
        
        // User can still use V1 explicitly
        bytes memory setData = abi.encodeWithSignature("setValue(uint256)", 50);
        proxy.executeAtVersion(VERSION_1_0_0, setData);
        
        bytes memory getData = abi.encodeWithSignature("getValue()");
        bytes memory result = proxy.executeAtVersion(VERSION_1_0_0, getData);
        assertEq(abi.decode(result, (uint256)), 50);
        
        // Default uses V3
        ImplementationV3 proxied = ImplementationV3(address(proxy));
        proxied.setValue(100);
        assertEq(proxied.getValue(), 100);
        assertEq(proxied.newFunction(), 42);
    }
    
    function test_GradualMigration() public {
        vm.startPrank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        vm.stopPrank();
        
        // Initial users use V1 via fallback
        ImplementationV1 proxied = ImplementationV1(address(proxy));
        proxied.setValue(10);
        assertEq(proxied.getValue(), 10);
        
        // Admin deploys V2 and sets as default
        vm.startPrank(admin);
        proxy.registerVersion(VERSION_2_0_0, address(implV2));
        proxy.setDefaultVersion(VERSION_2_0_0);
        vm.stopPrank();
        
        // New users get V2 by default
        ImplementationV2 proxiedV2 = ImplementationV2(address(proxy));
        proxiedV2.setValue(10);
        assertEq(proxiedV2.getValue(), 20);
        
        // Legacy integrations can still explicitly use V1
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 15);
        proxy.executeAtVersion(VERSION_1_0_0, data);
        
        data = abi.encodeWithSignature("getValue()");
        bytes memory result = proxy.executeAtVersion(VERSION_1_0_0, data);
        assertEq(abi.decode(result, (uint256)), 15);
    }
    
    function test_MaliciousUpgradeProtection() public {
        vm.startPrank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        proxy.registerVersion(VERSION_2_0_0, address(implV2));
        vm.stopPrank();
        
        // User verifies and trusts V1
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 100);
        proxy.executeAtVersion(VERSION_1_0_0, data);
        
        // Admin sets V2 as default (potentially malicious)
        vm.prank(admin);
        proxy.setDefaultVersion(VERSION_2_0_0);
        
        // User can continue using trusted V1
        data = abi.encodeWithSignature("getValue()");
        bytes memory result = proxy.executeAtVersion(VERSION_1_0_0, data);
        assertEq(abi.decode(result, (uint256)), 100);
        
        // User is not forced to use potentially malicious V2
    }
    
    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetVersions() public {
        vm.startPrank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        proxy.registerVersion(VERSION_2_0_0, address(implV2));
        proxy.registerVersion(VERSION_3_0_0, address(implV3));
        vm.stopPrank();
        
        bytes32[] memory versions = proxy.getVersions();
        assertEq(versions.length, 3);
        
        // Verify all versions are present (order may vary)
        bool hasV1 = false;
        bool hasV2 = false;
        bool hasV3 = false;
        
        for (uint256 i = 0; i < versions.length; i++) {
            if (versions[i] == VERSION_1_0_0) hasV1 = true;
            if (versions[i] == VERSION_2_0_0) hasV2 = true;
            if (versions[i] == VERSION_3_0_0) hasV3 = true;
        }
        
        assertTrue(hasV1 && hasV2 && hasV3);
    }
    
    function test_GetVersionsAfterRemoval() public {
        vm.startPrank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        proxy.registerVersion(VERSION_2_0_0, address(implV2));
        proxy.setDefaultVersion(VERSION_2_0_0);
        proxy.removeVersion(VERSION_1_0_0);
        vm.stopPrank();
        
        bytes32[] memory versions = proxy.getVersions();
        assertEq(versions.length, 1);
        assertEq(versions[0], VERSION_2_0_0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        RECEIVE/PAYABLE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ReceiveEther() public {
        vm.deal(user, 10 ether);
        
        vm.prank(user);
        (bool success,) = address(proxy).call{value: 5 ether}("");
        
        assertTrue(success);
        assertEq(address(proxy).balance, 5 ether);
    }
    
    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_RegisterAndExecute(uint256 value) public {
        vm.assume(value < type(uint256).max / 2); // Avoid overflow in V2
        
        vm.startPrank(admin);
        proxy.registerVersion(VERSION_1_0_0, address(implV1));
        proxy.registerVersion(VERSION_2_0_0, address(implV2));
        vm.stopPrank();
        
        bytes memory setData = abi.encodeWithSignature("setValue(uint256)", value);
        proxy.executeAtVersion(VERSION_1_0_0, setData);
        
        bytes memory getData = abi.encodeWithSignature("getValue()");
        bytes memory result = proxy.executeAtVersion(VERSION_1_0_0, getData);
        assertEq(abi.decode(result, (uint256)), value);
        
        // V2 doubles the value
        proxy.executeAtVersion(VERSION_2_0_0, setData);
        result = proxy.executeAtVersion(VERSION_2_0_0, getData);
        assertEq(abi.decode(result, (uint256)), value * 2);
    }
    
    function testFuzz_VersionIdentifiers(bytes32 version) public {
        vm.assume(version != bytes32(0));
        
        vm.prank(admin);
        proxy.registerVersion(version, address(implV1));
        
        assertEq(proxy.getImplementation(version), address(implV1));
        assertEq(proxy.getDefaultVersion(), version);
    }
}