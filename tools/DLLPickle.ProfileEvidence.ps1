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

    $ContentProperty = $Evidence.PSObject.Properties['content']
    if ([int]$Evidence.schemaVersion -ne 1 -or $null -eq $ContentProperty -or $null -eq $ContentProperty.Value) {
        throw 'Normalized profile evidence has an unsupported schema or no fingerprinted content.'
    }

    $CanonicalContent = $ContentProperty.Value | ConvertTo-Json -Depth 100 -Compress
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($CanonicalContent)
    [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::HashData($Bytes)
    ).Replace('-', '').ToLowerInvariant()
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
