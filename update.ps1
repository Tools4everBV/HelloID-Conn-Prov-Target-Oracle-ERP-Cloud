#################################################
# HelloID-Conn-Prov-Target-Oracle-ERP-Cloud-Update
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
    foreach ($property in $outputContext.Data.PSObject.Properties) {
        switch ($property.Name) {
            'email' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $primaryEmail.value }
            'userName' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.userName }
            'externalId' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.externalId }
            'givenName' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.givenName }
            'familyName' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.name.familyName }
            'active' { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.active }
            default { $helloidAccountObject | Add-Member -NotePropertyName $property.Name -NotePropertyValue $AccountObject.$($property.Name) }
        }
    }
    Write-Output $helloidAccountObject
}
#endregion

try {
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)"))
    $headers = @{
        Authorization  = "Basic $base64AuthInfo"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }

    Write-Information 'Verifying if a Oracle-ERP-Cloud account exists'
    $splatGetUserParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/hcmRestApi/scim/Users/$($actionContext.References.Account)"
        Method  = 'GET'
        Headers = $headers
    }
    try {
        $correlatedAccount = Invoke-RestMethod @splatGetUserParams
    }
    catch {
        $errorObj = Resolve-Oracle-ERP-CloudError -ErrorObject $_
        if ($errorObj.FriendlyMessage -match 'was not found') {
            $correlatedAccount = $null
        }
        else {
            throw
        }
    }

    if ($null -ne $correlatedAccount) {
        $outputContext.PreviousData = ConvertTo-HelloIDAccountObject -AccountObject $correlatedAccount

        # Always compare the account against the current account in target system
        $splatCompareProperties = @{
            ReferenceObject  = @((ConvertTo-HelloIDAccountObject -AccountObject $correlatedAccount).PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $lifecycleProcess = 'UpdateAccount'
        }
        else {
            $lifecycleProcess = 'NoChanges'
        }
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'UpdateAccount' {
            Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"

            $body = @{
                schemas = @('urn:scim:schemas:core:2.0:User')
            }
            foreach ($property in $propertiesChanged) {
                switch ($property.Name) {
                    'email' {
                        $body.emails = @(
                            @{
                                primary = $true
                                value   = $property.Value
                                type    = 'W'
                            }
                        )
                    }
                    'givenName' {
                        if ($null -eq $body.name) {
                            $body.name = @{}
                        }
                        $body.name.givenName = $property.Value
                    }
                    'familyName' {
                        if ($null -eq $body.name) {
                            $body.name = @{}
                        }
                        $body.name.familyName = $property.Value
                    }
                    'active' { $body.active = [System.Convert]::ToBoolean($property.Value) }
                    'userName' { $body.userName = $property.Value }
                    'externalId' { $body.externalId = $property.Value }
                }
            }

            $splatUpdateParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/hcmRestApi/scim/Users/$($actionContext.References.Account)"
                Method  = 'PATCH'
                Headers = $headers
                Body    = ($body | ConvertTo-Json -Depth 5)
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating Oracle-ERP-Cloud account with accountReference: [$($actionContext.References.Account)]"
                $updatedAccount = Invoke-RestMethod @splatUpdateParams
                $outputContext.Data = ConvertTo-HelloIDAccountObject -AccountObject $updatedAccount
            }
            else {
                Write-Information "[DryRun] Update Oracle-ERP-Cloud account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to Oracle-ERP-Cloud account with accountReference: [$($actionContext.References.Account)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped updating Oracle-ERP-Cloud account with AccountReference: [$($actionContext.References.Account)]. Reason: No changes."
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Oracle-ERP-Cloud account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Oracle-ERP-Cloud account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Oracle-ERP-CloudError -ErrorObject $ex
        $auditLogMessage = "Could not update Oracle-ERP-Cloud account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not update Oracle-ERP-Cloud account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}