################################################################
# HelloID-Conn-Prov-Target-Oracle-ERP-Cloud-RevokePermission-Datasecurity
# PowerShell V2
################################################################
$actionContext.DryRun = $false
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
        $lifecycleProcess = 'RevokePermission'
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    #https://docs.oracle.com/en/cloud/saas/financials/26a/farfa/api-data-security-users.html
    # Process
    switch ($lifecycleProcess) {
        'RevokePermission' {
            $Permission = @{   
                Userrf               = $correlatedAccount.username
                SecurityContext      = $actionContext.References.Permission.SecurityContext
                SecurityContextValue = $actionContext.References.Permission.SecurityContextValue
                RoleCommonName       = $actionContext.References.Permission.RoleCommonName
            }

            Write-Information 'Verifying if a Oracle-ERP-Cloud dataSecurity exists'
            $splatGetUserDataSecurityParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/fscmRestApi/resources/11.13.18.05/dataSecurities?q=Userrf=$($Permission.Userrf);RoleNameCr=$($Permission.RoleNameCr);SecurityContext=$($Permission.SecurityContext);SecurityContextValue=$($Permission.SecurityContextValue)&onlyData=true&limit=2"
                Method  = 'GET'
                Headers = $headers
            }
    
            $correlatedDataSecurity = (Invoke-RestMethod @splatGetUserDataSecurityParams).items            
            
            if (($correlatedDataSecurity | measure-object).count -gt 1) {
                Throw "Multiple dataSecurities found"
            }
            elseif (($correlatedDataSecurity | measure-object).count -eq 0) {
                Write-Information "Oracle-ERP-Cloud DataSecurity: [$($actionContext.PermissionDisplayName)] could not be found, indicating that it may have been deleted"
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Oracle-ERP-Cloud DataSecurity: [$($actionContext.PermissionDisplayName)] could not be found, indicating that it may have been deleted"
                        IsError = $false
                    })
            }       
            else {
                #REVOKE
                if($correlatedDataSecurity.ActiveFlag -eq $true){
                $SetActivebody = @{
                    ActiveFlag = $false
                }

                $splatRevokePermissionParams = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/fscmRestApi/resources/11.13.18.05/dataSecurities/$($correlatedDataSecurity.UserRoleDataAssignmentId)"
                    Method  = 'PATCH'
                    Headers = $headers
                    Body    = $SetActivebody | convertto-json
                }

                if (-not($actionContext.DryRun -eq $true)) {
                    Write-Information "Revoking Oracle-ERP-Cloud dataSecurity: [$($actionContext.PermissionDisplayName)] with id [$($correlatedDataSecurity.UserRoleDataAssignmentId)]"
                    try {
                        $null = Invoke-RestMethod @splatRevokePermissionParams
                        $auditLogMessage = "Revoke permission [$($actionContext.PermissionDisplayName)] with id [$($correlatedDataSecurity.UserRoleDataAssignmentId)] was successful - updating ActiveFlag"
                    }
                    catch {
                        Throw $_
                    }
                }
            
                else {
                    Write-Information "[DryRun] revoke Oracle-ERP-Cloud dataSecurity: [$($actionContext.PermissionDisplayName)] with id [$($correlatedDataSecurity.UserRoleDataAssignmentId)], will be executed during enforcement"
                    Write-Warning "[DryRun] with body: $($splatRevokePermissionParams.body)"
                    $auditLogMessage = "[DryRun]  revoke dataSecurity [$($actionContext.PermissionDisplayName)] with id [$($correlatedDataSecurity.UserRoleDataAssignmentId)] was successful"
                }
                           } else{
                            Write-Information "Skip Revoking - ActiveFlag = $($correlatedDataSecurity.ActiveFlag)"
                           }   
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $auditLogMessage
                    IsError = $false
                })
        }
        'NotFound' {
            Write-Information "Oracle-ERP-Cloud account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Oracle-ERP-Cloud account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $false
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
        $auditLogMessage = "Could not revoke Oracle-ERP-Cloud dataSecurity for account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not revoke Oracle-ERP-Cloud dataSecurity for account: [$($actionContext.References.Account)]. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}