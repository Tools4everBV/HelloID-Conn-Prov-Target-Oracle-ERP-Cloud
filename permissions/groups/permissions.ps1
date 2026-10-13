############################################################
# HelloID-Conn-Prov-Target-Oracle-ERP-Cloud-Permissions-Group
# PowerShell V2
############################################################

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
    Write-Information 'Retrieving permissions'

    $base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)"))
    $headers = @{
        Authorization  = "Basic $base64AuthInfo"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }

    $pageStartIndex = 1
    $pageSize = 100
    do {
        $splatGetRolesParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/hcmRestApi/scim/Roles?startIndex=$pageStartIndex&count=$pageSize"
            Method  = 'GET'
            Headers = $headers
        }

        $rolesResponse = Invoke-RestMethod @splatGetRolesParams
        $retrievedPermissions = @($rolesResponse.Resources)

        foreach ($permission in $retrievedPermissions) {
            $outputContext.Permissions.Add(
                @{
                    DisplayName    = $permission.displayName
                    Identification = @{
                        Reference = $permission.id
                    }
                }
            )
        }

        $responseStartIndex = if ($rolesResponse.startIndex) { [int]$rolesResponse.startIndex } else { $pageStartIndex }
        $pageStartIndex = $responseStartIndex + $retrievedPermissions.Count
    } while ($retrievedPermissions.Count -ge $pageSize)

    Write-Information "Retrieved $($outputContext.Permissions.Count) permissions"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Oracle-ERP-CloudError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
}
