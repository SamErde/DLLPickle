# Security Policy

## Reporting a Vulnerability

If you discover a vulnerability in DLL Pickle, please follow the process below. I appreciate your efforts to responsibly disclose your findings, and will make every effort to acknowledge your contributions.

Please use the GitHub Security Advisory ["Report a Vulnerability"](https://github.com/SamErde/DLLPickle/security/advisories/new) form to report a security issue or vulnerability.

We will send a response indicating the next steps in handling your report. After the initial acknowledgement, we will keep you informed of the progress towards a fix and full announcement, and may ask for additional information or guidance.

Our goal is to have all reports acknowledged within 7 days and resolved within 30 days. If you do not receive an acknowledgement, escalation may be sent to [security@day3bits.com](mailto:security@day3bits.com).

## 3rd Party Modules

DLL Pickle selects and preloads dependency assemblies inside the caller's
PowerShell process. Its security responsibilities include runtime/profile
selection, assembly and native-library resolution, configuration interpretation,
and the integrity of its build and distributed package. It does not authenticate
users, authorize tenant operations, or implement token storage or cryptography;
those responsibilities belong to the consuming modules and Microsoft libraries.
DLL Pickle remains responsible for how it selects, uses, and packages them.

The per-user configuration is preferences, not an authorization boundary.
`Get-DPConfig` validates recognized setting types before applying them; a read or
validation failure reports `DPConfigReadFailed` and uses the complete default
configuration unless the caller requests terminating errors. In particular, the
default skip list is empty. Validation does not authenticate the configuration or
make a writable module installation trustworthy. Use trusted installation sources
and protect the module and user configuration with the operating system's access
controls. DLL Pickle does not sandbox assemblies or guarantee that conflicting
service modules can safely share a process.

See the existing [threat model](.oss-scanner/threat_model.md) for trust boundaries,
attacker prerequisites, and reproduction limits. Scanner environment preparation
or an enrollment request alone is not evidence that scanning is active.

Please report security bugs in third-party modules to the person or team maintaining the module. You can also report a vulnerability through GitHub for the [MSAL packages](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/security).

## Public Disclosure

Once we have either a) published a fix, or b) declined to address the vulnerability for whatever reason, you are free to publicly disclose it.

## Related Policies

- Dependency and supply chain policy: [DEPENDENCIES.md](docs/DEPENDENCIES.md)
- Contribution workflow and quality gates: [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md)
