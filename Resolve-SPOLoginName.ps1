function Resolve-SPOLoginName {
    <#
    .SYNOPSIS
    Helper funtion to SPO Permissions Report
    
    .DESCRIPTION
    Funtion accepts objects like c:0t.cusername and connects to AAD to check for user and return samaccountname.

    .EXAMPLE
    Resolve-SPOLoginName -PrincipalType $roleAssignments.Member.PrincipalType -LoginName $roleAssignments.Member.LoginName -Credential $Credential
    #>
    
    param(
        [Parameter(Mandatory = $true)]    
        $PrincipalType,
        [Parameter(Mandatory = $true)]
        $LoginName,
        [Parameter(Mandatory = $false)]
        [PSCredential] $Credential
    )
    try {
        Get-AzureADCurrentSessionInfo -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Connect-AzureAD  | Out-Null
    }
    if ($PrincipalType -eq 'SecurityGroup') {
        if ($LoginName -like 'c:0t.c*') {
            $SecurityGroupId = $LoginName.Split('|')
            $EmployeeAzureGroups = (Get-AzureADObjectByObjectId -ObjectId $SecurityGroupId[2]).DisplayName
            $LoginName = $EmployeeAzureGroups
        }
    }
    elseif ($PrincipalType -eq 'User') {
        $LoginName = $LoginName.Split('|')[2]
    }
    return $LoginName
}