################################################################
# HelloID-Conn-Prov-Target-Oracle-ERP-Cloud-GrantPermission-Datasecurity
# PowerShell V2
################################################################
# Enable TLS1.2
$actionContext.DryRun = $false
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
            try {
                $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            }
            catch {
                $errorDetailsObject = $httpErrorObj.ErrorDetails
            }

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

# Begin
try {
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($actionContext.Configuration.UserName):$($actionContext.Configuration.Password)"))
    $headers = @{
        Authorization  = "Basic $base64AuthInfo"
        Accept         = 'application/json'
        'Content-Type' = 'application/vnd.oracle.adf.resourceitem+json'
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
        $lifecycleProcess = 'GrantPermission'
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    #https://docs.oracle.com/en/cloud/saas/financials/26a/farfa/api-data-security-users.html
    # Process
    switch ($lifecycleProcess) {
        'GrantPermission' {
            $body = @{   
                UserName             = $correlatedAccount.username
                SecurityContext      = $actionContext.References.Permission.SecurityContext
                SecurityContextValue = $actionContext.References.Permission.SecurityContextValue
                RoleCommonName       = $actionContext.References.Permission.RoleCommonName
            }

            $splatGetUserDataSecurityParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/fscmRestApi/resources/11.13.18.05/dataSecurities?q=Userrf=$($body.UserName);RoleCommonName=$($body.RoleCommonName);SecurityContext=$($body.SecurityContext);SecurityContextValue=$($body.SecurityContextValue)&onlyData=true&limit=5"
                Method  = 'GET'
                Headers = $headers
            }
    
            $correlatedDataSecurity = (Invoke-RestMethod @splatGetUserDataSecurityParams).items            
            $SetActivebody = @{
                ActiveFlag = $false
            }

            if (($correlatedDataSecurity | measure-object).count -gt 1) {
                $lifecycleSubProcess = "MultipleFound"
            }
            elseif (($correlatedDataSecurity | measure-object).count -eq 1) {
                if ($correlatedDataSecurity.ActiveFlag -eq $false) {
                    $lifecycleSubProcess = "SetActive"
                }
                else {
                    $lifecycleSubProcess = "SkipAction"
                }
            }
            else {
                $lifecycleSubProcess = "Grant"
            }

            switch ($lifecycleSubProcess) {
                'Grant' {
                    $splatGrantPermissionParams = @{
                        Uri     = "$($actionContext.Configuration.BaseUrl)/fscmRestApi/resources/11.13.18.05/dataSecurities"
                        Method  = 'POST'
                        Headers = $headers
                        Body    = $body | convertto-json
                    }

                    if (-not($actionContext.DryRun -eq $true)) {
                        Write-Information "Granting Oracle-ERP-Cloud dataSecurity: [$($actionContext.PermissionDisplayName)]"
                        try {
                            $null = Invoke-RestMethod @splatGrantPermissionParams
                            $auditLogMessage = "Grant permission [$($actionContext.PermissionDisplayName)] was successful"
                        }
                        catch {
                            if ($_.ErrorDetails.message -eq "Er bestaat al een record met deze combinatie van waarden.") {
                                $auditLogMessage = "Granting permission [$($actionContext.PermissionDisplayName)] was skipped - Reason: already granted"
                            }
                            else {
                                Throw $_
                            }
                        }
                    }
                    else {
                        Write-Information "[DryRun] Grant Oracle-ERP-Cloud dataSecurity: [$($actionContext.PermissionDisplayName)], will be executed during enforcement"
                        Write-Warning "[DryRun] with body: $($splatGrantPermissionParams.body)"
                        $auditLogMessage = "[DryRun]  Grant dataSecurity [$($actionContext.PermissionDisplayName)] was successful"
                    }
                    break
                }
                'SetActive' {
                    $SetActivebody = @{
                        ActiveFlag = $true
                    }

                    $splatGrantPermissionParams = @{
                        Uri     = "$($actionContext.Configuration.BaseUrl)/fscmRestApi/resources/11.13.18.05/dataSecurities/$($correlatedDataSecurity.UserRoleDataAssignmentId)"
                        Method  = 'PATCH'
                        Headers = $headers
                        Body    = $SetActivebody | convertto-json
                    }

                    if (-not($actionContext.DryRun -eq $true)) {
                        Write-Information "Granting Oracle-ERP-Cloud dataSecurity: [$($actionContext.PermissionDisplayName)]"
                        try {
                            $null = Invoke-RestMethod @splatGrantPermissionParams
                            $auditLogMessage = "Grant permission [$($actionContext.PermissionDisplayName)] was successful - updating ActiveFlag"
                        }
                        catch {
                            Throw $_
                        }
                    }
                
                    else {
                        Write-Information "[DryRun] Grant Oracle-ERP-Cloud dataSecurity: [$($actionContext.PermissionDisplayName)], will be executed during enforcement"
                        Write-Warning "[DryRun] with body: $($splatGrantPermissionParams.body)"
                        $auditLogMessage = "[DryRun]  Grant dataSecurity [$($actionContext.PermissionDisplayName)] was successful"
                    }

                    break
                }                
                'MultipleFound' {
                    Throw "Oracle-ERP-Cloud dataSecurity: [$($actionContext.PermissionDisplayName)] multiple found."
                }
                'SkipAction' {
                    $auditLogMessage = "Granting permission [$($actionContext.PermissionDisplayName)] was skipped - Reason: already granted"
                }
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditLogMessage
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
        $auditLogMessage = "Could not grant Oracle-ERP-Cloud dataSecurity for account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not grant Oracle-ERP-Cloud dataSecurity for account: [$($actionContext.References.Account)]. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}