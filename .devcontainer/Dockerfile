# PowerShell 7.4 LTS on Debian 12 (Dependabot should update this)
FROM mcr.microsoft.com/powershell:7.4-debian-12@sha256:810c4f1e0c9d23022c3ec18c50a6205ee4b60766f1739d329b2948df1fd7d5b0

# Configure non-root user for development. See https://aka.ms/vscode-remote/containers/non-root-user for details.
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Install system packages and create non-root user
RUN apt-get update && apt-get -y install --no-install-recommends \
    sudo \
    git \
    openssh-client \
    less \
    procps \
    curl \
    wget \
    vim \
    nano \
    jq \
    tree \
    # Create non-root user with sudo access
    && groupadd --gid $USER_GID $USERNAME \
    && useradd -s /bin/bash --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    # Clean up apt cache
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install PowerShell modules for development
RUN pwsh -NoLogo -NoProfile -Command " \
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
    Install-Module -Name Pester -Force -SkipPublisherCheck; \
    Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck; \
    Install-Module -Name InvokeBuild -Force -SkipPublisherCheck"
