// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ScriptUtils} from "./utils/ScriptUtils.s.sol";
import {AccountLens} from "../src/Lens/AccountLens.sol";
import {OracleLens} from "../src/Lens/OracleLens.sol";
import {IRMLens} from "../src/Lens/IRMLens.sol";
import {VaultLens} from "../src/Lens/VaultLens.sol";
import {UtilsLens} from "../src/Lens/UtilsLens.sol";

contract Lenses is ScriptUtils {
    function run()
        public
        broadcast
        returns (address accountLens, address oracleLens, address irmLens, address vaultLens, address utilsLens)
    {
        string memory inputScriptFileName = "08_Lenses_input.json";
        string memory outputScriptFileName = "08_Lenses_output.json";
        string memory json = getInputConfig(inputScriptFileName);
        address oracleAdapterRegistry = abi.decode(vm.parseJson(json, ".oracleAdapterRegistry"), (address));
        address kinkIRMFactory = abi.decode(vm.parseJson(json, ".kinkIRMFactory"), (address));

        (accountLens, oracleLens, irmLens, vaultLens, utilsLens) = execute(oracleAdapterRegistry, kinkIRMFactory);

        string memory object;
        object = vm.serializeAddress("lenses", "accountLens", accountLens);
        object = vm.serializeAddress("lenses", "oracleLens", oracleLens);
        object = vm.serializeAddress("lenses", "irmLens", irmLens);
        object = vm.serializeAddress("lenses", "vaultLens", vaultLens);
        object = vm.serializeAddress("lenses", "utilsLens", utilsLens);
        vm.writeJson(object, string.concat(vm.projectRoot(), "/script/", outputScriptFileName));
    }

    function deploy(address oracleAdapterRegistry, address kinkIRMFactory)
        public
        broadcast
        returns (address accountLens, address oracleLens, address irmLens, address vaultLens, address utilsLens)
    {
        (accountLens, oracleLens, irmLens, vaultLens, utilsLens) = execute(oracleAdapterRegistry, kinkIRMFactory);
    }

    function execute(address oracleAdapterRegistry, address kinkIRMFactory)
        public
        returns (address accountLens, address oracleLens, address irmLens, address vaultLens, address utilsLens)
    {
        accountLens = address(new AccountLens());
        oracleLens = address(new OracleLens(oracleAdapterRegistry));
        irmLens = address(new IRMLens(kinkIRMFactory));
        vaultLens = address(new VaultLens(address(oracleLens), address(irmLens)));
        utilsLens = address(new UtilsLens());
    }
}
