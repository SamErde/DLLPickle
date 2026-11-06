# Keep the SDK image aligned with global.json; setup.ps1 checks the exact version.
FROM mcr.microsoft.com/dotnet/sdk:10.0.403-noble@sha256:212fe4cb74627d5adf9817a4088906ae3edff1bd853bb27565d4b46731efe61e

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    POWERSHELL_TELEMETRY_OPTOUT=1 \
    NUGET_PACKAGES=/opt/nuget/packages

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates=20260816ubuntu0.24.04.2 \
      curl=8.5.0-2ubuntu10.16 \
      git=1:2.43.0-1ubuntu7.4 \
      jq=1.7.1-3ubuntu0.24.04.2 \
      python3=3.12.3-0ubuntu2.1 \
      procps=2:4.0.4-4ubuntu3.3 \
      libunwind8=1.6.2-3build1.1 \
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
# Restore every TFM's packages/reference packs and warm temporary test projects.
# The complete runtime matrix is exercised by the offline acceptance run.
RUN pwsh -NoLogo -NoProfile -NonInteractive -Command \
    '$env:PSModulePath = "/opt/dllpickle/modules" + [IO.Path]::PathSeparator + (Join-Path $PSHOME "Modules"); & ./tools/Invoke-DLLPickleBuild.ps1 -Task BuildCrossPlatform'

# Subsequent restores (including test fixtures) use only the retained package cache.
# This is image-local; normal repository builds still use their configured feeds.
RUN useradd --create-home --uid 10001 scanner \
    && mkdir -p /root/.config /home/scanner/.config \
      /root/.nuget/NuGet /home/scanner/.nuget/NuGet \
    && cp .oss-scanner/NuGet.Config /root/.nuget/NuGet/NuGet.Config \
    && cp .oss-scanner/NuGet.Config /home/scanner/.nuget/NuGet/NuGet.Config \
    && git config --file /root/.gitconfig --add safe.directory /src \
    && chown -R scanner:scanner /src /opt/nuget /home/scanner \
    && chmod -R a+rX /opt/dllpickle

ENV HOME=/home/scanner \
    PSModulePath=/opt/dllpickle/modules
# Anthropic's tooling layer switches to root; its offline NuGet config is ready too.
USER scanner
ENTRYPOINT []
CMD ["bash"]
