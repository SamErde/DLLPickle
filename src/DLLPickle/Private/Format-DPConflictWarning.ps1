function Format-DPConflictWarning {
    <#
    .SYNOPSIS
        Builds the user-facing warning message for a known module conflict.
    .PARAMETER Conflict
        A knownConflicts entry (modules, reason, workaround, issue).
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$Conflict
    )

    process {
        $Modules = @($Conflict.modules) -join ' + '
        $Lines = @(
            "DLLPickle: '$Modules' cannot be used together in one PowerShell session. $($Conflict.reason)"
            "Workaround: $($Conflict.workaround)"
            "Details: https://github.com/SamErde/DLLPickle/issues/$($Conflict.issue)"
        )
        $Lines -join [System.Environment]::NewLine
    }
}
