#################################################
# HelloID-Conn-Prov-Target-Oracle-ERP-Cloud-Create
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
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails 
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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    $base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)"))
    $headers = @{
        Authorization  = "Basic $base64AuthInfo"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]
        Write-Information "Verifying if a Oracle-ERP-Cloud account exists where $correlationField is: [$correlationValue]"

        $splatGetUserParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/hcmRestApi/scim/Users?filter=$($correlationField) eq $($correlationValue)"
            Method  = 'GET'
            Headers = $headers
        }

        $correlatedAccount = (Invoke-RestMethod @splatGetUserParams).Resources
    }

    if ($correlatedAccount.Count -eq 0) {
        $lifecycleProcess = 'CreateAccount'
    }
    elseif ($correlatedAccount.Count -eq 1) {
        $correlatedAccount = $correlatedAccount | select-object -first 1
        $lifecycleProcess = 'CorrelateAccount'
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    }

    # Extra get request to retrieve the employee account of the correlated user account. This is needed to link the 2 accounts together.
    $splatGetEmployeerParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/hcmRestApi/resources/11.13.18.05/workers?q=PersonNumber=$($actionContext.Data.externalId)&fields=PersonId&onlyData=true"
        Method  = 'GET'
        Headers = $headers
    }
    $correlatedEmployeeAccount = (Invoke-RestMethod @splatGetEmployeerParams).items

    if ($correlatedEmployeeAccount.Count -eq 0) {
        throw "No employee account found for person where PersonNumber is: [$($actionContext.Data.externalId)]"
    }
    if ($correlatedEmployeeAccount.Count -gt 1) {
        throw "Multiple employee accounts found for person where PersonNumber is: [$($actionContext.Data.externalId)]"
    }

    # Process
    switch ($lifecycleProcess) {
        'CreateAccount' {
            [System.Collections.Generic.List[object]]$emailList = @()
            $emailList.Add(
                [PSCustomObject]@{
                    primary = $true
                    value   = $actionContext.Data.email
                    type    = 'W'
                }
            )

            $body = @{
                schemas    = @(
                    'urn:scim:schemas:core:2.0:User'
                )
                name       = @{
                    familyName = $actionContext.Data.familyName
                    givenName  = $actionContext.Data.givenName
                }
                active     = $actionContext.Data.active
                userName   = $actionContext.Data.userName
                emails     = $emailList
                externalId = $actionContext.Data.externalId
            } | ConvertTo-Json


            $splatCreateParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/hcmRestApi/scim/Users"
                Method  = 'POST'
                Headers = $headers
                Body    = $body
            }

            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating Oracle-ERP-Cloud account'

                $createdAccount = Invoke-RestMethod @splatCreateParams

                # Link the newly created user account to the employee account. This is needed to link the 2 accounts together.
                $splatLinkUserParams = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/hcmRestApi/resources/11.13.18.05/userAccounts/$($createdAccount.Id)"
                    Method  = 'PATCH'
                    Headers = $headers
                    Body    = (@{
                            PersonId = $correlatedEmployeeAccount.PersonId
                        } | ConvertTo-Json)
                }
                $null = Invoke-RestMethod @splatLinkUserParams

                # Make sure to filter out arrays from $outputContext.Data (If this is not mapped to type Array in the fieldmapping). This is not supported by HelloID.
                $outputContext.Data = ConvertTo-HelloIDAccountObject -AccountObject $createdAccount
                $outputContext.AccountReference = $createdAccount.Id
            }
            else {
                Write-Information '[DryRun] Create and correlate Oracle-ERP-Cloud account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Oracle-ERP-Cloud account'

            # Link the newly correlated user account to the employee account. This is needed to link the 2 accounts together.
            $splatLinkUserParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/hcmRestApi/resources/11.13.18.05/userAccounts/$($correlatedAccount.Id)"
                Method  = 'PATCH'
                Headers = $headers
                Body    = (@{
                        PersonId = $correlatedEmployeeAccount.PersonId
                    } | ConvertTo-Json)
            }
            if (-not($actionContext.DryRun -eq $true)) {
                $null = Invoke-RestMethod @splatLinkUserParams
            }

            # Make sure to filter out arrays from $outputContext.Data (If this is not mapped to type Array in the fieldmapping). This is not supported by HelloID.
            $outputContext.Data = ConvertTo-HelloIDAccountObject -AccountObject $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.Id
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.Success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $lifecycleProcess
            Message = $auditLogMessage
            IsError = $false
        })
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Oracle-ERP-CloudError -ErrorObject $ex
        $auditLogMessage = "Could not create or correlate Oracle-ERP-Cloud account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not create or correlate Oracle-ERP-Cloud account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}