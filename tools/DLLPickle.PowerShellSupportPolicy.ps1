function Get-DLLPicklePowerShellSupportState {
    <#
    .SYNOPSIS
        Evaluates one declared PowerShell line against lifecycle and reviewed retirement policy.
    .DESCRIPTION
        Returns the lifecycle state plus whether an approaching-retirement decision is already
        recorded. A retired line is allowed only when a time-bounded hosted-service compatibility
        holdover cites current Microsoft Learn evidence. The holdover is never labeled as upstream
        Microsoft support.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$RuntimeProfile,

        [Parameter(Mandatory)]
        [datetime]$LifecycleEndExclusiveUtc,

        [Parameter(Mandatory)]
        [datetime]$AsOfUtc,

        [Parameter(Mandatory)]
        [ValidateRange(1, 3650)]
        [int]$RetirementWarningDays
    )

    $EvaluationUtc = $AsOfUtc.ToUniversalTime()
    $EndExclusiveUtc = $LifecycleEndExclusiveUtc.ToUniversalTime()
    $ReleaseLine = '{0}.{1}' -f $RuntimeProfile.powerShellMajor, $RuntimeProfile.powerShellMinor
    $DaysRemaining = [math]::Floor(($EndExclusiveUtc - $EvaluationUtc).TotalDays)
    $IsExpired = $EvaluationUtc -ge $EndExclusiveUtc
    $Status = if ($IsExpired) { 'Expired' } elseif ($DaysRemaining -le $RetirementWarningDays) { 'RetiringSoon' } else { 'Supported' }
    $DecisionRecorded = $false
    $RetirementAction = 'review-at-warning'
    $HoldoverEvidenceAgeDays = $null

    if ($RuntimeProfile.PSObject.Properties.Name -contains 'supportPolicy' -and $null -ne $RuntimeProfile.supportPolicy) {
        $Policy = $RuntimeProfile.supportPolicy
        $RetirementAction = [string]$Policy.retirementAction
        if ($RetirementAction -notin @('retire-at-lifecycle-end', 'retain-for-hosted-service-compatibility')) {
            throw "PowerShell $ReleaseLine has unsupported retirement action '$RetirementAction'."
        }
        $DecisionDateUtc = [datetime]::MinValue
        $DecisionDateIsValid = [datetime]::TryParseExact(
            [string]$Policy.decisionDate,
            'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref]$DecisionDateUtc
        )
        if (-not $DecisionDateIsValid -or
            $DecisionDateUtc.Date -gt $EvaluationUtc.Date -or
            [string]::IsNullOrWhiteSpace([string]$Policy.reviewTrigger)) {
            throw "PowerShell $ReleaseLine retirement policy must contain a decision date and review trigger."
        }

        if ($RetirementAction -eq 'retire-at-lifecycle-end') {
            $DecisionRecorded = -not $IsExpired
        } else {
            $HostedServices = @($Policy.hostedServices)
            if ([string]::IsNullOrWhiteSpace([string]$Policy.evidenceVerifiedUtc) -or
                [int]$Policy.evidenceFreshnessDays -le 0 -or
                $HostedServices.Count -eq 0) {
                throw "PowerShell $ReleaseLine hosted-service holdover lacks bounded evidence metadata."
            }
            foreach ($HostedService in $HostedServices) {
                $DocumentationUri = $null
                if (-not [uri]::TryCreate([string]$HostedService.documentationUrl, [System.UriKind]::Absolute, [ref]$DocumentationUri) -or
                    $DocumentationUri.Scheme -ne 'https' -or
                    $DocumentationUri.Host -ne 'learn.microsoft.com' -or
                    [string]::IsNullOrWhiteSpace([string]$HostedService.name) -or
                    [string]::IsNullOrWhiteSpace([string]$HostedService.finding)) {
                    throw "PowerShell $ReleaseLine hosted-service holdover must cite a complete Microsoft Learn finding."
                }
            }

            $EvidenceVerifiedUtc = [datetime]::Parse(
                [string]$Policy.evidenceVerifiedUtc,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
            )
            if ($EvidenceVerifiedUtc -gt $EvaluationUtc) {
                throw "PowerShell $ReleaseLine hosted-service holdover evidence cannot be verified in the future."
            }
            $HoldoverEvidenceAgeDays = ($EvaluationUtc - $EvidenceVerifiedUtc).TotalDays
            $EvidenceIsFresh = $HoldoverEvidenceAgeDays -le [double]$Policy.evidenceFreshnessDays
            $DecisionRecorded = $EvidenceIsFresh
            if ($IsExpired) {
                $Status = if ($EvidenceIsFresh) { 'CompatibilityHoldover' } else { 'HoldoverReviewDue' }
            }
        }
    }

    [PSCustomObject]@{
        ReleaseLine                = $ReleaseLine
        DaysRemaining              = $DaysRemaining
        Status                     = $Status
        RetirementAction           = $RetirementAction
        RetirementDecisionRecorded = $DecisionRecorded
        HoldoverEvidenceAgeDays     = if ($null -eq $HoldoverEvidenceAgeDays) { $null } else { [math]::Round($HoldoverEvidenceAgeDays, 2) }
    }
}
