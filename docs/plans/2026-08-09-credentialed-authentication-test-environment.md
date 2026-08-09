# Draft plan: credentialed read-only authentication test environment

**Status:** Draft for security, tenant, and repository-owner review

**Date:** 2026-08-09

**Scope:** Microsoft Graph, Exchange Online, Azure PowerShell, and Microsoft Teams authentication gates for DLLPickle

**External changes performed by this document:** None

## 1. Objective

Create an approval-gated environment that can run DLLPickle's authenticated compatibility tier without interactive sign-in, tenant writes, long-lived client secrets, or misleading pass results when credentials are absent.

The environment must prove that the supported DLLPickle runtime profiles can authenticate and execute the exact read-only probes declared in `build/dependency-policy.json` after the relevant modules and DLLPickle are loaded in both monitored import orders.

This is separate from the deterministic, zero-credential import tier. A missing credential, missing role, conditional-access block, unsupported authentication mode, or unexecuted probe remains a failed or outstanding release gate.

## 2. Current authenticated gates

| Module family | Current authenticated read-only probe | What it proves |
| --- | --- | --- |
| Microsoft.Graph.Authentication | `Get-MgContext \| Out-Null` | A Graph authentication context was established in the current process. |
| ExchangeOnlineManagement | `Get-EXOMailbox -ResultSize 1 \| Out-Null` | EXO app-only authentication and a limited mailbox read succeed. |
| Az.Storage | `Get-AzStorageAccount \| Select-Object -First 1 \| Out-Null` | Azure Resource Manager authentication can enumerate storage-account control-plane metadata. |
| Az.Accounts | `Get-AzContext \| Out-Null` | An Azure PowerShell process-scoped context was established. |
| MicrosoftTeams | `Get-CsTenant \| Out-Null` | Teams application authentication and a tenant read succeed. |
| Az.Resources | `Get-AzResource \| Select-Object -First 1 \| Out-Null` | Azure Resource Manager authentication can enumerate resource metadata. |

The Graph probe currently proves context establishment, not an API read. Before calling the Graph gate complete, decide whether to retain that narrow contract or add a separately reviewed read probe such as an organization read. Do not silently broaden it in the workflow.

## 3. Non-goals and safety invariants

- Do not create, update, delete, assign, invite, send, publish, or consent to tenant data during a test run.
- Do not run the credentialed job for pull requests from forks or for unreviewed code.
- Do not expose access tokens, certificates, assertion tokens, tenant identifiers that are classified as secrets, or command output containing customer data.
- Do not store a client secret in the repository. Prefer short-lived OpenID Connect tokens. A certificate fallback requires explicit approval and a rotation plan.
- Do not use Global Administrator, Owner, Contributor, Exchange Administrator, or another broad role merely to make the probes pass.
- Do not enable a schedule until the manual workflow has been reviewed, exercised, and accepted.
- Do not represent skipped probes as passing compatibility evidence.

## 4. Recommended architecture

### 4.1 GitHub control plane

Create a GitHub environment named `authenticated-readonly` with:

- required reviewer approval;
- self-review prevention where the repository plan supports it;
- deployment branches restricted to `main` and explicitly approved test branches;
- environment-scoped variables and secrets only;
- no automatic execution for forked pull requests;
- a workflow with `contents: read` and `id-token: write`, and no repository-writing permissions.

GitHub environments can withhold environment secrets until required reviewers approve a job. See [Deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).

Start with `workflow_dispatch` only. A release workflow may call the credentialed workflow later, but only after the environment approval and evidence-redaction controls are accepted.

### 4.2 Identity separation

Prefer two dedicated workload identities to keep Azure and Microsoft 365 authorization independently revocable:

1. `dllpickle-azure-readonly`
   - Federated to this repository and the `authenticated-readonly` GitHub environment.
   - Azure `Reader` role at a dedicated test resource group, not the subscription root.
   - The resource group contains at least one storage account and one harmless ARM resource so enumeration probes exercise real code paths.

2. `dllpickle-m365-auth-probe`
   - Federated to the same protected GitHub environment if Graph, EXO, and Teams token exchange is proven to work for the pinned module versions.
   - Assigned only the application permissions and service-specific RBAC needed for the approved probes.
   - No delegated user credentials.

Microsoft documents GitHub-to-Azure workload identity federation through OIDC in [Authenticate to Azure from GitHub Actions by OpenID Connect](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect). Azure's built-in `Reader` role permits control-plane reads without changes; scope it to the dedicated resource group. See [Azure built-in roles for General](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general).

### 4.3 Authentication mechanism decision

Preferred path:

- Use GitHub OIDC to obtain short-lived workload tokens.
- Use `azure/login` with Azure PowerShell session support for Az.Accounts/Az.Resources/Az.Storage.
- Exchange the workload identity for service-specific access tokens for Graph, Exchange Online, and Teams, then pass tokens directly to the modules in process scope.

The feasibility spike must prove all of the following before this becomes the accepted design:

- `Connect-MgGraph -AccessToken ... -ContextScope Process` accepts the acquired Graph token under every pinned PowerShell profile.
- `Connect-ExchangeOnline -AccessToken ... -Organization <primary-onmicrosoft-domain>` accepts the app-only Exchange token.
- `Connect-MicrosoftTeams -AccessTokens @(<graph-token>, <teams-token>)` accepts the required token pair.
- The token audience, cloud endpoints, and module versions are recorded without logging token values.

First-party references:

- [Microsoft Graph PowerShell authentication commands](https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0)
- [Exchange Online app-only authentication](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps)
- [Teams PowerShell application-based authentication](https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-application-authentication)

Fallback path, requiring a separate approval:

- Use one short-lived X.509 certificate per Microsoft 365 test identity.
- Store the encrypted PFX and its password only as protected environment secrets, import it into an ephemeral certificate store, and remove it in an `always()` cleanup step.
- Record owner, expiry, rotation date, and emergency revocation instructions before first use.

Graph, Exchange Online, and Teams all document certificate-based application authentication. The fallback is operationally simpler but introduces a long-lived credential and therefore is not the default.

## 5. Least-privilege authorization work

The tenant administrator must review and execute all consent and role assignments. Repository automation must not grant its own permissions.

### 5.1 Microsoft Graph

- Start with only the application permission needed by the approved Graph read probe.
- If the probe remains `Get-MgContext`, document that it validates authentication context only.
- If an organization read is approved, evaluate `Organization.Read.All` application permission and grant admin consent only after review.
- Use `-ContextScope Process` and call `Disconnect-MgGraph` during cleanup.

### 5.2 Exchange Online

- Configure app-only Exchange authentication using the tenant's primary `.onmicrosoft.com` organization name.
- Review the `Exchange.ManageAsApp` application permission requirement from Microsoft's app-only guidance.
- Use Exchange Online application RBAC or a custom least-privilege management role that permits the specific `Get-EXOMailbox -ResultSize 1` read. Do not assign Exchange Administrator solely for this test.
- Prove that the service principal can read one mailbox object and cannot execute a selected write negative-control command.
- Call `Disconnect-ExchangeOnline -Confirm:$false` during cleanup.

### 5.3 Azure PowerShell

- Assign Azure `Reader` at the dedicated test resource-group scope.
- Confirm the role exposes storage-account and resource control-plane metadata but no data-plane content.
- Include at least one storage account so `Get-AzStorageAccount` cannot pass vacuously because the environment is empty.
- Use a process-scoped context and clear it during cleanup.

### 5.4 Microsoft Teams

- Review the Teams application-authentication permission table for the pinned MicrosoftTeams module.
- `Get-CsTenant` requires a tenant read. Evaluate `Organization.Read.All` and the narrowest supported Microsoft Entra/Teams RBAC role for this cmdlet.
- Do not copy the broad permission set documented for all non-`*-Cs` cmdlets when only `Get-CsTenant` is in scope.
- Prove both the positive read and a denied write negative control.
- Call `Disconnect-MicrosoftTeams` during cleanup.

## 6. Environment configuration contract

Use environment variables for non-secret identifiers and environment secrets only where a provider cannot use OIDC directly.

Candidate environment variables:

- `DLLPICKLE_AUTH_TENANT_ID`
- `DLLPICKLE_AUTH_AZURE_CLIENT_ID`
- `DLLPICKLE_AUTH_M365_CLIENT_ID`
- `DLLPICKLE_AUTH_SUBSCRIPTION_ID`
- `DLLPICKLE_AUTH_RESOURCE_GROUP`
- `DLLPICKLE_AUTH_EXO_ORGANIZATION`
- `DLLPICKLE_AUTH_CLOUD` with an allow-listed default such as `AzureCloud`

Certificate fallback secrets, if explicitly approved:

- `DLLPICKLE_AUTH_M365_PFX_BASE64`
- `DLLPICKLE_AUTH_M365_PFX_PASSWORD`

Never accept arbitrary connection commands, scopes, resource URLs, or probe script text from workflow inputs. Workflow inputs may select a reviewed profile or scenario identifier only.

## 7. Workflow and test-harness implementation

### Phase A: offline contract tests

1. Add a schema for the credentialed environment variables and approved command allow-list.
2. Add zero-network unit tests for missing values, malformed GUIDs, unsupported clouds, and forbidden commands.
3. Add a dry-run mode that prints probe identifiers and expected permissions but never token values or connection arguments containing credentials.
4. Verify the ordinary unit and integration suites remain zero-credential and zero-network.

### Phase B: manual identity feasibility spike

1. Configure the protected GitHub environment and federated identity manually.
2. Run one exact Windows profile with no DLLPickle import to prove each provider's authentication mode independently.
3. Run the approved read probes and negative write controls.
4. Capture only sanitized identity metadata: tenant hash or approved tenant label, client ID if non-secret, token audience, expiry time, authentication mode, module version, command name, success/error type, and workflow run ID.
5. Revoke the federated credential or certificate after the spike if the design is rejected.

### Phase C: DLLPickle compatibility matrix

For each supported PowerShell release line, use the exact patch from `build/powershell-test-matrix.json` and a fresh process for every scenario:

1. Module authentication without DLLPickle.
2. DLLPickle first, then module connection and read probe.
3. Module connection first, then DLLPickle and read probe where the module supports that order.
4. Both monitored cross-module import orders from `build/dependency-policy.json`.
5. Assembly/ALC snapshot before authentication, after connection, and after the read probe.

Begin with the three Windows profiles. Expanding credentialed execution to Linux and macOS requires a separate support and risk review because it increases the number of environments receiving tenant tokens.

### Phase D: release integration

Only after the manual matrix is accepted:

- add the credentialed tier as a reusable, environment-gated workflow;
- keep `workflow_dispatch` available for focused reruns;
- make release readiness depend on a fresh successful credentialed evidence artifact or an explicit maintainer waiver;
- do not allow the job to auto-approve, merge, publish, or mutate issues;
- set a documented evidence freshness window.

## 8. Evidence schema and redaction

Each probe record should include:

- PowerShell exact version, CLR version, TFM, OS, architecture, `$PSHOME`, and executable path;
- DLLPickle version/commit and selected bundle;
- module name/version and import order;
- connection method identifier, token audience identifier, and token expiry timestamp;
- probe command identifier, result, duration, and normalized error type;
- tracked assembly name/version/hash/path/ALC before and after authentication;
- `WritesPerformed: false`;
- workflow run URL and environment name;
- explicit `Executed`, `Skipped`, or `Blocked` status.

Redact access tokens, authorization headers, certificate bytes/passwords, mailbox identities, tenant domains where required, subscription/resource names where required, and raw command output. Upload JSON evidence only after a redaction test passes.

## 9. Negative controls

The feasibility run is not accepted without evidence that the identity is constrained:

- Azure: an approved harmless write attempt using `-WhatIf` where supported, plus an authorization inspection showing no write actions at the assigned scope. Do not perform a real write merely to prove denial.
- Graph: inspect granted application permissions and verify no write permission is consented.
- Exchange: inspect the assigned application RBAC role and confirm it contains only required read cmdlets/parameters.
- Teams: inspect API permissions and assigned role; do not execute a state-changing Teams cmdlet.
- Workflow: confirm forked PRs cannot obtain the environment or OIDC subject, and confirm environment approval is required before token issuance.

## 10. Cleanup, rotation, and incident response

Every job uses an `always()` cleanup step to disconnect providers, clear process-scoped contexts, remove temporary certificate material, and delete temporary module/token caches. Evidence upload occurs after redaction and before runner teardown.

Before enabling the environment, document:

- identity owners and backup owners;
- federated credential subject and audiences;
- role/permission inventory;
- certificate expiry and rotation if the fallback is used;
- normal revocation procedure;
- emergency disable procedure for the GitHub environment and Entra service principals;
- audit-log locations and review cadence.

## 11. Decisions requiring explicit approval

1. Which tenant and dedicated Azure resource group may be used?
2. Is GitHub OIDC the required design, or may the certificate fallback be prototyped if a module cannot consume federated access tokens?
3. Should Graph remain a context-only gate or add a real organization read?
4. What exact Exchange application RBAC role is acceptable for `Get-EXOMailbox -ResultSize 1`?
5. What exact Teams role is the least privilege supported for `Get-CsTenant`?
6. Who reviews the `authenticated-readonly` GitHub environment?
7. What evidence fields require hashing or redaction for the selected tenant?
8. What freshness window is required before release?
9. Is credentialed coverage initially Windows-only across three PowerShell profiles, or is cross-platform token exposure approved?

## 12. Definition of done

- The GitHub environment is protected and cannot be used by forked or unreviewed code.
- No long-lived client secret is used.
- Every permission and role is documented with scope and owner.
- All six configured authenticated read probes execute under each approved profile, or the exact blocked probe is recorded as a release gate.
- Both monitored import orders and with/without-DLLPickle scenarios produce sanitized ALC evidence.
- No test performs a tenant or Azure resource write.
- Missing credentials and denied permissions fail closed.
- Tokens and tenant data are absent from logs and artifacts.
- Revocation and cleanup are demonstrated.
- Maintainers explicitly accept the evidence before changing `not-run-no-approved-credentials` status in `build/dependency-policy.json`.
