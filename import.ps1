#################################################
# HelloID-Conn-Prov-Target-Oracle-ERP-Cloud-Import
# PowerShell V2
#################################################

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

function ConvertTo-HelloIDAccountObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $AccountObject
    )
    $emailAddresses = @($AccountObject.emails)
    if ($emailAddresses.Count -gt 1) {
        $emailAddresses = $emailAddresses | Where-Object { $_.primary }
    }
    $primaryEmail = $emailAddresses | Select-Object -First 1

    $helloidAccountObject = [PSCustomObject]@{}
    foreach ($property in $actionContext.ImportFields) {
        switch ($property) {
            'email' { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $primaryEmail.value }
            'userName' { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.userName }
            'externalId' { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.externalId }
            'givenName' { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.name.givenName }
            'familyName' { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.name.familyName }
            'active' { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.active }
            default { $helloidAccountObject | Add-Member -NotePropertyName $property -NotePropertyValue $AccountObject.$($property) }
        }
    }
    Write-Output $helloidAccountObject
}
#endregion

try {
    Write-Information 'Starting Oracle-ERP-Cloud account entitlement import'

    $base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)"))
    $headers = @{
        Authorization  = "Basic $base64AuthInfo"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }

    $pageStartIndex = 1
    $pageSize = 100
    do {
        $splatImportAccountParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/hcmRestApi/scim/Users?startIndex=$pageStartIndex&count=$pageSize"
            Method  = 'GET'
            Headers = $headers
        }

        $response = Invoke-RestMethod @splatImportAccountParams

        if ($response.Resources) {
            foreach ($importedAccount in $response.Resources) {
                $data = ConvertTo-HelloIDAccountObject -AccountObject $importedAccount

                # Make sure the displayName has a value
                $displayName = "$($importedAccount.displayName)"
                if ([string]::IsNullOrEmpty($displayName)) {
                    $displayName = $importedAccount.Id
                }

                # Make sure the userName has a value
                if ([string]::IsNullOrWhiteSpace($importedAccount.userName)) {
                    $importedAccount.userName = $importedAccount.Id
                }

                # Return the result
                Write-Output @{
                    AccountReference = $importedAccount.Id
                    DisplayName      = $displayName
                    UserName         = "$($importedAccount.userName)".Substring(0, [math]::Min($importedAccount.userName.Length, 100))
                    Enabled          = $importedAccount.active
                    Data             = $data
                }
            }
        }

        $responseStartIndex = if ($response.startIndex) { [int]$response.startIndex } else { $pageStartIndex }
        $pageStartIndex = $responseStartIndex + $response.Resources.Count
            
    } while ($response.Resources.Count -ge $pageSize -and ($false -eq $actionContext.DryRun))   
    Write-Information 'Oracle-ERP-Cloud account entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Oracle-ERP-CloudError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Oracle-ERP-Cloud account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Oracle-ERP-Cloud account entitlements. Error: $($ex.Exception.Message)"
    }
}
