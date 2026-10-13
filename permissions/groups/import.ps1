####################################################################
# HelloID-Conn-Prov-Target-Oracle-ERP-Cloud-ImportPermissions-Group
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
    Write-Information 'Starting Oracle-ERP-Cloud permission entitlement import'
    $base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)"))
    $headers = @{
        Authorization  = "Basic $base64AuthInfo"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }

    $pageStartIndex = 1
    $pageSize = 100
    do {
        $splatImportPermissionParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/hcmRestApi/scim/Roles?startIndex=$pageStartIndex&count=$pageSize"
            Method  = 'GET'
            Headers = $headers
        }

        $response = Invoke-RestMethod @splatImportPermissionParams
        $importedPermissions = @($response.Resources)

        foreach ($importedPermission in $importedPermissions) {
            $permission = @{
                PermissionReference = @{
                    Reference = $importedPermission.id
                }
                Description         = "$($importedPermission.description)".Substring(0, [math]::Min($importedPermission.description.Length, 100))
                DisplayName         = "$($importedPermission.displayName)".Substring(0, [math]::Min($importedPermission.displayName.Length, 100))
                AccountReferences   = $null
            }

            # The code below splits a list of permission members into batches of 100
            # Each batch is assigned to $permission.AccountReferences and the permission object will be returned to HelloID for each batch
            # Ensure batching is based on the number of account references to prevent exceeding the maximum limit of 500 account references per batch
            $batchSize = 500
            for ($i = 0; $i -lt ($importedPermission.members | Measure-Object).Count; $i += $batchSize) {
                $permission.AccountReferences = @($importedPermission.members[$i..([Math]::Min($i + $batchSize - 1, $importedPermission.members.Count - 1))] | ForEach-Object { $_.value })
                Write-Output $permission
            }
        }

        $responseStartIndex = if ($response.startIndex) { [int]$response.startIndex } else { $pageStartIndex }
        $pageStartIndex = $responseStartIndex + $importedPermissions.Count
    } while ($importedPermissions.Count -ge $pageSize -and ($false -eq $actionContext.DryRun))

    Write-Information 'Oracle-ERP-Cloud permission entitlement import completed'
}
catch {
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