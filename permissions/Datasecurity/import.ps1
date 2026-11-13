
####################################################################
# HelloID-Conn-Prov-Target-Oracle-ERP-Cloud-ImportPermissions-Datasecurity
# PowerShell V2
####################################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-Oracle-ERP-CloudError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            if ($null -ne $errorDetailsObject.errors.description) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.errors.description
            }
            else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            Write-Warning $_.Exception.Message
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    Write-Information 'Starting Oracle-ERP-Cloud dataSecurity entitlement import'
    $base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)"))
    $headers = @{
        Authorization  = "Basic $base64AuthInfo"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }

    Write-Information "Getting all users"
    
    $pageStartIndex = 1
    $pageSize = 100
    $users = @()

    do {
        $splatImportAccountParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/hcmRestApi/scim/Users?startIndex=$pageStartIndex&count=$pageSize"
            Method  = 'GET'
            Headers = $headers
        }
        $response = Invoke-RestMethod @splatImportAccountParams
        $users += $response.Resources

        $responseStartIndex = if ($response.startIndex) { [int]$response.startIndex } else { $pageStartIndex }
        $pageStartIndex = $responseStartIndex + $response.Resources.Count
            
    } while ($response.Resources.Count -ge $pageSize)   

    Write-Information "found $(($users | measure-object).count) users"

    $usersGrouped = $users | Group-Object -Property userName  -AsHashTable

    $offset = 0
    $limit = 100
    do {

        $splatGetEmployeerParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/fscmRestApi/resources/11.13.18.05/dataSecurities?q=ActiveFlag=true&offset=$offset&limit=$limit"
            Method  = 'GET'
            Headers = $headers
        }

        $response = Invoke-RestMethod @splatGetEmployeerParams
        $importedPermissions = @($response.items)

        foreach ($importedPermission in $importedPermissions) {

            $displayname = "$($importedPermission.Rolerf) - $($importedPermission.SecurityContext) - $($importedPermission.SecurityContextValue)"

            if ($displayname.length -gt 100) {
                $displayname = "$($importedPermission.Rolerf.Substring(0, [Math]::Min(30, $importedPermission.Rolerf.Length))).. - $($importedPermission.SecurityContext.Substring(0, [Math]::Min(30, $securityContext.SecurityContext.Length))).. - $($importedPermission.SecurityContextValue.Substring(0, [Math]::Min(30, $importedPermission.SecurityContextValue.Length))).."
            }

            $permission = @{
                PermissionReference = @{
                    RoleCommonName       = $importedPermission.RoleCommonName
                    SecurityContext      = $importedPermission.SecurityContext
                    SecurityContextValue = $importedPermission.SecurityContextValue
                }
                Description         = $displayname 
                DisplayName         = $displayname 
                AccountReferences   = $null
            }
     
            $permission.AccountReferences = @($usersGrouped[$importedpermission.username].ID)
            Write-Output $permission
        }
    
        $offset += $response.limit

    } while ($importedPermissions.Count -ge $pageSize -and ($false -eq $actionContext.DryRun))

    Write-Information 'Oracle-ERP-Cloud dataSecurity entitlement import completed'
}
catch {
    write-warning "$($_)"
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Oracle-ERP-CloudError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Oracle-ERP-Cloud permission entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Oracle-ERP-Cloud permission entitlements. Error: $($ex.Exception.Message)"
    }
}