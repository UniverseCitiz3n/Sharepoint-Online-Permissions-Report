function Get-PnPSPOFoldersPermissions {
    <#
    .SYNOPSIS
    Function connects to SharepointSite and loads permissions for folders on site
    
    .DESCRIPTION
    Function connects to SharepointSite and loads permissions for folders on site. 
    It is the best to firstly load Libraries Permissions, choose library of intrest and pass it to function
    If folder has unique permissions it loades permissions and goes through them adding every permission to PSObject.
    Folders without unique permissons are added to PSObject with info that it has not unique permissions. Function returns PSObject with permissions
    
    .PARAMETER SiteURL
    Parameter description
    
    .PARAMETER Credential
    Parameter description
    
    .EXAMPLE
    $FoldersPermissions = Get-PnPSPOFoldersPermissions -SiteURL 'https://obss.sharepoint.com/sites/it/' -SiteLibrary $LibrariesPermissions -Credential $Credential
    It is the best to firstly load Libraries Permissions, choose library of intrest and pass it to function

    .EXAMPLE
    $FoldersPermissions = Get-PnPSPOFoldersPermissions -SiteURL 'https://obss.sharepoint.com/sites/it/' -SiteLibrary $LibrariesPermissions -UseWebLogin
    
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]    
        $SiteURL,
        [Parameter()]    
        $SiteLibrary,
        [switch] $UseWebLogin,
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
    if ($null -eq $SiteLibrary) {
        $SiteLibraryRAW = Get-PnPList | Where-Object {$PSItem.TemplateFeatureId -like '*101' -and $PSItem.Hidden -ne $True} | Out-GridView -PassThru
        $SiteLibrary = @()
        foreach ($library in $SiteLibraryRAW) {
            $SiteLibrary += @{
                ItemFullPath = "$($library.ParentWebUrl)/$($library.title)"
            }
        }
    }
    $SiteLibrary = $SiteLibrary | Sort-Object ItemFullPath -Unique
    $SiteLibrariesWithFolders = @()
    Write-Log -Info -Message "Checking for folders in SiteLibraries"
    foreach ($List in $SiteLibrary) {
        try {
            $LibraryCheck = Get-pnplist -Identity $List.ItemFullPath.Split('/')[-1].Trim()
        }
        catch {
            Write-Log -Info -Message "Try using Library Object"
            $_.Exception.Message
            
        }
        if ($LibraryCheck.TemplateFeatureId -like '*101') {
            $LibraryFoldersFieldValues = (Get-PnPListItem -List $LibraryCheck.Title).FieldValues            
            $FoldersToCheck = $LibraryFoldersFieldValues | Where-Object {$_.ContentTypeId -like '0x0120*'}
            if ($null -eq $FoldersToCheck) {
                $HasFolders = $false
            }
            else {
                $HasFolders = $true
            }
            $SiteLibrariesWithFolders += New-Object psobject -Property @{
                DocumentLibraryName = $LibraryCheck.Title;
                Url                 = $LibraryCheck.RootFolder.ServerRelativeUrl;           
                HasFolders          = $HasFolders
            }
        }
    }
    $FolderPermissions = @()
    Write-Log -Info -Message "Reading permissions for folders"
    foreach ($List in $SiteLibrariesWithFolders) {
        if ($List.HasFolders -eq $false) {
            Write-Log -Info -Message "Folder '$($List.DocumentLibraryName)' does not have other folders. Going to next one..."
            continue
        }
        $LibraryFoldersFieldValues = (Get-PnPListItem -List $List.DocumentLibraryName).FieldValues
        $ListItems = @()
        foreach ($Item in $LibraryFoldersFieldValues) {

            $ListItems += New-Object psobject -Property @{
                ItemName        = $Item.FileLeafRef;
                ParentDirectory = $Item.FileDirRef;
                ItemFullPath    = $Item.FileRef;
                ContentTypeId   = $Item.ContentTypeId.ToString().SubString(0, 6)
            }
        }
        $FoldersToCheck = $ListItems | Where-Object {$_.ContentTypeId -eq '0x0120'}
        $DocumentLibraryHasFiles = $ListItems | Where-Object {$_.ContentTypeId -eq '0x0101'}
        if ($null -ne $DocumentLibraryHasFiles) {
            $FolderPermissions += New-Object psobject -Property @{
                ItemName             = 'Files without folders'
                LoginName            = '---'
                PrincipalType        = '---'
                Permission           = "---"
                ParentDirectory      = '---'
                ItemFullPath         = $list.DefaultViewUrl
                HasUniquePermissions = '---'
            }
        }
        Write-Log -Info -Message "In $($FoldersToCheck[0].ParentDirectory) there are $($FoldersToCheck.Count) folders to check."
        foreach ($Folder in $FoldersToCheck) {

            $PathTemp = $Folder.ItemFullPath.Split('/')
            $Path = $PathTemp[$($PathTemp.IndexOf($List.url.Split('/')[-1]))..$PathTemp.count] -join '/'
            $LoadFolder = Get-PnPFolder -Url $Path -Includes ListItemAllFields.RoleAssignments, ListItemAllFields.HasUniqueRoleAssignments
            $LoadSharedWithInfo = Get-PnPFolder -Url $Path -Includes ListItemAllFields
            try {
                $SharedWithDetailsJSON = $LoadSharedWithInfo.ListItemAllFields.FieldValues.SharedWithDetails.Replace('i:0#.f|membership|', '') -replace 'LoginName', 'WhoShared' | ConvertFrom-Json
                $JSONColumns = $SharedWithDetailsJSON | Get-Member
                $SharedWithObjects = @()
                foreach ($item in $JSONColumns.Name[4..$JSONColumns.Count]) {
                    $SharedWithObjects += New-Object psobject -Property @{
                        SharedWith     = $item
                        SharingDetails = $SharedWithDetailsJSON.$item
                    }
                }
            }
            catch {
                Write-Log -Info -Message "No one shared folder"
                #$_.Exception.Message
            }
            foreach ($ThisFolder in $LoadFolder.ListItemAllFields.HasUniqueRoleAssignments) {
                if ($ThisFolder) {           
                    foreach ($roleAssignments in $LoadFolder.ListItemAllFields.RoleAssignments) {
                        Get-PnPProperty -ClientObject $roleAssignments -Property RoleDefinitionBindings, Member
                        #Get the Permissions assigned to user/group
                        foreach ($RoleDefinition in $roleAssignments.RoleDefinitionBindings) {
                            $LoginName = Resolve-SPOLoginName -PrincipalType $roleAssignments.Member.PrincipalType -LoginName $roleAssignments.Member.LoginName -Credential $Credential
                            $FolderPermissions += New-Object psobject -Property @{
                                ItemName             = $Folder.ItemName
                                LoginName            = $LoginName
                                #LoginTitle           = $roleAssignments.Member.Title
                                PrincipalType        = $roleAssignments.Member.PrincipalType
                                Permission           = $RoleDefinition.Name
                                ParentDirectory      = $Folder.ParentDirectory
                                ItemFullPath         = $Folder.ItemFullPath
                                HasUniquePermissions = $True
                                SharedWithDetails    = $SharedWithObjects | Where-Object {$PSItem.SharedWith -eq $LoginName}      
                            }
                        }
                    }
                }
                else {
                    $FolderPermissions += New-Object psobject -Property @{
                        ItemName             = $Folder.ItemName
                        LoginName            = '---'
                        PrincipalType        = '---'
                        Permission           = "Item has permissions of $($List.DocumentLibraryName)"
                        ParentDirectory      = $Folder.ParentDirectory
                        ItemFullPath         = $Folder.ItemFullPath
                        HasUniquePermissions = $False
                        SharedWithDetails    = '---'
                    }
                }
            }
        }
    }
    return $FolderPermissions
}