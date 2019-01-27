function Get-PnPSPOLibrariesPermissions {
    <#
    .SYNOPSIS
    Function connects to SharepointSite and loads permissions for Libraries on site
    
    .DESCRIPTION
    Function connects to SharepointSite and loads permissions for Libraries on site. If library has unique permissions it loades permissions and goes through them adding every permission to PSObject.
    Libraries without unique permissons are added to PSObject with info that it has not unique permissions. Function returns PSObject with permissions
    
    .PARAMETER SiteURL
    Parameter description
    
    .PARAMETER Credential
    Parameter description
    
    .EXAMPLE
    $LibrariesPermissions = Get-PnPSPOLibrariesPermissions -SiteURL 'https://obss.sharepoint.com/sites/it/' -Credential $Credential
    
    .EXAMPLE
    $LibrariesPermissions = Get-PnPSPOLibrariesPermissions -SiteURL 'https://obss.sharepoint.com/sites/it/' -UseWebLogin

    .NOTES
    General notes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]    
        $SiteURL,
        [swtich] $UseWebLogin,
        [Parameter(Mandatory = $false)]
        [PSCredential] $Credential
    )
    if ($UseWebLogin) {
        try {
            Get-PnPConnection | Out-Null
            if ((Get-PnPConnection).Url -ne $SiteURL) {
                Connect-PnPOnline -Url $SiteURL -UseWebLogin -Verbose
            }
        }
        catch {
            Connect-PnPOnline -Url $SiteURL -UseWebLogin -Verbose
        }
    }else{        
        try {
            Get-PnPConnection | Out-Null
            if ((Get-PnPConnection).Url -ne $SiteURL) {
                Connect-PnPOnline -Url $SiteURL -Credential $Credential -Verbose
            }
        }
        catch {
            Connect-PnPOnline -Url $SiteURL -Credential $Credential -Verbose
        }
    }

    $SiteLists = Get-PnPList
    
    Write-Log -Info -Message "On this site there are $($SiteLists.Count) libraries."
    Write-Log -Info -Message "Reading their permissions..."
    $LibrariesPermissions = @()
    foreach ($List in $SiteLists) {
        
        $LibraryPermissions = Get-PnPList -Identity $List.Title -Includes RoleAssignments, HasUniqueRoleAssignments
        foreach ($ThisLibrary in $LibraryPermissions.HasUniqueRoleAssignments) {
            if ($ThisLibrary) {
                foreach ($Library in $LibraryPermissions.RoleAssignments) {
                    $member = $Library.Member
                    $loginName = get-pnpproperty -ClientObject $member -Property LoginName
                    $PrincipalType = get-pnpproperty -ClientObject $member -Property PrincipalType
                    $rolebindings = get-pnpproperty -ClientObject $Library -Property RoleDefinitionBindings
                    $loginName = Resolve-SPOLoginName -PrincipalType $PrincipalType -LoginName $loginName -Credential $Credential
                    $LibrariesPermissions += New-Object psobject -Property @{
                        ItemName             = "Library - $($List.Title)"
                        LoginName            = $loginName
                        PrincipalType        = $PrincipalType
                        Permission           = $rolebindings.Name
                        ParentDirectory      = $List.RootFolder.ServerRelativeUrl
                        ItemFullPath         = $List.RootFolder.ServerRelativeUrl
                        HasUniquePermissions = $True               
                    }
                }
            }
            else {
                $LibrariesPermissions += New-Object psobject -Property @{
                    ItemName             = "Library - $($List.Title)"
                    LoginName            = '---'
                    PrincipalType        = '---'
                    Permission           = 'Library has permissions of site'
                    ParentDirectory      = $List.RootFolder.ServerRelativeUrl
                    ItemFullPath         = $List.RootFolder.ServerRelativeUrl
                    HasUniquePermissions = $False
                }
            }
        }
    }
    return $LibrariesPermissions
}