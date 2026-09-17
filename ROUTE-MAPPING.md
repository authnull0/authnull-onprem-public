# ROUTE-MAPPING.md — registered HTTP routes

**Generated** from the live Gin engine. Do not hand-edit; regenerate with:

```sh
ROUTE_DUMP=routes_output.json go test ./cmd/authnull-service/ -run TestDumpRoutes
python3 scripts/gen_routemap.py   # or re-run the generator used to produce this file
```

`routes_output.json` is the machine-readable form of the same dump.

## Actual URL scheme

Everything is mounted under **`/api/v1`** by `RegisterAllRoutes` in
[cmd/authnull-service/routes.go](cmd/authnull-service/routes.go), plus a set of
root-level and legacy aliases kept for the admin UI and the self-service console.

> **Correction to earlier revisions of this document.** Previous versions of this
> file specified a `/{tier}/v1/{service}/{action}` scheme with `admin` / `ssc` /
> `tenant` tiers and listed 486 routes. **That scheme was never implemented.** No
> `/admin/v1`, `/ssc/v1` or `/tenant/v1` group exists anywhere in the Go source.
> The `// OLD:` / `// NEW:` comments still present above many route registrations
> refer to that abandoned plan and describe paths that are not served. This
> document now reflects what the engine actually registers.

**Total registered routes: 1196**

| Method | Count |
|---|---|
| DELETE | 24 |
| GET | 74 |
| OPTIONS | 2 |
| POST | 1039 |
| PUT | 57 |

The count is higher than the number of distinct handlers because several modules
are deliberately registered on more than one prefix (for example `pam` is mounted
at both `/api/v1/pam` and `/pam/api/v1`, and `tenant` at `/api/v1/tenant`,
`/api/v1/tenants` and `/api/v1/tenants/tenants`).

**Duplicate method+path check: PASS — none**

Gin panics on a duplicate method+path registration, so a booting server is itself
proof of no collisions. `TestRegisterAllRoutes` covers this in CI.

## Groups

| Group | Routes |
|---|---|
| pam (canonical) | 133 |
| pam (UI alias) | 133 |
| policy (policyService alias) | 23 |
| policy | 74 |
| dashboard (dashboardService alias) | 9 |
| dashboard | 9 |
| database (databaseService alias) | 26 |
| database | 26 |
| serviceaccounts | 11 |
| serviceaccounts (UI alias) | 11 |
| tenant (double-prefix alias) | 70 |
| tenant + org (SSC alias) | 81 |
| tenant | 70 |
| issuer | 46 |
| issuer (short-path alias) | 12 |
| wallet | 28 |
| verifier | 10 |
| user | 94 |
| org | 8 |
| endpoint | 9 |
| entra | 2 |
| ad | 100 |
| mfa | 42 |
| dbconsole | 4 |
| secretservice (stub) | 2 |
| ad (root alias) | 100 |
| mfa (SSC /authentication alias) | 60 |
| authnz (proxy) | 2 |
| ssc redirect | 1 |

## pam (canonical)  (133)

| Method | Path |
|---|---|
| POST | `/api/v1/pam/addActiveDirectory` |
| POST | `/api/v1/pam/addEPMGroup` |
| DELETE | `/api/v1/pam/apps/:id` |
| POST | `/api/v1/pam/apps/:id` |
| PUT | `/api/v1/pam/apps/:id` |
| POST | `/api/v1/pam/apps/addApp` |
| POST | `/api/v1/pam/apps/listAll` |
| POST | `/api/v1/pam/checkouts/assignEpmUserToWallet` |
| POST | `/api/v1/pam/checkouts/assignedUserCheckout` |
| POST | `/api/v1/pam/checkouts/assignedUserGeneratePasswordVc` |
| POST | `/api/v1/pam/checkouts/assignedUserGeneratePasswordlessVc` |
| POST | `/api/v1/pam/checkouts/assignedUserGenerateRdpPasswordVc` |
| POST | `/api/v1/pam/checkouts/assignedUserGenerateSshVc` |
| POST | `/api/v1/pam/checkouts/assignedUserGenerateVncPasswordVc` |
| POST | `/api/v1/pam/checkouts/assignedUserGetCheckoutJob` |
| PUT | `/api/v1/pam/checkouts/assignedUserUpdateCheckoutJob` |
| POST | `/api/v1/pam/checkouts/getLastCheckoutJob` |
| POST | `/api/v1/pam/checkouts/pollCheckoutUser` |
| POST | `/api/v1/pam/connections/createConnections` |
| POST | `/api/v1/pam/connections/credType` |
| DELETE | `/api/v1/pam/connections/deleteConnection` |
| POST | `/api/v1/pam/connections/listAssignedConnections` |
| POST | `/api/v1/pam/connections/listConnections` |
| POST | `/api/v1/pam/connections/statusConnection` |
| POST | `/api/v1/pam/connections/updateGuacdStatus` |
| POST | `/api/v1/pam/connections/updateServiceStatus` |
| DELETE | `/api/v1/pam/deleteEPMGroup` |
| PUT | `/api/v1/pam/endpointUsers/addEpmUserCredPolicy` |
| POST | `/api/v1/pam/endpointUsers/addEpmUserInfo` |
| POST | `/api/v1/pam/endpointUsers/credentialRotationPolicy` |
| DELETE | `/api/v1/pam/endpointUsers/deleteEpmUser` |
| DELETE | `/api/v1/pam/endpointUsers/deleteEpmUserCached` |
| POST | `/api/v1/pam/endpointUsers/donwloadSshKey` |
| POST | `/api/v1/pam/endpointUsers/epmUserDetail` |
| PUT | `/api/v1/pam/endpointUsers/escalatePrivileges` |
| POST | `/api/v1/pam/endpointUsers/expiryForAgentToken` |
| POST | `/api/v1/pam/endpointUsers/generateAgentkey` |
| POST | `/api/v1/pam/endpointUsers/generateRandPassword` |
| POST | `/api/v1/pam/endpointUsers/generateSshKey` |
| POST | `/api/v1/pam/endpointUsers/getAgentkey` |
| POST | `/api/v1/pam/endpointUsers/listAllEpmUsers` |
| POST | `/api/v1/pam/endpointUsers/listEpmUserBuffer` |
| PUT | `/api/v1/pam/endpointUsers/updateEpmUserInfo` |
| PUT | `/api/v1/pam/endpointUsers/updatePasswordHashUsers` |
| PUT | `/api/v1/pam/endpointUsers/updateUserWallet` |
| POST | `/api/v1/pam/endpointUsers/viewCredential` |
| POST | `/api/v1/pam/getImportStatus` |
| GET | `/api/v1/pam/groups/:groupId` |
| POST | `/api/v1/pam/groups/addGroup` |
| DELETE | `/api/v1/pam/groups/deleteGroup` |
| POST | `/api/v1/pam/groups/listAll` |
| PUT | `/api/v1/pam/groups/updateGroup` |
| POST | `/api/v1/pam/importUsers` |
| POST | `/api/v1/pam/instanceGroup/addAuthFlowToInstanceGroup` |
| POST | `/api/v1/pam/instanceGroup/addInstanceGroup` |
| POST | `/api/v1/pam/instanceGroup/assignUsersToEndpointGroup` |
| DELETE | `/api/v1/pam/instanceGroup/deleteEndpointGroup` |
| PUT | `/api/v1/pam/instanceGroup/editInstanceGroup` |
| POST | `/api/v1/pam/instanceGroup/fetchInstanceGroupDetail` |
| POST | `/api/v1/pam/instanceGroup/listEndpointGroup` |
| PUT | `/api/v1/pam/instanceGroup/updateInstanceGroupStatus` |
| POST | `/api/v1/pam/instances/addCredentialRotationPolicy` |
| POST | `/api/v1/pam/instances/addInstance` |
| POST | `/api/v1/pam/instances/addPasswordPolicy` |
| POST | `/api/v1/pam/instances/assignGroupToMachines` |
| PUT | `/api/v1/pam/instances/assignPolicyToMachine` |
| POST | `/api/v1/pam/instances/assignUsersToMachines` |
| DELETE | `/api/v1/pam/instances/deleteCredentialRotationPolicy` |
| DELETE | `/api/v1/pam/instances/deletePasswordPolicy` |
| POST | `/api/v1/pam/instances/getCredentialRotationPolicy` |
| POST | `/api/v1/pam/instances/getVncPassword` |
| POST | `/api/v1/pam/instances/list` |
| POST | `/api/v1/pam/instances/listAllCredentialRotationPolicy` |
| POST | `/api/v1/pam/instances/listAssignCredential` |
| POST | `/api/v1/pam/instances/listAssignedInstances` |
| POST | `/api/v1/pam/instances/listPasswordPolicy` |
| POST | `/api/v1/pam/instances/setVncPassword` |
| PUT | `/api/v1/pam/instances/updateAuthType` |
| PUT | `/api/v1/pam/instances/updateCredentialRotationPolicy` |
| POST | `/api/v1/pam/instances/updateCredentialRotationPolicyLastRunTime` |
| PUT | `/api/v1/pam/instances/updateInstanceStatus` |
| PUT | `/api/v1/pam/instances/updatePasswordPolicy` |
| POST | `/api/v1/pam/instances/viewGeneratedPamCode` |
| POST | `/api/v1/pam/integrations/activeDirectory/importCsv` |
| POST | `/api/v1/pam/integrations/importUsers` |
| POST | `/api/v1/pam/jumpserver/addJumpServer` |
| DELETE | `/api/v1/pam/jumpserver/deleteJumpServer` |
| POST | `/api/v1/pam/jumpserver/getEndpointJob` |
| POST | `/api/v1/pam/jumpserver/listJumpServer` |
| PUT | `/api/v1/pam/jumpserver/totalOpenJobs` |
| PUT | `/api/v1/pam/jumpserver/updateEndpointJobStatus` |
| PUT | `/api/v1/pam/jumpserver/updateJumpServer` |
| PUT | `/api/v1/pam/jumpserver/updateStatus` |
| POST | `/api/v1/pam/listAllActiveDirectories` |
| POST | `/api/v1/pam/listAllEPMGroup` |
| POST | `/api/v1/pam/login` |
| POST | `/api/v1/pam/login/authenticate` |
| POST | `/api/v1/pam/lumsAgent/importUsers` |
| POST | `/api/v1/pam/lumsAgent/registerAgent` |
| POST | `/api/v1/pam/lumsAgent/updateAgent` |
| POST | `/api/v1/pam/lumsAgent/updateEndpointLastActive` |
| POST | `/api/v1/pam/network_device/CreateDevice` |
| POST | `/api/v1/pam/network_device/DeleteDevice` |
| POST | `/api/v1/pam/network_device/ListDevices` |
| POST | `/api/v1/pam/reConfigure` |
| POST | `/api/v1/pam/registerAgent` |
| POST | `/api/v1/pam/registerUser` |
| POST | `/api/v1/pam/saveActiveDirectoryConfig` |
| POST | `/api/v1/pam/sessionRecording/addSessionRecording` |
| POST | `/api/v1/pam/sessionRecording/listSessionRecording` |
| POST | `/api/v1/pam/simpleAuth/configFactorperTenant` |
| POST | `/api/v1/pam/simpleAuth/retrieveCredentials` |
| POST | `/api/v1/pam/simpleAuth/retrieveFactors` |
| GET | `/api/v1/pam/status` |
| PUT | `/api/v1/pam/updateEPMGroupCredEscalation` |
| PUT | `/api/v1/pam/updateEPMGroupStatus` |
| PUT | `/api/v1/pam/updateEPMGroupUsers` |
| PUT | `/api/v1/pam/updateStatus` |
| POST | `/api/v1/pam/userPrivileges/getResourcePath` |
| POST | `/api/v1/pam/users/:userId` |
| POST | `/api/v1/pam/users/addUser` |
| DELETE | `/api/v1/pam/users/deleteUser` |
| PUT | `/api/v1/pam/users/disableUser` |
| PUT | `/api/v1/pam/users/enableUser` |
| POST | `/api/v1/pam/users/listAll` |
| POST | `/api/v1/pam/users/onboardUser` |
| PUT | `/api/v1/pam/users/updateUser` |
| POST | `/api/v1/pam/userservice/addUser` |
| POST | `/api/v1/pam/userservice/generateADCredentials` |
| POST | `/api/v1/pam/userservice/generateUserDid` |
| POST | `/api/v1/pam/userservice/registerWallet` |
| POST | `/api/v1/pam/userservice/sendEmail` |
| POST | `/api/v1/pam/validateEmail` |

## pam (UI alias)  (133)

| Method | Path |
|---|---|
| POST | `/pam/api/v1/addActiveDirectory` |
| POST | `/pam/api/v1/addEPMGroup` |
| DELETE | `/pam/api/v1/apps/:id` |
| POST | `/pam/api/v1/apps/:id` |
| PUT | `/pam/api/v1/apps/:id` |
| POST | `/pam/api/v1/apps/addApp` |
| POST | `/pam/api/v1/apps/listAll` |
| POST | `/pam/api/v1/checkouts/assignEpmUserToWallet` |
| POST | `/pam/api/v1/checkouts/assignedUserCheckout` |
| POST | `/pam/api/v1/checkouts/assignedUserGeneratePasswordVc` |
| POST | `/pam/api/v1/checkouts/assignedUserGeneratePasswordlessVc` |
| POST | `/pam/api/v1/checkouts/assignedUserGenerateRdpPasswordVc` |
| POST | `/pam/api/v1/checkouts/assignedUserGenerateSshVc` |
| POST | `/pam/api/v1/checkouts/assignedUserGenerateVncPasswordVc` |
| POST | `/pam/api/v1/checkouts/assignedUserGetCheckoutJob` |
| PUT | `/pam/api/v1/checkouts/assignedUserUpdateCheckoutJob` |
| POST | `/pam/api/v1/checkouts/getLastCheckoutJob` |
| POST | `/pam/api/v1/checkouts/pollCheckoutUser` |
| POST | `/pam/api/v1/connections/createConnections` |
| POST | `/pam/api/v1/connections/credType` |
| DELETE | `/pam/api/v1/connections/deleteConnection` |
| POST | `/pam/api/v1/connections/listAssignedConnections` |
| POST | `/pam/api/v1/connections/listConnections` |
| POST | `/pam/api/v1/connections/statusConnection` |
| POST | `/pam/api/v1/connections/updateGuacdStatus` |
| POST | `/pam/api/v1/connections/updateServiceStatus` |
| DELETE | `/pam/api/v1/deleteEPMGroup` |
| PUT | `/pam/api/v1/endpointUsers/addEpmUserCredPolicy` |
| POST | `/pam/api/v1/endpointUsers/addEpmUserInfo` |
| POST | `/pam/api/v1/endpointUsers/credentialRotationPolicy` |
| DELETE | `/pam/api/v1/endpointUsers/deleteEpmUser` |
| DELETE | `/pam/api/v1/endpointUsers/deleteEpmUserCached` |
| POST | `/pam/api/v1/endpointUsers/donwloadSshKey` |
| POST | `/pam/api/v1/endpointUsers/epmUserDetail` |
| PUT | `/pam/api/v1/endpointUsers/escalatePrivileges` |
| POST | `/pam/api/v1/endpointUsers/expiryForAgentToken` |
| POST | `/pam/api/v1/endpointUsers/generateAgentkey` |
| POST | `/pam/api/v1/endpointUsers/generateRandPassword` |
| POST | `/pam/api/v1/endpointUsers/generateSshKey` |
| POST | `/pam/api/v1/endpointUsers/getAgentkey` |
| POST | `/pam/api/v1/endpointUsers/listAllEpmUsers` |
| POST | `/pam/api/v1/endpointUsers/listEpmUserBuffer` |
| PUT | `/pam/api/v1/endpointUsers/updateEpmUserInfo` |
| PUT | `/pam/api/v1/endpointUsers/updatePasswordHashUsers` |
| PUT | `/pam/api/v1/endpointUsers/updateUserWallet` |
| POST | `/pam/api/v1/endpointUsers/viewCredential` |
| POST | `/pam/api/v1/getImportStatus` |
| GET | `/pam/api/v1/groups/:groupId` |
| POST | `/pam/api/v1/groups/addGroup` |
| DELETE | `/pam/api/v1/groups/deleteGroup` |
| POST | `/pam/api/v1/groups/listAll` |
| PUT | `/pam/api/v1/groups/updateGroup` |
| POST | `/pam/api/v1/importUsers` |
| POST | `/pam/api/v1/instanceGroup/addAuthFlowToInstanceGroup` |
| POST | `/pam/api/v1/instanceGroup/addInstanceGroup` |
| POST | `/pam/api/v1/instanceGroup/assignUsersToEndpointGroup` |
| DELETE | `/pam/api/v1/instanceGroup/deleteEndpointGroup` |
| PUT | `/pam/api/v1/instanceGroup/editInstanceGroup` |
| POST | `/pam/api/v1/instanceGroup/fetchInstanceGroupDetail` |
| POST | `/pam/api/v1/instanceGroup/listEndpointGroup` |
| PUT | `/pam/api/v1/instanceGroup/updateInstanceGroupStatus` |
| POST | `/pam/api/v1/instances/addCredentialRotationPolicy` |
| POST | `/pam/api/v1/instances/addInstance` |
| POST | `/pam/api/v1/instances/addPasswordPolicy` |
| POST | `/pam/api/v1/instances/assignGroupToMachines` |
| PUT | `/pam/api/v1/instances/assignPolicyToMachine` |
| POST | `/pam/api/v1/instances/assignUsersToMachines` |
| DELETE | `/pam/api/v1/instances/deleteCredentialRotationPolicy` |
| DELETE | `/pam/api/v1/instances/deletePasswordPolicy` |
| POST | `/pam/api/v1/instances/getCredentialRotationPolicy` |
| POST | `/pam/api/v1/instances/getVncPassword` |
| POST | `/pam/api/v1/instances/list` |
| POST | `/pam/api/v1/instances/listAllCredentialRotationPolicy` |
| POST | `/pam/api/v1/instances/listAssignCredential` |
| POST | `/pam/api/v1/instances/listAssignedInstances` |
| POST | `/pam/api/v1/instances/listPasswordPolicy` |
| POST | `/pam/api/v1/instances/setVncPassword` |
| PUT | `/pam/api/v1/instances/updateAuthType` |
| PUT | `/pam/api/v1/instances/updateCredentialRotationPolicy` |
| POST | `/pam/api/v1/instances/updateCredentialRotationPolicyLastRunTime` |
| PUT | `/pam/api/v1/instances/updateInstanceStatus` |
| PUT | `/pam/api/v1/instances/updatePasswordPolicy` |
| POST | `/pam/api/v1/instances/viewGeneratedPamCode` |
| POST | `/pam/api/v1/integrations/activeDirectory/importCsv` |
| POST | `/pam/api/v1/integrations/importUsers` |
| POST | `/pam/api/v1/jumpserver/addJumpServer` |
| DELETE | `/pam/api/v1/jumpserver/deleteJumpServer` |
| POST | `/pam/api/v1/jumpserver/getEndpointJob` |
| POST | `/pam/api/v1/jumpserver/listJumpServer` |
| PUT | `/pam/api/v1/jumpserver/totalOpenJobs` |
| PUT | `/pam/api/v1/jumpserver/updateEndpointJobStatus` |
| PUT | `/pam/api/v1/jumpserver/updateJumpServer` |
| PUT | `/pam/api/v1/jumpserver/updateStatus` |
| POST | `/pam/api/v1/listAllActiveDirectories` |
| POST | `/pam/api/v1/listAllEPMGroup` |
| POST | `/pam/api/v1/login` |
| POST | `/pam/api/v1/login/authenticate` |
| POST | `/pam/api/v1/lumsAgent/importUsers` |
| POST | `/pam/api/v1/lumsAgent/registerAgent` |
| POST | `/pam/api/v1/lumsAgent/updateAgent` |
| POST | `/pam/api/v1/lumsAgent/updateEndpointLastActive` |
| POST | `/pam/api/v1/network_device/CreateDevice` |
| POST | `/pam/api/v1/network_device/DeleteDevice` |
| POST | `/pam/api/v1/network_device/ListDevices` |
| POST | `/pam/api/v1/reConfigure` |
| POST | `/pam/api/v1/registerAgent` |
| POST | `/pam/api/v1/registerUser` |
| POST | `/pam/api/v1/saveActiveDirectoryConfig` |
| POST | `/pam/api/v1/sessionRecording/addSessionRecording` |
| POST | `/pam/api/v1/sessionRecording/listSessionRecording` |
| POST | `/pam/api/v1/simpleAuth/configFactorperTenant` |
| POST | `/pam/api/v1/simpleAuth/retrieveCredentials` |
| POST | `/pam/api/v1/simpleAuth/retrieveFactors` |
| GET | `/pam/api/v1/status` |
| PUT | `/pam/api/v1/updateEPMGroupCredEscalation` |
| PUT | `/pam/api/v1/updateEPMGroupStatus` |
| PUT | `/pam/api/v1/updateEPMGroupUsers` |
| PUT | `/pam/api/v1/updateStatus` |
| POST | `/pam/api/v1/userPrivileges/getResourcePath` |
| POST | `/pam/api/v1/users/:userId` |
| POST | `/pam/api/v1/users/addUser` |
| DELETE | `/pam/api/v1/users/deleteUser` |
| PUT | `/pam/api/v1/users/disableUser` |
| PUT | `/pam/api/v1/users/enableUser` |
| POST | `/pam/api/v1/users/listAll` |
| POST | `/pam/api/v1/users/onboardUser` |
| PUT | `/pam/api/v1/users/updateUser` |
| POST | `/pam/api/v1/userservice/addUser` |
| POST | `/pam/api/v1/userservice/generateADCredentials` |
| POST | `/pam/api/v1/userservice/generateUserDid` |
| POST | `/pam/api/v1/userservice/registerWallet` |
| POST | `/pam/api/v1/userservice/sendEmail` |
| POST | `/pam/api/v1/validateEmail` |

## policy (policyService alias)  (23)

| Method | Path |
|---|---|
| POST | `/api/v1/policyService/ApprovePolicy` |
| POST | `/api/v1/policyService/CreatePolicy` |
| POST | `/api/v1/policyService/FilterPolicy` |
| POST | `/api/v1/policyService/IsPolicyExists` |
| POST | `/api/v1/policyService/ListPolicy` |
| POST | `/api/v1/policyService/SearchPolicy` |
| POST | `/api/v1/policyService/UpdatePolicy` |
| POST | `/api/v1/policyService/activateEndpointRule` |
| POST | `/api/v1/policyService/addEndpoint` |
| POST | `/api/v1/policyService/authenticationLog` |
| POST | `/api/v1/policyService/changeStatus` |
| POST | `/api/v1/policyService/createEndpointrule` |
| POST | `/api/v1/policyService/deactivateEndpointRule` |
| POST | `/api/v1/policyService/listAD` |
| POST | `/api/v1/policyService/listADGroups` |
| POST | `/api/v1/policyService/listEndpointRule` |
| POST | `/api/v1/policyService/listEndpointUser` |
| POST | `/api/v1/policyService/listEndpoints` |
| POST | `/api/v1/policyService/listLinuxCommands` |
| POST | `/api/v1/policyService/listOU` |
| POST | `/api/v1/policyService/logAccessRequest` |
| POST | `/api/v1/policyService/storeSudoers` |
| POST | `/api/v1/policyService/updateEndpointRule` |

## policy  (74)

| Method | Path |
|---|---|
| POST | `/api/v1/policy/accessRequest` |
| POST | `/api/v1/policy/activateADGroupJob` |
| POST | `/api/v1/policy/activateEndpointRule` |
| POST | `/api/v1/policy/activateManualEndpointRule` |
| POST | `/api/v1/policy/addEndpoint` |
| POST | `/api/v1/policy/approvePolicy` |
| POST | `/api/v1/policy/archiveRequest` |
| POST | `/api/v1/policy/auth/evaluateAuth` |
| POST | `/api/v1/policy/auth/listAuthDecisions` |
| POST | `/api/v1/policy/authenticationLog` |
| POST | `/api/v1/policy/changeStatus` |
| POST | `/api/v1/policy/createADGroupJob` |
| POST | `/api/v1/policy/createEndpointrule` |
| POST | `/api/v1/policy/createManualEndpointRule` |
| POST | `/api/v1/policy/createPolicy` |
| POST | `/api/v1/policy/deactivateADGroupJob` |
| POST | `/api/v1/policy/deactivateEndpointRule` |
| POST | `/api/v1/policy/deactivateManualEndpointRule` |
| POST | `/api/v1/policy/deleteManualEndpointRule` |
| POST | `/api/v1/policy/filterAccessRequest` |
| POST | `/api/v1/policy/filterPolicy` |
| POST | `/api/v1/policy/isPolicyExists` |
| POST | `/api/v1/policy/json/aggregatePolicies` |
| POST | `/api/v1/policy/json/aggregateRequests` |
| POST | `/api/v1/policy/json/applyDiscoveredPolicies` |
| POST | `/api/v1/policy/json/approveAllBaselines` |
| POST | `/api/v1/policy/json/approvePolicy` |
| POST | `/api/v1/policy/json/approvePolicyAgentless` |
| POST | `/api/v1/policy/json/createBaselinePolicy` |
| POST | `/api/v1/policy/json/createPolicy` |
| POST | `/api/v1/policy/json/deletePolicy` |
| POST | `/api/v1/policy/json/discoverADPolicies` |
| POST | `/api/v1/policy/json/getEffectivePolicy` |
| POST | `/api/v1/policy/json/getEnrolledAdAccounts` |
| POST | `/api/v1/policy/json/getEnrolledSetDelta` |
| POST | `/api/v1/policy/json/getMachineDetailByTenantId` |
| POST | `/api/v1/policy/json/getMachineDetails` |
| POST | `/api/v1/policy/json/getPolicyDetails` |
| POST | `/api/v1/policy/json/getUniqueGroups` |
| POST | `/api/v1/policy/json/getUsers` |
| POST | `/api/v1/policy/json/listPendingBaselines` |
| POST | `/api/v1/policy/json/listPolicy` |
| POST | `/api/v1/policy/json/policyAction` |
| POST | `/api/v1/policy/json/pollAdGroupPolicy` |
| POST | `/api/v1/policy/json/previewImpact` |
| POST | `/api/v1/policy/json/revokePolicy` |
| POST | `/api/v1/policy/json/revokePolicyAgentless` |
| POST | `/api/v1/policy/json/searchPolicy` |
| POST | `/api/v1/policy/json/simulatePolicy` |
| POST | `/api/v1/policy/json/updateAdGroupPolicy` |
| POST | `/api/v1/policy/json/updatePolicy` |
| POST | `/api/v1/policy/json/updatePolicyCredentialMapping` |
| POST | `/api/v1/policy/listAD` |
| POST | `/api/v1/policy/listADGroups` |
| POST | `/api/v1/policy/listADLogGroup` |
| POST | `/api/v1/policy/listAllEndpointRulewithPermission` |
| POST | `/api/v1/policy/listDestinationIP` |
| POST | `/api/v1/policy/listEndpointRule` |
| POST | `/api/v1/policy/listEndpointUser` |
| POST | `/api/v1/policy/listEndpoints` |
| POST | `/api/v1/policy/listLinuxCommands` |
| POST | `/api/v1/policy/listManualEndpointRule` |
| POST | `/api/v1/policy/listOU` |
| POST | `/api/v1/policy/listSourceIP` |
| POST | `/api/v1/policy/listViewADGroupJobs` |
| POST | `/api/v1/policy/listViewPermission` |
| POST | `/api/v1/policy/logAccessRequest` |
| POST | `/api/v1/policy/policy` |
| POST | `/api/v1/policy/searchPolicy` |
| POST | `/api/v1/policy/storeSudoers` |
| POST | `/api/v1/policy/updateEndpointRule` |
| POST | `/api/v1/policy/updateManualEndpointRule` |
| POST | `/api/v1/policy/updatePolicy` |
| POST | `/api/v1/policy/updateUserAccessRequest` |

## dashboard (dashboardService alias)  (9)

| Method | Path |
|---|---|
| POST | `/api/v1/dashboardService/listActivePolicy` |
| POST | `/api/v1/dashboardService/listApprovedAuthRequest` |
| POST | `/api/v1/dashboardService/listAuthRequest` |
| POST | `/api/v1/dashboardService/listCredentialCount` |
| POST | `/api/v1/dashboardService/listEndPointCount` |
| POST | `/api/v1/dashboardService/listEndPointUserCount` |
| POST | `/api/v1/dashboardService/listRejectedAuthRequest` |
| POST | `/api/v1/dashboardService/listTenantCount` |
| POST | `/api/v1/dashboardService/listUserCount` |

## dashboard  (9)

| Method | Path |
|---|---|
| POST | `/api/v1/dashboard/listActivePolicy` |
| POST | `/api/v1/dashboard/listApprovedAuthRequest` |
| POST | `/api/v1/dashboard/listAuthRequest` |
| POST | `/api/v1/dashboard/listCredentialCount` |
| POST | `/api/v1/dashboard/listEndPointCount` |
| POST | `/api/v1/dashboard/listEndPointUserCount` |
| POST | `/api/v1/dashboard/listRejectedAuthRequest` |
| POST | `/api/v1/dashboard/listTenantCount` |
| POST | `/api/v1/dashboard/listUserCount` |

## database (databaseService alias)  (26)

| Method | Path |
|---|---|
| POST | `/api/v1/databaseService/createDbHost` |
| POST | `/api/v1/databaseService/dbSync` |
| POST | `/api/v1/databaseService/dbTable` |
| POST | `/api/v1/databaseService/dbUser` |
| POST | `/api/v1/databaseService/deleteAgentHost` |
| POST | `/api/v1/databaseService/deleteDatabaseHost` |
| POST | `/api/v1/databaseService/getDatabaseAgentHost` |
| POST | `/api/v1/databaseService/getJobQueue` |
| POST | `/api/v1/databaseService/getRoles` |
| POST | `/api/v1/databaseService/getTableFields` |
| POST | `/api/v1/databaseService/getTableNames` |
| POST | `/api/v1/databaseService/getTenantNames` |
| POST | `/api/v1/databaseService/getUniqueDatabasenames` |
| POST | `/api/v1/databaseService/getUniqueUsernames` |
| GET | `/api/v1/databaseService/health` |
| POST | `/api/v1/databaseService/listConnections` |
| POST | `/api/v1/databaseService/listDatabase` |
| POST | `/api/v1/databaseService/listDatabaseEndpoints` |
| POST | `/api/v1/databaseService/listDbHosts` |
| POST | `/api/v1/databaseService/listTables` |
| POST | `/api/v1/databaseService/listUniqueHosts` |
| POST | `/api/v1/databaseService/listUser` |
| POST | `/api/v1/databaseService/listUserPrivilege` |
| POST | `/api/v1/databaseService/registerDbAgent` |
| POST | `/api/v1/databaseService/updateLastActive` |
| POST | `/api/v1/databaseService/updateQueue` |

## database  (26)

| Method | Path |
|---|---|
| POST | `/api/v1/database/createDbHost` |
| POST | `/api/v1/database/dbSync` |
| POST | `/api/v1/database/dbTable` |
| POST | `/api/v1/database/dbUser` |
| POST | `/api/v1/database/deleteAgentHost` |
| POST | `/api/v1/database/deleteDatabaseHost` |
| POST | `/api/v1/database/getDatabaseAgentHost` |
| POST | `/api/v1/database/getJobQueue` |
| POST | `/api/v1/database/getRoles` |
| POST | `/api/v1/database/getTableFields` |
| POST | `/api/v1/database/getTableNames` |
| POST | `/api/v1/database/getTenantNames` |
| POST | `/api/v1/database/getUniqueDatabasenames` |
| POST | `/api/v1/database/getUniqueUsernames` |
| GET | `/api/v1/database/health` |
| POST | `/api/v1/database/listConnections` |
| POST | `/api/v1/database/listDatabase` |
| POST | `/api/v1/database/listDatabaseEndpoints` |
| POST | `/api/v1/database/listDbHosts` |
| POST | `/api/v1/database/listTables` |
| POST | `/api/v1/database/listUniqueHosts` |
| POST | `/api/v1/database/listUser` |
| POST | `/api/v1/database/listUserPrivilege` |
| POST | `/api/v1/database/registerDbAgent` |
| POST | `/api/v1/database/updateLastActive` |
| POST | `/api/v1/database/updateQueue` |

## serviceaccounts  (11)

| Method | Path |
|---|---|
| GET | `/api/v1/serviceAccounts/` |
| POST | `/api/v1/serviceAccounts/` |
| GET | `/api/v1/serviceAccounts/:id` |
| POST | `/api/v1/serviceAccounts/assignEndpoints` |
| POST | `/api/v1/serviceAccounts/getAll` |
| POST | `/api/v1/serviceAccounts/group/addEndpointGroup` |
| GET | `/api/v1/serviceAccounts/group/getEndpointGroup/:id` |
| GET | `/api/v1/serviceAccounts/group/getEndpointGroups` |
| GET | `/api/v1/serviceAccounts/health` |
| POST | `/api/v1/serviceAccounts/listAssignedEndpoints` |
| PUT | `/api/v1/serviceAccounts/updateServiceAccount` |

## serviceaccounts (UI alias)  (11)

| Method | Path |
|---|---|
| GET | `/api/v1/service-accounts/serviceAccounts/` |
| POST | `/api/v1/service-accounts/serviceAccounts/` |
| GET | `/api/v1/service-accounts/serviceAccounts/:id` |
| POST | `/api/v1/service-accounts/serviceAccounts/assignEndpoints` |
| POST | `/api/v1/service-accounts/serviceAccounts/getAll` |
| POST | `/api/v1/service-accounts/serviceAccounts/group/addEndpointGroup` |
| GET | `/api/v1/service-accounts/serviceAccounts/group/getEndpointGroup/:id` |
| GET | `/api/v1/service-accounts/serviceAccounts/group/getEndpointGroups` |
| GET | `/api/v1/service-accounts/serviceAccounts/health` |
| POST | `/api/v1/service-accounts/serviceAccounts/listAssignedEndpoints` |
| PUT | `/api/v1/service-accounts/serviceAccounts/updateServiceAccount` |

## tenant (double-prefix alias)  (70)

| Method | Path |
|---|---|
| POST | `/api/v1/tenants/tenants/SetDefaultJumpserver` |
| POST | `/api/v1/tenants/tenants/approveClient` |
| POST | `/api/v1/tenants/tenants/checkSsoMfa` |
| POST | `/api/v1/tenants/tenants/checkUserandSendMail` |
| POST | `/api/v1/tenants/tenants/createClient` |
| POST | `/api/v1/tenants/tenants/createtenant` |
| POST | `/api/v1/tenants/tenants/createtenantV1` |
| POST | `/api/v1/tenants/tenants/deletetenant` |
| POST | `/api/v1/tenants/tenants/disable_root` |
| POST | `/api/v1/tenants/tenants/forgotPassword` |
| POST | `/api/v1/tenants/tenants/getAdminMfaCache` |
| POST | `/api/v1/tenants/tenants/getAuthMethod` |
| POST | `/api/v1/tenants/tenants/getAuthenticationPolicy` |
| POST | `/api/v1/tenants/tenants/getConnectionMode` |
| POST | `/api/v1/tenants/tenants/getCredentialMode` |
| POST | `/api/v1/tenants/tenants/getCredentialShareMode` |
| POST | `/api/v1/tenants/tenants/getCredentialStore` |
| POST | `/api/v1/tenants/tenants/getDITStatus` |
| POST | `/api/v1/tenants/tenants/getDefaultIssuer` |
| POST | `/api/v1/tenants/tenants/getEndUserMfaCache` |
| POST | `/api/v1/tenants/tenants/getEntityAuthentication` |
| POST | `/api/v1/tenants/tenants/getIssuerList` |
| POST | `/api/v1/tenants/tenants/getJumpserverList` |
| POST | `/api/v1/tenants/tenants/getLogOutputConfiguration` |
| POST | `/api/v1/tenants/tenants/getMfaDevices` |
| POST | `/api/v1/tenants/tenants/getPlatformMfa` |
| POST | `/api/v1/tenants/tenants/getSSOConfiguration` |
| POST | `/api/v1/tenants/tenants/getSsoMfa` |
| POST | `/api/v1/tenants/tenants/getSsoMfaEndUser` |
| POST | `/api/v1/tenants/tenants/getTenantAuthFactor` |
| POST | `/api/v1/tenants/tenants/getTenantDetail` |
| POST | `/api/v1/tenants/tenants/getTenantLogo` |
| POST | `/api/v1/tenants/tenants/getTenantStatus` |
| POST | `/api/v1/tenants/tenants/getUserDetailFromAuthService` |
| POST | `/api/v1/tenants/tenants/getauthfactors` |
| POST | `/api/v1/tenants/tenants/listClient` |
| POST | `/api/v1/tenants/tenants/mfaconfig/add` |
| POST | `/api/v1/tenants/tenants/mfaconfig/delete` |
| POST | `/api/v1/tenants/tenants/mfaconfig/get` |
| GET | `/api/v1/tenants/tenants/openAuthLoginWindow` |
| POST | `/api/v1/tenants/tenants/resetPassword` |
| POST | `/api/v1/tenants/tenants/samlOnboardUser` |
| POST | `/api/v1/tenants/tenants/setAdminMfaCache` |
| POST | `/api/v1/tenants/tenants/setAuthenticationPolicy` |
| POST | `/api/v1/tenants/tenants/setConnectionMode` |
| POST | `/api/v1/tenants/tenants/setCredentialMode` |
| POST | `/api/v1/tenants/tenants/setCredentialShareMode` |
| POST | `/api/v1/tenants/tenants/setCredentialStore` |
| POST | `/api/v1/tenants/tenants/setDITStatus` |
| POST | `/api/v1/tenants/tenants/setDefaultIssuer` |
| POST | `/api/v1/tenants/tenants/setDefaultIssuerForTenant` |
| POST | `/api/v1/tenants/tenants/setDefaultJumpserver` |
| POST | `/api/v1/tenants/tenants/setEndUserMfaCache` |
| POST | `/api/v1/tenants/tenants/setEntityAuthentication` |
| POST | `/api/v1/tenants/tenants/setMfaDevices` |
| POST | `/api/v1/tenants/tenants/setPlatformMfa` |
| POST | `/api/v1/tenants/tenants/setSSOConfiguration` |
| POST | `/api/v1/tenants/tenants/setSsoMfa` |
| POST | `/api/v1/tenants/tenants/setSsoMfaEndUser` |
| POST | `/api/v1/tenants/tenants/setTenantLogo` |
| POST | `/api/v1/tenants/tenants/setTenantS3` |
| POST | `/api/v1/tenants/tenants/setTenantSetup` |
| POST | `/api/v1/tenants/tenants/setTenantTimeZone` |
| POST | `/api/v1/tenants/tenants/setauthfactors` |
| POST | `/api/v1/tenants/tenants/storeLogOutputConfiguration` |
| POST | `/api/v1/tenants/tenants/tenantlist` |
| POST | `/api/v1/tenants/tenants/tenantlogin` |
| POST | `/api/v1/tenants/tenants/tenantsignup` |
| POST | `/api/v1/tenants/tenants/tenanttokenverify` |
| POST | `/api/v1/tenants/tenants/updateLogOutputConfiguration` |

## tenant + org (SSC alias)  (81)

| Method | Path |
|---|---|
| POST | `/api/v1/tenants/SetDefaultJumpserver` |
| POST | `/api/v1/tenants/approveClient` |
| POST | `/api/v1/tenants/approveorg` |
| POST | `/api/v1/tenants/authenticatemethod` |
| POST | `/api/v1/tenants/checkSsoMfa` |
| POST | `/api/v1/tenants/checkUserandSendMail` |
| POST | `/api/v1/tenants/createClient` |
| POST | `/api/v1/tenants/createtenant` |
| POST | `/api/v1/tenants/createtenantV1` |
| POST | `/api/v1/tenants/deletetenant` |
| POST | `/api/v1/tenants/disable_root` |
| POST | `/api/v1/tenants/forgotPassword` |
| POST | `/api/v1/tenants/getAdminMfaCache` |
| POST | `/api/v1/tenants/getAuthMethod` |
| POST | `/api/v1/tenants/getAuthenticationPolicy` |
| POST | `/api/v1/tenants/getConnectionMode` |
| POST | `/api/v1/tenants/getCountofEpmUserByEndpoint` |
| POST | `/api/v1/tenants/getCountofEpmUserGroupByEndpoint` |
| POST | `/api/v1/tenants/getCredentialMode` |
| POST | `/api/v1/tenants/getCredentialShareMode` |
| POST | `/api/v1/tenants/getCredentialStore` |
| POST | `/api/v1/tenants/getDITStatus` |
| POST | `/api/v1/tenants/getDefaultIssuer` |
| POST | `/api/v1/tenants/getEndUserMfaCache` |
| POST | `/api/v1/tenants/getEntityAuthentication` |
| POST | `/api/v1/tenants/getIssuerList` |
| POST | `/api/v1/tenants/getJumpserverList` |
| POST | `/api/v1/tenants/getLogOutputConfiguration` |
| POST | `/api/v1/tenants/getMfaDevices` |
| POST | `/api/v1/tenants/getOsList` |
| POST | `/api/v1/tenants/getPlatformMfa` |
| POST | `/api/v1/tenants/getSSOConfiguration` |
| POST | `/api/v1/tenants/getSsoMfa` |
| POST | `/api/v1/tenants/getSsoMfaEndUser` |
| POST | `/api/v1/tenants/getTenantAuthFactor` |
| POST | `/api/v1/tenants/getTenantDetail` |
| POST | `/api/v1/tenants/getTenantLogo` |
| POST | `/api/v1/tenants/getTenantStatus` |
| POST | `/api/v1/tenants/getUserDetailFromAuthService` |
| POST | `/api/v1/tenants/getauthfactors` |
| POST | `/api/v1/tenants/listClient` |
| POST | `/api/v1/tenants/mfaconfig/add` |
| POST | `/api/v1/tenants/mfaconfig/delete` |
| POST | `/api/v1/tenants/mfaconfig/get` |
| GET | `/api/v1/tenants/openAuthLoginWindow` |
| POST | `/api/v1/tenants/orgdetail` |
| POST | `/api/v1/tenants/orglist` |
| POST | `/api/v1/tenants/orglogin` |
| POST | `/api/v1/tenants/orgsignup` |
| GET | `/api/v1/tenants/orgsignupverify` |
| POST | `/api/v1/tenants/resetPassword` |
| POST | `/api/v1/tenants/samlOnboardUser` |
| POST | `/api/v1/tenants/setAdminMfaCache` |
| POST | `/api/v1/tenants/setAuthenticationPolicy` |
| POST | `/api/v1/tenants/setConnectionMode` |
| POST | `/api/v1/tenants/setCredentialMode` |
| POST | `/api/v1/tenants/setCredentialShareMode` |
| POST | `/api/v1/tenants/setCredentialStore` |
| POST | `/api/v1/tenants/setDITStatus` |
| POST | `/api/v1/tenants/setDefaultIssuer` |
| POST | `/api/v1/tenants/setDefaultIssuerForTenant` |
| POST | `/api/v1/tenants/setDefaultJumpserver` |
| POST | `/api/v1/tenants/setEndUserMfaCache` |
| POST | `/api/v1/tenants/setEntityAuthentication` |
| POST | `/api/v1/tenants/setMfaDevices` |
| POST | `/api/v1/tenants/setPlatformMfa` |
| POST | `/api/v1/tenants/setSSOConfiguration` |
| POST | `/api/v1/tenants/setSsoMfa` |
| POST | `/api/v1/tenants/setSsoMfaEndUser` |
| POST | `/api/v1/tenants/setTenantLogo` |
| POST | `/api/v1/tenants/setTenantS3` |
| POST | `/api/v1/tenants/setTenantSetup` |
| POST | `/api/v1/tenants/setTenantTimeZone` |
| POST | `/api/v1/tenants/setauthfactors` |
| POST | `/api/v1/tenants/storeLogOutputConfiguration` |
| POST | `/api/v1/tenants/tenantlist` |
| POST | `/api/v1/tenants/tenantlogin` |
| POST | `/api/v1/tenants/tenantsignup` |
| POST | `/api/v1/tenants/tenanttokenverify` |
| POST | `/api/v1/tenants/updateLogOutputConfiguration` |
| POST | `/api/v1/tenants/validateemailandorgname` |

## tenant  (70)

| Method | Path |
|---|---|
| POST | `/api/v1/tenant/SetDefaultJumpserver` |
| POST | `/api/v1/tenant/approveClient` |
| POST | `/api/v1/tenant/checkSsoMfa` |
| POST | `/api/v1/tenant/checkUserandSendMail` |
| POST | `/api/v1/tenant/createClient` |
| POST | `/api/v1/tenant/createtenant` |
| POST | `/api/v1/tenant/createtenantV1` |
| POST | `/api/v1/tenant/deletetenant` |
| POST | `/api/v1/tenant/disable_root` |
| POST | `/api/v1/tenant/forgotPassword` |
| POST | `/api/v1/tenant/getAdminMfaCache` |
| POST | `/api/v1/tenant/getAuthMethod` |
| POST | `/api/v1/tenant/getAuthenticationPolicy` |
| POST | `/api/v1/tenant/getConnectionMode` |
| POST | `/api/v1/tenant/getCredentialMode` |
| POST | `/api/v1/tenant/getCredentialShareMode` |
| POST | `/api/v1/tenant/getCredentialStore` |
| POST | `/api/v1/tenant/getDITStatus` |
| POST | `/api/v1/tenant/getDefaultIssuer` |
| POST | `/api/v1/tenant/getEndUserMfaCache` |
| POST | `/api/v1/tenant/getEntityAuthentication` |
| POST | `/api/v1/tenant/getIssuerList` |
| POST | `/api/v1/tenant/getJumpserverList` |
| POST | `/api/v1/tenant/getLogOutputConfiguration` |
| POST | `/api/v1/tenant/getMfaDevices` |
| POST | `/api/v1/tenant/getPlatformMfa` |
| POST | `/api/v1/tenant/getSSOConfiguration` |
| POST | `/api/v1/tenant/getSsoMfa` |
| POST | `/api/v1/tenant/getSsoMfaEndUser` |
| POST | `/api/v1/tenant/getTenantAuthFactor` |
| POST | `/api/v1/tenant/getTenantDetail` |
| POST | `/api/v1/tenant/getTenantLogo` |
| POST | `/api/v1/tenant/getTenantStatus` |
| POST | `/api/v1/tenant/getUserDetailFromAuthService` |
| POST | `/api/v1/tenant/getauthfactors` |
| POST | `/api/v1/tenant/listClient` |
| POST | `/api/v1/tenant/mfaconfig/add` |
| POST | `/api/v1/tenant/mfaconfig/delete` |
| POST | `/api/v1/tenant/mfaconfig/get` |
| GET | `/api/v1/tenant/openAuthLoginWindow` |
| POST | `/api/v1/tenant/resetPassword` |
| POST | `/api/v1/tenant/samlOnboardUser` |
| POST | `/api/v1/tenant/setAdminMfaCache` |
| POST | `/api/v1/tenant/setAuthenticationPolicy` |
| POST | `/api/v1/tenant/setConnectionMode` |
| POST | `/api/v1/tenant/setCredentialMode` |
| POST | `/api/v1/tenant/setCredentialShareMode` |
| POST | `/api/v1/tenant/setCredentialStore` |
| POST | `/api/v1/tenant/setDITStatus` |
| POST | `/api/v1/tenant/setDefaultIssuer` |
| POST | `/api/v1/tenant/setDefaultIssuerForTenant` |
| POST | `/api/v1/tenant/setDefaultJumpserver` |
| POST | `/api/v1/tenant/setEndUserMfaCache` |
| POST | `/api/v1/tenant/setEntityAuthentication` |
| POST | `/api/v1/tenant/setMfaDevices` |
| POST | `/api/v1/tenant/setPlatformMfa` |
| POST | `/api/v1/tenant/setSSOConfiguration` |
| POST | `/api/v1/tenant/setSsoMfa` |
| POST | `/api/v1/tenant/setSsoMfaEndUser` |
| POST | `/api/v1/tenant/setTenantLogo` |
| POST | `/api/v1/tenant/setTenantS3` |
| POST | `/api/v1/tenant/setTenantSetup` |
| POST | `/api/v1/tenant/setTenantTimeZone` |
| POST | `/api/v1/tenant/setauthfactors` |
| POST | `/api/v1/tenant/storeLogOutputConfiguration` |
| POST | `/api/v1/tenant/tenantlist` |
| POST | `/api/v1/tenant/tenantlogin` |
| POST | `/api/v1/tenant/tenantsignup` |
| POST | `/api/v1/tenant/tenanttokenverify` |
| POST | `/api/v1/tenant/updateLogOutputConfiguration` |

## issuer  (46)

| Method | Path |
|---|---|
| POST | `/api/v1/issuer/credential/assignEPMUser` |
| POST | `/api/v1/issuer/credential/assignVC` |
| POST | `/api/v1/issuer/credential/createADGroupCredential` |
| POST | `/api/v1/issuer/credential/createADUserCredential` |
| POST | `/api/v1/issuer/credential/createADUserCredentialV2` |
| POST | `/api/v1/issuer/credential/createCredential` |
| POST | `/api/v1/issuer/credential/createDatabaseCredential` |
| POST | `/api/v1/issuer/credential/createEpmUser` |
| POST | `/api/v1/issuer/credential/createEpmUserCredential` |
| POST | `/api/v1/issuer/credential/createPasswordCredential` |
| POST | `/api/v1/issuer/credential/createPlatformCredential` |
| POST | `/api/v1/issuer/credential/createPolicyADUserCredential` |
| POST | `/api/v1/issuer/credential/createRadiusCredential` |
| POST | `/api/v1/issuer/credential/createRdpCredential` |
| POST | `/api/v1/issuer/credential/createSecretCredential` |
| POST | `/api/v1/issuer/credential/createServiceAccountCredential` |
| POST | `/api/v1/issuer/credential/createSharedAdUserCredential` |
| POST | `/api/v1/issuer/credential/createSshCredential` |
| POST | `/api/v1/issuer/credential/createVncCredential` |
| POST | `/api/v1/issuer/credential/credentialList` |
| POST | `/api/v1/issuer/credential/credentialListByUser` |
| POST | `/api/v1/issuer/credential/credentialSchemaList` |
| POST | `/api/v1/issuer/credential/endpointGroups/sshCredential` |
| POST | `/api/v1/issuer/credential/getAcceptedCredential` |
| POST | `/api/v1/issuer/credential/getAssignedCredential` |
| POST | `/api/v1/issuer/credential/getCredential` |
| POST | `/api/v1/issuer/credential/getCredentialByEpmUser` |
| POST | `/api/v1/issuer/credential/getCredentialCountByEpmUser` |
| POST | `/api/v1/issuer/credential/getIgnoredCredential` |
| POST | `/api/v1/issuer/credential/resetWallet` |
| POST | `/api/v1/issuer/credential/revokecredential` |
| POST | `/api/v1/issuer/credential/serviceAccount/acceptCredential` |
| POST | `/api/v1/issuer/did/DIDList` |
| POST | `/api/v1/issuer/did/createHolderDid` |
| POST | `/api/v1/issuer/did/createIssuerDid` |
| DELETE | `/api/v1/issuer/did/deleteDid` |
| POST | `/api/v1/issuer/did/didList` |
| POST | `/api/v1/issuer/did/issuerList` |
| POST | `/api/v1/issuer/did/searchDID` |
| POST | `/api/v1/issuer/did/userList` |
| POST | `/api/v1/issuer/getLastActiveOfEndpointMachine` |
| POST | `/api/v1/issuer/revokeAllCredentials` |
| POST | `/api/v1/issuer/rotateCredential` |
| POST | `/api/v1/issuer/schema/createSchema` |
| PUT | `/api/v1/issuer/seedSchemas` |
| PUT | `/api/v1/issuer/seedUserDID` |

## issuer (short-path alias)  (12)

| Method | Path |
|---|---|
| POST | `/api/v1/credential/GetAcceptedCredential` |
| POST | `/api/v1/credential/GetAssignedCredential` |
| POST | `/api/v1/credential/GetIgnoredCredential` |
| POST | `/api/v1/credential/credentialList` |
| POST | `/api/v1/did/DIDList` |
| POST | `/api/v1/did/createHolderDid` |
| POST | `/api/v1/did/createIssuerDid` |
| DELETE | `/api/v1/did/deleteDid` |
| POST | `/api/v1/did/didList` |
| POST | `/api/v1/did/issuerList` |
| POST | `/api/v1/did/searchDID` |
| POST | `/api/v1/did/userList` |

## wallet  (28)

| Method | Path |
|---|---|
| POST | `/api/v1/wallet/acknowledgeCredential` |
| PUT | `/api/v1/wallet/acknowledgePresentationRequest` |
| POST | `/api/v1/wallet/allowedVsDeniedCredential` |
| POST | `/api/v1/wallet/assignWalletUser` |
| POST | `/api/v1/wallet/countNewCredentialShared` |
| POST | `/api/v1/wallet/countTransactionCredential` |
| POST | `/api/v1/wallet/createWallet` |
| POST | `/api/v1/wallet/getAssignedWalletUserByEpmUser` |
| POST | `/api/v1/wallet/getWalletStatus` |
| POST | `/api/v1/wallet/getWalletUserDetails` |
| POST | `/api/v1/wallet/invalidateWallet` |
| POST | `/api/v1/wallet/listCredentials` |
| POST | `/api/v1/wallet/listCredentialsforUser` |
| POST | `/api/v1/wallet/listOrganizations` |
| POST | `/api/v1/wallet/listTenants` |
| POST | `/api/v1/wallet/pollCredentials` |
| POST | `/api/v1/wallet/pollPresentationRequest` |
| POST | `/api/v1/wallet/registerDevice` |
| POST | `/api/v1/wallet/resetWalletByOrg` |
| POST | `/api/v1/wallet/resetWalletByTenant` |
| POST | `/api/v1/wallet/resetWalletByUser` |
| POST | `/api/v1/wallet/restoreWallet` |
| GET | `/api/v1/wallet/status` |
| POST | `/api/v1/wallet/submitCustomPresentationResponse` |
| POST | `/api/v1/wallet/submitPresentation` |
| POST | `/api/v1/wallet/submitPresentationResponse` |
| POST | `/api/v1/wallet/updatePushToken` |
| POST | `/api/v1/wallet/walletUserList` |

## verifier  (10)

| Method | Path |
|---|---|
| GET | `/api/v1/verifier/health` |
| POST | `/api/v1/verifier/issuePR` |
| POST | `/api/v1/verifier/issuePRV4` |
| POST | `/api/v1/verifier/issuePRV5` |
| POST | `/api/v1/verifier/resolveDid` |
| GET | `/api/v1/verifier/status` |
| POST | `/api/v1/verifier/verifyPresentationSubmission` |
| POST | `/api/v1/verifier/verifyPresentationSubmissionV4` |
| POST | `/api/v1/verifier/verifyPresentationSubmissionV5` |
| POST | `/api/v1/verifier/verifyServiceAccount` |

## user  (94)

| Method | Path |
|---|---|
| POST | `/api/v1/user/GetJumpserverList` |
| POST | `/api/v1/user/SetDefaultJumpserver` |
| POST | `/api/v1/user/addEndpointGroups` |
| POST | `/api/v1/user/approveClient` |
| POST | `/api/v1/user/approveorg` |
| POST | `/api/v1/user/authenticatemethod` |
| POST | `/api/v1/user/checkSsoMfa` |
| POST | `/api/v1/user/checkUserandSendMail` |
| POST | `/api/v1/user/createClient` |
| POST | `/api/v1/user/createtenant` |
| POST | `/api/v1/user/createtenantV1` |
| POST | `/api/v1/user/dashboardnoofendpoints` |
| POST | `/api/v1/user/dashboardnooftenant` |
| POST | `/api/v1/user/dashboardnoofuser` |
| POST | `/api/v1/user/deletetenant` |
| POST | `/api/v1/user/endpoint/updateDesc` |
| POST | `/api/v1/user/endpoint/updateFqdn` |
| POST | `/api/v1/user/endpoint/updatePrivateIp` |
| POST | `/api/v1/user/endpoint/updatePublicIp` |
| POST | `/api/v1/user/endpointlist` |
| POST | `/api/v1/user/forgotPassword` |
| POST | `/api/v1/user/getAdminMfaCache` |
| POST | `/api/v1/user/getAuthMethod` |
| POST | `/api/v1/user/getAuthenticationPolicy` |
| POST | `/api/v1/user/getConnectionMode` |
| POST | `/api/v1/user/getCountofEpmUserByEndpoint` |
| POST | `/api/v1/user/getCountofEpmUserGroupByEndpoint` |
| POST | `/api/v1/user/getCredentialMode` |
| POST | `/api/v1/user/getCredentialShareMode` |
| POST | `/api/v1/user/getCredentialStore` |
| POST | `/api/v1/user/getDITStatus` |
| POST | `/api/v1/user/getDefaultIssuer` |
| POST | `/api/v1/user/getEndUserMfaCache` |
| POST | `/api/v1/user/getEndpointandUserDetail` |
| POST | `/api/v1/user/getEntityAuthentication` |
| POST | `/api/v1/user/getIssuerList` |
| POST | `/api/v1/user/getLogOutputConfiguration` |
| POST | `/api/v1/user/getMfaDevices` |
| POST | `/api/v1/user/getOsList` |
| POST | `/api/v1/user/getPlatformMfa` |
| POST | `/api/v1/user/getSSOConfiguration` |
| POST | `/api/v1/user/getSsoMfa` |
| POST | `/api/v1/user/getSsoMfaEndUser` |
| POST | `/api/v1/user/getTenantAuthFactor` |
| POST | `/api/v1/user/getTenantDetail` |
| POST | `/api/v1/user/getTenantLogo` |
| POST | `/api/v1/user/getTenantStatus` |
| POST | `/api/v1/user/getUserDetailFromAuthService` |
| POST | `/api/v1/user/getWalletUserDetail` |
| POST | `/api/v1/user/isIPExists` |
| POST | `/api/v1/user/listClient` |
| POST | `/api/v1/user/listEntity` |
| GET | `/api/v1/user/openAuthLoginWindow` |
| POST | `/api/v1/user/orgdetail` |
| POST | `/api/v1/user/orglist` |
| POST | `/api/v1/user/orglogin` |
| POST | `/api/v1/user/orgsignup` |
| GET | `/api/v1/user/orgsignupverify` |
| POST | `/api/v1/user/resetPassword` |
| POST | `/api/v1/user/samlOnboardUser` |
| POST | `/api/v1/user/setAdminMfaCache` |
| POST | `/api/v1/user/setAuthenticationPolicy` |
| POST | `/api/v1/user/setConnectionMode` |
| POST | `/api/v1/user/setCredentialMode` |
| POST | `/api/v1/user/setCredentialShareMode` |
| POST | `/api/v1/user/setCredentialStore` |
| POST | `/api/v1/user/setDITStatus` |
| POST | `/api/v1/user/setDefaultIssuer` |
| POST | `/api/v1/user/setDefaultIssuerForTenant` |
| POST | `/api/v1/user/setEndUserMfaCache` |
| POST | `/api/v1/user/setEntityAuthentication` |
| POST | `/api/v1/user/setMfaDevices` |
| POST | `/api/v1/user/setPlatformMfa` |
| POST | `/api/v1/user/setSSOConfiguration` |
| POST | `/api/v1/user/setSsoMfa` |
| POST | `/api/v1/user/setSsoMfaEndUser` |
| POST | `/api/v1/user/setTenantLogo` |
| POST | `/api/v1/user/setTenantS3` |
| POST | `/api/v1/user/setTenantSetup` |
| POST | `/api/v1/user/setTenantTimeZone` |
| POST | `/api/v1/user/storeLogOutputConfiguration` |
| POST | `/api/v1/user/tenantlist` |
| POST | `/api/v1/user/tenantlogin` |
| POST | `/api/v1/user/tenants/disable_root` |
| POST | `/api/v1/user/tenants/getauthfactors` |
| POST | `/api/v1/user/tenants/mfaconfig/add` |
| POST | `/api/v1/user/tenants/mfaconfig/delete` |
| POST | `/api/v1/user/tenants/mfaconfig/get` |
| POST | `/api/v1/user/tenants/setauthfactors` |
| POST | `/api/v1/user/tenantsignup` |
| POST | `/api/v1/user/tenanttokenverify` |
| POST | `/api/v1/user/updateLogOutputConfiguration` |
| POST | `/api/v1/user/userlist` |
| POST | `/api/v1/user/validateemailandorgname` |

## org  (8)

| Method | Path |
|---|---|
| POST | `/api/v1/org/approveorg` |
| POST | `/api/v1/org/authenticatemethod` |
| POST | `/api/v1/org/orgdetail` |
| POST | `/api/v1/org/orglist` |
| POST | `/api/v1/org/orglogin` |
| POST | `/api/v1/org/orgsignup` |
| GET | `/api/v1/org/orgsignupverify` |
| POST | `/api/v1/org/validateemailandorgname` |

## endpoint  (9)

| Method | Path |
|---|---|
| GET | `/api/v1/endpoint/agent/logs` |
| POST | `/api/v1/endpoint/agent/start` |
| GET | `/api/v1/endpoint/agent/status` |
| POST | `/api/v1/endpoint/agent/stop` |
| GET | `/api/v1/endpoint/healthz` |
| POST | `/api/v1/endpoint/user/add_to_sudo` |
| POST | `/api/v1/endpoint/user/create` |
| POST | `/api/v1/endpoint/user/delete` |
| POST | `/api/v1/endpoint/user/remove_from_sudo` |

## entra  (2)

| Method | Path |
|---|---|
| GET | `/api/v1/entra/health` |
| POST | `/api/v1/entra/syncEntraUsers` |

## ad  (100)

| Method | Path |
|---|---|
| POST | `/api/v1/ad/AddDomain` |
| POST | `/api/v1/ad/AddGateway` |
| POST | `/api/v1/ad/AddGroup` |
| POST | `/api/v1/ad/AddOUs` |
| POST | `/api/v1/ad/AddUser` |
| POST | `/api/v1/ad/AssignGatewayDomain` |
| POST | `/api/v1/ad/BlockPrincipal` |
| POST | `/api/v1/ad/CheckPasswordResetPolicy` |
| POST | `/api/v1/ad/DeleteDomain` |
| POST | `/api/v1/ad/DeleteGateway` |
| POST | `/api/v1/ad/DeleteMFAProvider` |
| GET | `/api/v1/ad/DownloadAgentBundle` |
| GET | `/api/v1/ad/DownloadAgentConfig` |
| GET | `/api/v1/ad/DownloadSensorConfig` |
| POST | `/api/v1/ad/GetADGroupJobs` |
| POST | `/api/v1/ad/GetAllAdUsers` |
| POST | `/api/v1/ad/GetAllDomains` |
| POST | `/api/v1/ad/GetAllGroupsByDomain` |
| POST | `/api/v1/ad/GetAllUsersByGroup` |
| POST | `/api/v1/ad/GetAuthBadSources` |
| POST | `/api/v1/ad/GetAuthLog` |
| POST | `/api/v1/ad/GetBlockedPrincipals` |
| GET | `/api/v1/ad/GetEnrollmentDetails` |
| POST | `/api/v1/ad/GetEnrollmentStatus` |
| POST | `/api/v1/ad/GetGatewayConfig` |
| POST | `/api/v1/ad/GetGatewaysByOrg` |
| POST | `/api/v1/ad/GetMFAChallenge` |
| POST | `/api/v1/ad/GetMFAProvider` |
| POST | `/api/v1/ad/GetOUs` |
| POST | `/api/v1/ad/GetServiceAccountUserByDomain` |
| POST | `/api/v1/ad/GetShadowGroups` |
| POST | `/api/v1/ad/GetUnenrolledUsersInGroup` |
| POST | `/api/v1/ad/GetUserAuthLog` |
| POST | `/api/v1/ad/IngestAuthEvents` |
| POST | `/api/v1/ad/InitiateMFAChallenge` |
| POST | `/api/v1/ad/ListAdGroups` |
| POST | `/api/v1/ad/RegisterDevice` |
| POST | `/api/v1/ad/RegisterGateway` |
| POST | `/api/v1/ad/RespondMFAChallenge` |
| POST | `/api/v1/ad/RotateCredentials` |
| POST | `/api/v1/ad/SendEnrollmentEmail` |
| POST | `/api/v1/ad/SetMFAProvider` |
| POST | `/api/v1/ad/UnassignGatewayDomain` |
| POST | `/api/v1/ad/UnblockPrincipal` |
| POST | `/api/v1/ad/UpdateADGroupJobs` |
| POST | `/api/v1/ad/UpdateDomainStatus` |
| POST | `/api/v1/ad/UpdateGatewayMode` |
| POST | `/api/v1/ad/UpdateMfaFlagADUsers` |
| POST | `/api/v1/ad/UserSync` |
| POST | `/api/v1/ad/addDomain` |
| POST | `/api/v1/ad/addGateway` |
| POST | `/api/v1/ad/addGroup` |
| POST | `/api/v1/ad/addOUs` |
| POST | `/api/v1/ad/addUser` |
| POST | `/api/v1/ad/assignGatewayDomain` |
| POST | `/api/v1/ad/blockPrincipal` |
| POST | `/api/v1/ad/checkPasswordResetPolicy` |
| POST | `/api/v1/ad/deleteDomain` |
| POST | `/api/v1/ad/deleteGateway` |
| POST | `/api/v1/ad/deleteMFAProvider` |
| GET | `/api/v1/ad/domain/status/stream` |
| GET | `/api/v1/ad/downloadAgentBundle` |
| GET | `/api/v1/ad/downloadAgentConfig` |
| GET | `/api/v1/ad/downloadSensorConfig` |
| POST | `/api/v1/ad/getADGroupJobs` |
| POST | `/api/v1/ad/getAllAdUsers` |
| POST | `/api/v1/ad/getAllDomains` |
| POST | `/api/v1/ad/getAllGroupsByDomain` |
| POST | `/api/v1/ad/getAllUsersByGroup` |
| POST | `/api/v1/ad/getAuthBadSources` |
| POST | `/api/v1/ad/getAuthLog` |
| POST | `/api/v1/ad/getBlockedPrincipals` |
| GET | `/api/v1/ad/getEnrollmentDetails` |
| POST | `/api/v1/ad/getEnrollmentStatus` |
| POST | `/api/v1/ad/getGatewayConfig` |
| POST | `/api/v1/ad/getGatewaysByOrg` |
| POST | `/api/v1/ad/getMFAChallenge` |
| POST | `/api/v1/ad/getMFAProvider` |
| POST | `/api/v1/ad/getOUs` |
| POST | `/api/v1/ad/getServiceAccountUserByDomain` |
| POST | `/api/v1/ad/getShadowGroups` |
| POST | `/api/v1/ad/getUnenrolledUsersInGroup` |
| POST | `/api/v1/ad/getUserAuthLog` |
| GET | `/api/v1/ad/health` |
| POST | `/api/v1/ad/ingestAuthEvents` |
| POST | `/api/v1/ad/initiateMFAChallenge` |
| POST | `/api/v1/ad/listAdGroups` |
| POST | `/api/v1/ad/registerDevice` |
| POST | `/api/v1/ad/registerGateway` |
| POST | `/api/v1/ad/respondMFAChallenge` |
| POST | `/api/v1/ad/rotateCredentials` |
| POST | `/api/v1/ad/sendEnrollmentEmail` |
| POST | `/api/v1/ad/setMFAProvider` |
| POST | `/api/v1/ad/unassignGatewayDomain` |
| POST | `/api/v1/ad/unblockPrincipal` |
| POST | `/api/v1/ad/updateADGroupJobs` |
| POST | `/api/v1/ad/updateDomainStatus` |
| POST | `/api/v1/ad/updateGatewayMode` |
| POST | `/api/v1/ad/updateMfaFlagADUsers` |
| POST | `/api/v1/ad/userSync` |

## mfa  (42)

| Method | Path |
|---|---|
| GET | `/api/v1/mfa/.well-known/openid-configuration` |
| POST | `/api/v1/mfa/auth/external-mfa` |
| POST | `/api/v1/mfa/auth/verifyUser` |
| POST | `/api/v1/mfa/backToLogin` |
| POST | `/api/v1/mfa/beginAuthRegistration` |
| POST | `/api/v1/mfa/beginAuthentication` |
| POST | `/api/v1/mfa/beginRegisterWallet` |
| POST | `/api/v1/mfa/beginRegistration` |
| POST | `/api/v1/mfa/deletePasskey` |
| GET | `/api/v1/mfa/emaptasaml/login` |
| POST | `/api/v1/mfa/finishAuthentication` |
| POST | `/api/v1/mfa/finishRegistration` |
| GET | `/api/v1/mfa/oauth2/v1/keys` |
| GET | `/api/v1/mfa/okta/getsession` |
| GET | `/api/v1/mfa/okta/logout` |
| POST | `/api/v1/mfa/okta/normalLogin` |
| POST | `/api/v1/mfa/okta/orgLogin` |
| POST | `/api/v1/mfa/okta/ssomfa` |
| POST | `/api/v1/mfa/passkey/beginAuthentication` |
| POST | `/api/v1/mfa/passkey/beginSetup` |
| POST | `/api/v1/mfa/passkey/confirmSetup` |
| POST | `/api/v1/mfa/passkey/verify` |
| POST | `/api/v1/mfa/provider/config` |
| POST | `/api/v1/mfa/provider/delete` |
| POST | `/api/v1/mfa/provider/get` |
| POST | `/api/v1/mfa/provider/set` |
| POST | `/api/v1/mfa/push/beginSetup` |
| POST | `/api/v1/mfa/push/challenge` |
| POST | `/api/v1/mfa/push/confirmSetup` |
| POST | `/api/v1/mfa/push/respond` |
| POST | `/api/v1/mfa/push/status` |
| POST | `/api/v1/mfa/saml/callback` |
| POST | `/api/v1/mfa/sms/beginSetup` |
| POST | `/api/v1/mfa/sms/confirmSetup` |
| POST | `/api/v1/mfa/sms/requestCode` |
| POST | `/api/v1/mfa/sms/verify` |
| POST | `/api/v1/mfa/status` |
| POST | `/api/v1/mfa/totp/beginSetup` |
| POST | `/api/v1/mfa/totp/confirmSetup` |
| POST | `/api/v1/mfa/totp/delete` |
| POST | `/api/v1/mfa/totp/verify` |
| GET | `/api/v1/mfa/v1/logout` |

## dbconsole  (4)

| Method | Path |
|---|---|
| POST | `/api/v1/dbconsole/init` |
| OPTIONS | `/api/v1/dbconsole/init` |
| GET | `/api/v1/dbconsole/ws` |
| OPTIONS | `/api/v1/dbconsole/ws` |

## secretservice (stub)  (2)

| Method | Path |
|---|---|
| POST | `/api/v1/secretservice/createSecretinVault` |
| POST | `/api/v1/secretservice/getConnectionMode` |

## ad (root alias)  (100)

| Method | Path |
|---|---|
| POST | `/ad/AddDomain` |
| POST | `/ad/AddGateway` |
| POST | `/ad/AddGroup` |
| POST | `/ad/AddOUs` |
| POST | `/ad/AddUser` |
| POST | `/ad/AssignGatewayDomain` |
| POST | `/ad/BlockPrincipal` |
| POST | `/ad/CheckPasswordResetPolicy` |
| POST | `/ad/DeleteDomain` |
| POST | `/ad/DeleteGateway` |
| POST | `/ad/DeleteMFAProvider` |
| GET | `/ad/DownloadAgentBundle` |
| GET | `/ad/DownloadAgentConfig` |
| GET | `/ad/DownloadSensorConfig` |
| POST | `/ad/GetADGroupJobs` |
| POST | `/ad/GetAllAdUsers` |
| POST | `/ad/GetAllDomains` |
| POST | `/ad/GetAllGroupsByDomain` |
| POST | `/ad/GetAllUsersByGroup` |
| POST | `/ad/GetAuthBadSources` |
| POST | `/ad/GetAuthLog` |
| POST | `/ad/GetBlockedPrincipals` |
| GET | `/ad/GetEnrollmentDetails` |
| POST | `/ad/GetEnrollmentStatus` |
| POST | `/ad/GetGatewayConfig` |
| POST | `/ad/GetGatewaysByOrg` |
| POST | `/ad/GetMFAChallenge` |
| POST | `/ad/GetMFAProvider` |
| POST | `/ad/GetOUs` |
| POST | `/ad/GetServiceAccountUserByDomain` |
| POST | `/ad/GetShadowGroups` |
| POST | `/ad/GetUnenrolledUsersInGroup` |
| POST | `/ad/GetUserAuthLog` |
| POST | `/ad/IngestAuthEvents` |
| POST | `/ad/InitiateMFAChallenge` |
| POST | `/ad/ListAdGroups` |
| POST | `/ad/RegisterDevice` |
| POST | `/ad/RegisterGateway` |
| POST | `/ad/RespondMFAChallenge` |
| POST | `/ad/RotateCredentials` |
| POST | `/ad/SendEnrollmentEmail` |
| POST | `/ad/SetMFAProvider` |
| POST | `/ad/UnassignGatewayDomain` |
| POST | `/ad/UnblockPrincipal` |
| POST | `/ad/UpdateADGroupJobs` |
| POST | `/ad/UpdateDomainStatus` |
| POST | `/ad/UpdateGatewayMode` |
| POST | `/ad/UpdateMfaFlagADUsers` |
| POST | `/ad/UserSync` |
| POST | `/ad/addDomain` |
| POST | `/ad/addGateway` |
| POST | `/ad/addGroup` |
| POST | `/ad/addOUs` |
| POST | `/ad/addUser` |
| POST | `/ad/assignGatewayDomain` |
| POST | `/ad/blockPrincipal` |
| POST | `/ad/checkPasswordResetPolicy` |
| POST | `/ad/deleteDomain` |
| POST | `/ad/deleteGateway` |
| POST | `/ad/deleteMFAProvider` |
| GET | `/ad/domain/status/stream` |
| GET | `/ad/downloadAgentBundle` |
| GET | `/ad/downloadAgentConfig` |
| GET | `/ad/downloadSensorConfig` |
| POST | `/ad/getADGroupJobs` |
| POST | `/ad/getAllAdUsers` |
| POST | `/ad/getAllDomains` |
| POST | `/ad/getAllGroupsByDomain` |
| POST | `/ad/getAllUsersByGroup` |
| POST | `/ad/getAuthBadSources` |
| POST | `/ad/getAuthLog` |
| POST | `/ad/getBlockedPrincipals` |
| GET | `/ad/getEnrollmentDetails` |
| POST | `/ad/getEnrollmentStatus` |
| POST | `/ad/getGatewayConfig` |
| POST | `/ad/getGatewaysByOrg` |
| POST | `/ad/getMFAChallenge` |
| POST | `/ad/getMFAProvider` |
| POST | `/ad/getOUs` |
| POST | `/ad/getServiceAccountUserByDomain` |
| POST | `/ad/getShadowGroups` |
| POST | `/ad/getUnenrolledUsersInGroup` |
| POST | `/ad/getUserAuthLog` |
| GET | `/ad/health` |
| POST | `/ad/ingestAuthEvents` |
| POST | `/ad/initiateMFAChallenge` |
| POST | `/ad/listAdGroups` |
| POST | `/ad/registerDevice` |
| POST | `/ad/registerGateway` |
| POST | `/ad/respondMFAChallenge` |
| POST | `/ad/rotateCredentials` |
| POST | `/ad/sendEnrollmentEmail` |
| POST | `/ad/setMFAProvider` |
| POST | `/ad/unassignGatewayDomain` |
| POST | `/ad/unblockPrincipal` |
| POST | `/ad/updateADGroupJobs` |
| POST | `/ad/updateDomainStatus` |
| POST | `/ad/updateGatewayMode` |
| POST | `/ad/updateMfaFlagADUsers` |
| POST | `/ad/userSync` |

## mfa (SSC /authentication alias)  (60)

| Method | Path |
|---|---|
| GET | `/authentication/.well-known/openid-configuration` |
| POST | `/authentication/auth/external-mfa` |
| POST | `/authentication/auth/verifyUser` |
| POST | `/authentication/backToLogin` |
| GET | `/authentication/emaptasaml/login` |
| GET | `/authentication/mfa/.well-known/openid-configuration` |
| POST | `/authentication/mfa/auth/external-mfa` |
| POST | `/authentication/mfa/auth/verifyUser` |
| POST | `/authentication/mfa/backToLogin` |
| POST | `/authentication/mfa/beginAuthRegistration` |
| POST | `/authentication/mfa/beginAuthentication` |
| POST | `/authentication/mfa/beginRegisterWallet` |
| POST | `/authentication/mfa/beginRegistration` |
| POST | `/authentication/mfa/deletePasskey` |
| GET | `/authentication/mfa/emaptasaml/login` |
| POST | `/authentication/mfa/finishAuthentication` |
| POST | `/authentication/mfa/finishRegistration` |
| GET | `/authentication/mfa/oauth2/v1/keys` |
| GET | `/authentication/mfa/okta/getsession` |
| GET | `/authentication/mfa/okta/logout` |
| POST | `/authentication/mfa/okta/normalLogin` |
| POST | `/authentication/mfa/okta/orgLogin` |
| POST | `/authentication/mfa/okta/ssomfa` |
| POST | `/authentication/mfa/passkey/beginAuthentication` |
| POST | `/authentication/mfa/passkey/beginSetup` |
| POST | `/authentication/mfa/passkey/confirmSetup` |
| POST | `/authentication/mfa/passkey/verify` |
| POST | `/authentication/mfa/provider/config` |
| POST | `/authentication/mfa/provider/delete` |
| POST | `/authentication/mfa/provider/get` |
| POST | `/authentication/mfa/provider/set` |
| POST | `/authentication/mfa/push/beginSetup` |
| POST | `/authentication/mfa/push/challenge` |
| POST | `/authentication/mfa/push/confirmSetup` |
| POST | `/authentication/mfa/push/respond` |
| POST | `/authentication/mfa/push/status` |
| POST | `/authentication/mfa/saml/callback` |
| POST | `/authentication/mfa/sms/beginSetup` |
| POST | `/authentication/mfa/sms/confirmSetup` |
| POST | `/authentication/mfa/sms/requestCode` |
| POST | `/authentication/mfa/sms/verify` |
| POST | `/authentication/mfa/status` |
| POST | `/authentication/mfa/totp/beginSetup` |
| POST | `/authentication/mfa/totp/confirmSetup` |
| POST | `/authentication/mfa/totp/delete` |
| POST | `/authentication/mfa/totp/verify` |
| GET | `/authentication/mfa/v1/logout` |
| GET | `/authentication/oauth2/v1/keys` |
| GET | `/authentication/okta/Logout` |
| GET | `/authentication/okta/getsession` |
| GET | `/authentication/okta/logout` |
| POST | `/authentication/okta/normalLogin` |
| POST | `/authentication/okta/orgLogin` |
| POST | `/authentication/okta/ssomfa` |
| POST | `/authentication/push/challenge` |
| POST | `/authentication/push/respond` |
| POST | `/authentication/push/status` |
| POST | `/authentication/saml/callback` |
| GET | `/authentication/v1/Logout` |
| GET | `/authentication/v1/logout` |

## authnz (proxy)  (2)

| Method | Path |
|---|---|
| GET | `/authnz/authenticate` |
| POST | `/authnz/getUserDetails` |

## ssc redirect  (1)

| Method | Path |
|---|---|
| GET | `/ssc/signin` |

