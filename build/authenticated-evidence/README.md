# Authenticated compatibility transition evidence

This directory holds the schema and, only after an explicit maintainer review,
the sanitized manual compatibility record for the initial `3.0.0` multi-target
release.

The temporary bridge is intentionally narrower than the future protected
credentialed workflow:

- exact bundle-source fingerprint;
- exact release version `3.0.0`;
- exact Windows x64 PowerShell 7.4, 7.5, and 7.6 profiles;
- fixed read-only probe and import-order identifiers;
- no credential material or raw service output;
- `WritesPerformed: false` at every level;
- maximum 30-day validity;
- explicit maintainer, confidence, and acceptance timestamp;
- explicit acknowledgement that delegated interactive authentication is not
  least-privilege workload-identity evidence.

`Test-DLLPickleManualAuthenticatedEvidence.ps1` is the authoritative semantic
validator. The JSON schema is a review aid, not an authorization mechanism. No
accepted evidence file is committed until the interactive run is complete.
