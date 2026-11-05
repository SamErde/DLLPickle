---
title: OSS Scanner environment
summary: Prepare DLL Pickle for offline security analysis.
---

## Build and verify

From the repository root on a Linux x64 Docker host:

```sh
docker build -f .oss-scanner/Dockerfile -t dllpickle-oss-scanner .
docker run --rm --network none --cpus 2 --memory 8g \
  dllpickle-oss-scanner pwsh -NoLogo -NoProfile -NonInteractive \
  -File .oss-scanner/test.ps1
```

The build downloads framework dependencies and warms test-project restores.
The second command rebuilds and tests in a new container with no networking and no
host files mounted. A successful image build alone is not offline test evidence.

The image uses `global.json`, `build/build-tool-versions.json`, and
`build/powershell-test-matrix.json`. Update the SDK image tag and digest
when `global.json` changes; setup rejects a mismatch. Runtime archives use the
matrix checksums and the existing stock-PowerShell provisioner. Each runtime has
its own fresh processes and explicit module path.

The Dockerfile also pins its direct OS package versions. Review those pins with
base-image updates; expired package versions fail the build rather than silently
selecting replacements. Dependency feeds and transitive OS packages remain
external inputs, so these pins are not a claim of bit-for-bit reproducibility.

Source is at `/src`; the built module is at `/src/module/DLLPickle`. Tools and
runtimes live under `/opt/dllpickle`; the NuGet cache is `/opt/nuget/packages`.
The final image's user-level NuGet configuration permits only that local cache.
This does not change normal builds outside the image. Online dependency audits
remain in the existing dependency workflows; offline restores cannot refresh
vulnerability data.

The project image defaults to the unprivileged `scanner` user. Anthropic's
tooling layer switches to root; both users have the same offline NuGet policy.
The analysis source and NuGet cache are writable, while installed runtimes and
build tools remain root-owned. Shared tools are on the default module path.

`test.ps1` runs the existing cross-platform build, then unit tests, synthetic
integration tests, strict package composition and TFM checks for every declared
Linux profile. Live service probes are disabled. JSON/XML results are separated
by runtime under `/src/artifacts/oss-scanner`; a passing summary is written only
after every check succeeds.

For interactive investigation:

```sh
docker run --rm -it --network none dllpickle-oss-scanner bash
```

The reusable `OSS-Scanner.yml` workflow saves the source commit, image metadata,
network mode, build/test logs and per-runtime results for 30 days.
`Build Module` calls it for build-relevant changes and includes its result in
the existing Build gate. Documentation-only changes can skip expensive jobs.
Dependabot tracks the scanner image separately from the development container.

## Enrollment after merge

Track preparation in
[issue #318](https://github.com/SamErde/DLLPickle/issues/318).
After the implementation PR is merged, create an upstream tracking issue and a
dedicated fork branch in `anthropics/oss-scanner`. Add only
`projects/dllpickle/project.yaml`, pointing to this Dockerfile and threat model.
Confirm the monitored primary security inbox before publishing the registration.

Run the upstream checks from the oss-scanner checkout:

```sh
python3 tools/validate.py
python3 tools/check dllpickle
# Inside the resulting offline shell:
pwsh -NoLogo -NoProfile -NonInteractive -File .oss-scanner/test.ps1
```

The helper clones the configured remote ref; it does not test unpublished local
files. Record the actual source revision and results in the enrollment PR.
Anthropic's build-only CI does not replace the offline test run. Its scanner
adds a tooling layer, so the project image's digest pin does not pin that layer.

Use the current upstream PR template and provide a factual security-criticality
and adoption rationale. The maintainer must make the contact, service terms and
CLA decisions. Creating these files does not enroll DLL Pickle or accept terms.
See [upstream contribution requirements](https://github.com/anthropics/oss-scanner/blob/main/CONTRIBUTING.md).

## Coverage

This environment verifies Linux execution and synthetic authentication-module
interactions. It does not validate live tenant sign-in, Windows broker/WAM,
macOS execution, or the full upstream service-module compatibility matrix.
Existing release and compatibility checks remain necessary. See
[the threat model](threat_model.md) for analysis scope and severity guidance.
