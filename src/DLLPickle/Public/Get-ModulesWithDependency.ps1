function Get-ModulesWithDependency {
    <#
    .SYNOPSIS
        Finds installed PowerShell modules that have a common file dependency.

    .DESCRIPTION
        This function queries installed PowerShell resources to identify all modules that have a common dependency on a
        specific file.

    .EXAMPLE
        Get-ModulesWithDependency -FileName 'Microsoft.Identity.Client.dll' | Format-Table Name,Version,@{N='FileName';E={($_.DependencyPath.Split('\'))[-1]}},DependencyVersion

        This will format the output to show the module name, version, file name, and dependency version in a table.

    .EXAMPLE
        Get-ModulesWithDependency -FileName 'Microsoft.Identity.Client.dll'

        This will return an array of PSResourceInfo objects for modules with the specified dependency.

    .OUTPUTS
        Microsoft.PowerShell.PSResourceGet.UtilClasses.PSResourceInfo[]
        An array of PSResourceInfo objects, each with an added 'DependencyPath' and 'DependencyVersion' property.
    #>
    [CmdletBinding()]
    param(
        # The name of the file dependency to search for in the module's manifest file list.
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName
    )

    process {
        Write-Verbose -Message "Searching for installed modules with '$FileName' included in their manifest's file list.`n"
        try {
            $ModulesWithDependency = Get-InstalledPSResource | Where-Object {
                $_.Type -eq 'Module' -and
                $_.AdditionalMetadata.FileList -match [regex]::Escape($FileName)
            }
            Write-Verbose -Message "Found $($ModulesWithDependency.Count) modules with the specified dependency.`n"
        } catch {
            throw "Error retrieving installed modules: $_"
        }

        foreach ($Module in $ModulesWithDependency) {
            Write-Verbose -Message "Module:            $($Module.Name) ($($Module.Version))"
            if ($Module.AdditionalMetadata.FileList -match "\|([^|]*?$FileName)") {
                $DependencyPath = $Matches[1]

                $FullDependencyPath = Join-Path -Path $Module.InstalledLocation -ChildPath $DependencyPath
                Write-Verbose -Message "DependencyPath:    $($FullDependencyPath.Replace($([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyDocuments)), '~\Documents'))"
                Add-Member -Name 'DependencyPath' -InputObject $Module -MemberType NoteProperty -Value $FullDependencyPath

                $DependencyVersion = [version]((Get-ChildItem -Path $FullDependencyPath).VersionInfo.FileVersion)
                Write-Verbose -Message "DependencyVersion: $($DependencyVersion.ToString()).`n"
                Add-Member -Name 'DependencyVersion' -InputObject $Module -MemberType NoteProperty -Value $DependencyVersion

                # Add a custom type name for formatting
                $Module.PSObject.TypeNames.Insert(0, 'DLLPickle.PSResourceInfo')
            }
        }

        $ModulesWithDependency = $ModulesWithDependency | Sort-Object -Property DependencyVersion, Name -Descending
        $ModulesWithDependency
    }
}
