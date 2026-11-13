############################################################
# HelloID-Conn-Prov-Target-Oracle-ERP-Cloud-Permissions-Datasecurity
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

function Confirm-MappingCsv {
    [CmdletBinding()]
    param(
        [array]
        $CsvTable,
        [Parameter(Mandatory)]
        [string]
        $Type

    )
    if ($null -eq $CsvTable) {
        throw "[$Type] does not contain any rows"
    }

    if ($null -eq $CsvTable[0]) {
        throw "[$Type] does not contain any rows"
    }
    $csvHeaders = @{
        'RoleDatasecurity' = @('RoleCommonName', 'SecurityContext','SecurityContextValue')
    }

    if ($null -eq $csvHeaders[$Type]) {
        throw "[$Type] is not a valid type parameter it should be one of [RoleDatasecurity]"
    }

    $compareResult = Compare-Object -ReferenceObject $csvHeaders[$Type] -DifferenceObject  ($CsvTable | Get-Member -MemberType NoteProperty).Name | Where-Object { $_.SideIndicator -eq '<=' }
    if (($compareResult | Measure-Object).Count -gt 0) {
        throw "[$Type] does not contain all required columns. Missing columns: [$($compareResult.InputObject -join ',')]"
    }
}

#endregion

Try{
    $securityContexts = import-csv -Path $actionContext.Configuration.DataSecurityMapping -Delimiter ";"
    $null = Confirm-MappingCsv -CsvTable $securityContexts -Type 'RoleDataSecurity'
}catch {
    Throw "Failed to read mapping file - $($_)"
}

try {    
          foreach ($securityContext in $securityContexts){
            $displayname = "$($securityContext.RoleName) - $($securityContext.SecurityContext) - $($securityContext.SecurityContextValue)"

            if($displayname.length -gt 100){
                $displayname = "$($securityContext.RoleName.Substring(0, [Math]::Min(30, $securityContext.RoleName.Length))).. - $($securityContext.SecurityContext.Substring(0, [Math]::Min(30, $securityContext.SecurityContext.Length))).. - $($securityContext.SecurityContextValue.Substring(0, [Math]::Min(30, $securityContext.SecurityContextValue.Length))).."
            }
              $outputContext.Permissions.Add(
                  @{
                      DisplayName    = $displayname
                      Identification = @{                          
                          RoleCommonName = $securityContext.RoleCode
                          SecurityContext = $securityContext.SecurityContext
                          SecurityContextValue = $securityContext.SecurityContextValue
                      }
                  }
              )
          }
        

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