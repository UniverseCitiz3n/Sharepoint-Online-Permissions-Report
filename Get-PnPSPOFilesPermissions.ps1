function Get-PnPSPOFilesPermissions {
    <#
   .SYNOPSIS
    Function connects to SharepointSite and loads permissions for files on site
    
    .DESCRIPTION
    Function connects to SharepointSite and loads permissions for files on site. 
    It is the best to firstly load Folders Permissions, choose library of intrest and pass it to function
    If folder has unique permissions it loades permissions and goes through them adding every permission to PSObject.
    Files without unique permissons are added to PSObject with info that it has not unique permissions. Function returns PSObject with permissions
    
    .PARAMETER SiteURL
    Parameter description
    
    .PARAMETER Credential
    Parameter description
    
    .EXAMPLE
    $FilesPermissions = Get-PnPSPOFilesPermissions -SiteURL 'https://obss.sharepoint.com/sites/it/' -SiteFolder $FoldersPermissions -Credential $Credential
    It is the best to firstly load Folders Permissions, choose folder of intrest and pass it to function
    
    .EXAMPLE
    $FilesPermissions = Get-PnPSPOFilesPermissions -SiteURL 'https://obss.sharepoint.com/sites/it/' -SiteFolder $FoldersPermissions -UseWebLogin

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]    
        $SiteURL,
        [Parameter()]    
        $SiteFolder,
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
    if ($null -eq $SiteFolder) {
        Write-Output "Please specify source folder"
        break
    }
    $SiteFolder = $SiteFolder | Sort-Object ItemFullPath -Unique
    $SiteFoldersArray = @()
    foreach ($List in $SiteFolder) {        

        $Folder = Get-PnPFolder -Url $List.ItemFullPath -Includes Files
        if ($Folder.Files.Count -eq 0) {
            $HasFiles = $false
        }
        else {
            $HasFiles = $true
        }
        $SiteFoldersArray += New-Object psobject -Property @{
            FolderObject = $Folder;
            Url          = $List.ItemFullPath;           
            HasFiles     = $HasFiles
        }
    }

    $FilesPermissions = @()
    foreach ($List in $SiteFoldersArray) {
        if ($List.HasFiles -eq $false) {
           
            Write-Log -Info -Message "This Folder does not have files. Going to next one..."
            continue
        }
        
       
        Write-Log -Info -Message "In $($List.FolderObject.Name) there are $($List.FolderObject.Files.Count) files to check."

        
        foreach ($File in $List.FolderObject.Files) {
            #$file = $SiteFoldersArray[0].FolderObject.Files
            $context.Load($File.ListItemAllFields)
            $context.ExecuteQuery()
            if ($null -eq $File.ListItemAllFields.FieldValues.SharedWithDetails) {
                $FilesPermissions += New-Object psobject -Property @{
                    ItemName             = $File.ListItemAllFields.FieldValues.FileLeafRef
                    LoginName            = '---'
                    PrincipalType        = '---'
                    Permission           = "Item has permissions of $($List.FolderObject.Name)"
                    ParentDirectory      = $list.FolderObject.ServerRelativeUrl
                    ItemFullPath         = $File.ListItemAllFields.FieldValues.FileRef
                    HasUniquePermissions = $False
                }
            }
            else {
                $context.Load($file.ListItemAllFields.RoleAssignments)
                $context.ExecuteQuery()
                foreach ($roleAssignments in $File.ListItemAllFields.RoleAssignments) {
                    Get-PnPProperty -ClientObject $roleAssignments -Property RoleDefinitionBindings, Member
                    #Get the Permissions assigned to user/group            
                    foreach ($RoleDefinition in $roleAssignments.RoleDefinitionBindings) {
                        $LoginName = Resolve-SPOLoginName -PrincipalType $roleAssignments.Member.PrincipalType -LoginName $roleAssignments.Member.LoginName -Credential $Credential
                        $FilesPermissions += New-Object psobject -Property @{
                            ItemName             = $File.ListItemAllFields.FieldValues.FileLeafRef
                            LoginName            = $LoginName
                            #LoginTitle    = $roleAssignments.Member.Title
                            PrincipalType        = $roleAssignments.Member.PrincipalType
                            Permission           = $RoleDefinition.Name
                            ParentDirectory      = $list.FolderObject.ServerRelativeUrl
                            ItemFullPath         = $File.ListItemAllFields.FieldValues.FileRef
                            HasUniquePermissions = $true
                        }
                    }
                }
            }
        }
    }
    Return $FilesPermissions
}
