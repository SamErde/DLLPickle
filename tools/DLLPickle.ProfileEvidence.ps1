function Get-DLLPickleNormalizedEvidenceFingerprint {
    <#
    .SYNOPSIS
    Recomputes the canonical fingerprint for normalized profile evidence.

    .PARAMETER Evidence
    A normalized evidence envelope with schemaVersion 1 and fingerprinted content.

    .OUTPUTS
    System.String
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object]$Evidence
    )

    if ([int]$Evidence.schemaVersion -ne 1) {
        throw 'Normalized profile evidence has an unsupported schema.'
    }

    $ContentProperty = $Evidence.PSObject.Properties['content']
    if ($null -eq $ContentProperty -or $null -eq $ContentProperty.Value) {
        throw 'Normalized profile evidence has no fingerprinted content.'
    }

    $CanonicalContent = $ContentProperty.Value | ConvertTo-Json -Depth 100 -Compress
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalContent)
    [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::HashData($Bytes)
    ).Replace('-', '').ToLowerInvariant()
}

function ConvertTo-DLLPickleUtcDateTimeOffset {
    <#
    .SYNOPSIS
    Converts a date/time value to a UTC DateTimeOffset.

    .PARAMETER Value
    DateTimeOffset, DateTime, or invariant date/time text to normalize.

    .OUTPUTS
    System.DateTimeOffset
    #>

    [CmdletBinding()]
    [OutputType([System.DateTimeOffset])]
    param (
        [Parameter(Mandatory)]
        [object]$Value
    )

    if ($Value -is [System.DateTimeOffset]) {
        return $Value.ToUniversalTime()
    }
    if ($Value -is [System.DateTime]) {
        return ([System.DateTimeOffset]$Value).ToUniversalTime()
    }
    [System.DateTimeOffset]::Parse(
        [string]$Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal
    ).ToUniversalTime()
}

function ConvertTo-DLLPickleCanonicalUtcTimestamp {
    <#
    .SYNOPSIS
    Formats a date/time value as one canonical UTC JSON timestamp.

    .DESCRIPTION
    DateTimeOffset.ToString('o') represents UTC with +00:00, while PowerShell's
    JSON round trip can deserialize that value into a local DateTime and emit a
    different offset. Converting through UtcDateTime keeps the same instant and
    always emits the round-trip Z representation used by the evidence hashes.

    .PARAMETER Value
    DateTimeOffset, DateTime, or invariant date/time text to normalize.

    .OUTPUTS
    System.String
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object]$Value
    )

    $UtcValue = ConvertTo-DLLPickleUtcDateTimeOffset -Value $Value
    $UtcValue.UtcDateTime.ToString(
        'o',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-DLLPickleStrictProbeCommand {
    <#
    .SYNOPSIS
    Wraps a deterministic probe with one narrowly accepted error outcome.

    .DESCRIPTION
    Returns the command unchanged when no expected error substring is declared.
    Otherwise, it catches only an error containing that exact substring with an
    ordinal, case-insensitive comparison and rethrows every other error. This lets
    a no-authentication probe validate a documented authentication gate without
    weakening strict failure behavior for unexpected probe errors.

    .PARAMETER Command
    Deterministic probe command to execute.

    .PARAMETER ExpectedErrorSubstring
    Exact, non-empty error-message substring that is an accepted probe outcome.

    .OUTPUTS
    System.String
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [Parameter()]
        [string]$ExpectedErrorSubstring
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedErrorSubstring)) {
        return $Command
    }

    $SubstringLiteral = "'{0}'" -f $ExpectedErrorSubstring.Replace("'", "''")
    'try {{ {0} }} catch {{ if ($_.Exception.Message.IndexOf({1}, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {{ throw }} }}' -f $Command, $SubstringLiteral
}

function Get-DLLPickleOrdinalSequence {
    <#
    .SYNOPSIS
    Sorts values deterministically with ordinal string comparison.

    .PARAMETER InputObject
    Values to sort.

    .PARAMETER KeySelector
    Optional script block that returns the primary string sort key for each value.

    .PARAMETER Unique
    Return only the first value for each ordinal primary key.

    .OUTPUTS
    System.Object
    #>

    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [Parameter()]
        [scriptblock]$KeySelector = { param($Item) [string]$Item },

        [Parameter()]
        [switch]$Unique
    )

    $SortableValues = @($InputObject | Where-Object { $null -ne $_ })
    if ($SortableValues.Count -eq 0) {
        return
    }

    $Entries = [System.Collections.Generic.List[object]]::new()
    foreach ($Value in $SortableValues) {
        $PrimaryKey = [string](& $KeySelector $Value)
        $TieBreaker = $Value | ConvertTo-Json -Depth 100 -Compress
        $Entries.Add([pscustomobject]@{
                PrimaryKey = $PrimaryKey
                SortKey    = $PrimaryKey + [char]0 + $TieBreaker
                Value      = $Value
            })
    }
    $Entries.Sort([System.Comparison[object]]{
            param($Left, $Right)
            [System.StringComparer]::Ordinal.Compare([string]$Left.SortKey, [string]$Right.SortKey)
        })

    $PreviousKey = $null
    $HasPreviousKey = $false
    foreach ($Entry in $Entries) {
        if ($Unique -and $HasPreviousKey -and
            [System.StringComparer]::Ordinal.Equals($PreviousKey, [string]$Entry.PrimaryKey)) {
            continue
        }

        $Entry.Value
        $PreviousKey = [string]$Entry.PrimaryKey
        $HasPreviousKey = $true
    }
}

function Get-DLLPickleScenarioFingerprint {
    <#
    .SYNOPSIS
    Computes the location-independent fingerprint for deterministic scenarios.

    .DESCRIPTION
    Fingerprints behavior and selected assembly identity without incorporating
    runner-specific absolute paths or provider error text. The full report still
    retains those diagnostic fields, while normalized evidence separately records
    stable module-relative selected-asset identities.

    .PARAMETER ProfileKey
    Exact PowerShell/TFM/platform/architecture profile key.

    .PARAMETER Scenario
    Deterministic scenario result rows.

    .OUTPUTS
    System.String
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProfileKey,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Scenario
    )

    $CanonicalRows = @(
        'schema=scenario-fingerprint-v2'
        "profile=$ProfileKey"
        foreach ($ScenarioResult in @(Get-DLLPickleOrdinalSequence -InputObject @($Scenario) -KeySelector {
                    param($Item)
                    '{0}{3}{1:D10}{3}{2}' -f $Item.ScenarioId, [int]$Item.OrderIndex, [bool]$Item.DllPicklePreloaded, [char]0
                })) {
            $AssemblyRows = @(
                foreach ($Assembly in @(Get-DLLPickleOrdinalSequence -InputObject @($ScenarioResult.Assemblies) -KeySelector {
                            param($Item)
                            '{0}{5}{1}{5}{2}{5}{3}{5}{4}' -f $Item.Name, $Item.Version, $Item.Sha256, $Item.Alc, [bool]$Item.IsCollectible, [char]0
                        })) {
                    '{0},{1},{2},{3},{4}' -f (
                        [string]$Assembly.Name,
                        [string]$Assembly.Version,
                        ([string]$Assembly.Sha256).ToLowerInvariant(),
                        [string]$Assembly.Alc,
                        [bool]$Assembly.IsCollectible
                    )
                }
            )
            'scenario={0}|order={1}|preload={2}|expectedLimitation={3}|expectedSuccess={4}|outcomePolicy={5}|success={6}|outcomeMatches={7}|errorObserved={10}|modules={8}|assemblies={9}' -f (
                [string]$ScenarioResult.ScenarioId,
                [int]$ScenarioResult.OrderIndex,
                [bool]$ScenarioResult.DllPicklePreloaded,
                [bool]$ScenarioResult.ExpectedLimitation,
                $ScenarioResult.ExpectedSuccess,
                [string]$ScenarioResult.OutcomePolicy,
                [bool]$ScenarioResult.Success,
                [bool]$ScenarioResult.OutcomeMatchesExpectation,
                (@($ScenarioResult.ImportOrder | ForEach-Object { [string]$_ }) -join ','),
                ($AssemblyRows -join ';'),
                -not [string]::IsNullOrWhiteSpace([string]$ScenarioResult.Error)
            )
        }
    )
    $FingerprintBytes = [System.Text.Encoding]::UTF8.GetBytes(($CanonicalRows -join [char]10))
    [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::HashData($FingerprintBytes)
    ).Replace('-', '').ToLowerInvariant()
}
