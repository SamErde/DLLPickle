# Keep the SDK image aligned with global.json; setup.ps1 checks the exact version.
FROM mcr.microsoft.com/dotnet/sdk:10.0.302-noble@sha256:72dd743782f2ae7e5476fd64f6a460045e3998dc862218b80e6944cba79a01b0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    POWERSHELL_TELEMETRY_OPTOUT=1 \
    NUGET_PACKAGES=/opt/nuget/packages

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git jq python3 procps libunwind8 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
# Keep tool provisioning cached when only source, tests or documentation change.
COPY global.json ./
COPY build/build-tool-versions.json build/powershell-test-matrix.json build/DLLPickle.Tooling.ps1 ./build/
COPY tools/Install-DLLPickleTestPowerShell.ps1 ./tools/
COPY .github/ci-scripts/Actions_Bootstrap.ps1 ./.github/ci-scripts/
COPY .oss-scanner/setup.ps1 ./.oss-scanner/

# Bootstrap one PowerShell from the same checksum-pinned matrix used by CI.
# setup.ps1 then uses the existing provisioner to validate/install every profile.
RUN set -eu; \
    read -r url checksum < <(jq -er '[.archiveAssets[] | select(.platform == "linux" and .architecture == "x64")] | sort_by(.powerShellVersion | split(".") | map(tonumber)) | last | [.downloadUrl, .sha256] | @tsv' build/powershell-test-matrix.json); \
    curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 "$url" -o /tmp/powershell.tar.gz; \
    printf '%s  /tmp/powershell.tar.gz\n' "$checksum" | sha256sum --check --strict; \
    mkdir -p /opt/powershell-bootstrap; \
    tar -xzf /tmp/powershell.tar.gz -C /opt/powershell-bootstrap; \
    chmod +x /opt/powershell-bootstrap/pwsh; \
    /opt/powershell-bootstrap/pwsh -NoLogo -NoProfile -NonInteractive -File .oss-scanner/setup.ps1; \
    ln -s "$(jq -er 'sort_by(.PowerShellVersion | split(".") | map(tonumber)) | last | .ExecutablePath' /opt/dllpickle/runtimes.json)" /usr/local/bin/pwsh; \
    rm -rf /opt/powershell-bootstrap /tmp/powershell.tar.gz

# The scanner uses the repository as its build context and expects source at /src.
COPY . /src
# Warm the build AND temporary test-project dependencies for every declared runtime.
RUN pwsh -NoLogo -NoProfile -NonInteractive -File .oss-scanner/test.ps1

# Subsequent restores (including test fixtures) use only the retained package cache.
# This is image-local; normal repository builds still use their configured feeds.
RUN mkdir -p /root/.nuget/NuGet \
    && cp .oss-scanner/NuGet.Config /root/.nuget/NuGet/NuGet.Config

ENTRYPOINT []
CMD ["bash"]
