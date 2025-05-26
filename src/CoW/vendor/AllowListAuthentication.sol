// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

/// @title AllowListAuthentication
/// @notice Interface for GPv2AllowListAuthentication contract
interface AllowListAuthentication {
    /// @notice Adds a new solver to the allowlist
    /// @param solver The address of the solver to add
    function addSolver(address solver) external;

    /// @notice Checks if an address is a valid solver
    /// @param prospectiveSolver The address to check
    /// @return True if the address is a valid solver, false otherwise
    function isSolver(address prospectiveSolver) external view returns (bool);
}
