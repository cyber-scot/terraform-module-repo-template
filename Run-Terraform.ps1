<#
.SYNOPSIS
    Automates the execution of Terraform operations (init, plan, apply, destroy) with configurable parameters and includes Terraform version management using 'tfenv'.

.DESCRIPTION
    This PowerShell script offers a parameter-driven approach to manage Terraform commands. It allows users to control the execution of Terraform init, plan, apply, and destroy operations. Additionally, it handles Terraform version management using 'tfenv', ensuring the desired version of Terraform is installed and used. The script is suitable for both automated environments and manual execution, providing options for debugging and plan file cleanup post-execution.

.PARAMETER RunTerraformInit
    Executes 'terraform init' when set to 'true'.

.PARAMETER RunTerraformPlan
    Executes 'terraform plan' when set to 'true'.

.PARAMETER RunTerraformPlanDestroy
    Executes 'terraform plan' with the destroy option when set to 'true'.

.PARAMETER RunTerraformApply
    Executes 'terraform apply' when set to 'true'.

.PARAMETER RunTerraformDestroy
    Executes 'terraform destroy' when set to 'true'.

.PARAMETER WorkingDirectory
    Specifies the directory where Terraform commands will be executed.

.PARAMETER DebugMode
    Enables additional diagnostic output if set to 'true'.

.PARAMETER DeletePlanFiles
    Determines whether to delete Terraform plan files after execution, set to 'true' to enable deletion.

.PARAMETER TerraformVersion
    Specifies the version of Terraform to use, accepts 'latest' or a specific version number.

.EXAMPLE
    .\Run-Terraform.ps1 -RunTerraformInit "true" -RunTerraformPlan "true" -RunTerraformApply "false" -RunTerraformDestroy "false" -DebugMode "false" -DeletePlanFiles "true" -TerraformVersion "latest"
    Runs Terraform init and plan with the latest version of Terraform, without debug mode, and deletes plan files after execution.

.NOTES
    Ensure Terraform or 'tfenv' is installed and accessible in the system path. The script is intended for use in a PowerShell environment. It's designed for flexibility and includes error handling to ensure smooth execution.

#>

param (
    [string]$RunTerraformInit = "true",
    [string]$RunTerraformPlan = "true",
    [string]$RunTerraformPlanDestroy = "false",
    [string]$RunTerraformApply = "false",
    [string]$RunTerraformDestroy = "false",
    [string]$WorkingDirectory = (Get-Location).Path,
    [string]$DebugMode = "false",
    [string]$DeletePlanFiles = "true",
    [string]$TerraformVersion = "latest",

    [Parameter(Mandatory = $true)]
    [string]$TerraformStateName,

    [Parameter(Mandatory = $true)]
    [string]$BackendStorageSubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$BackendStorageResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$BackendStorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$BackendStorageAccountBlobContainerName
)

# Function to check if Tfenv is installed
function Check-TfenvExists {
    try {
        $tfenvPath = Get-Command tfenv -ErrorAction Stop
        Write-Host "Success: Tfenv found at: $($tfenvPath.Source)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Warning: Tfenv is not installed or not in PATH. Skipping version checking."
        return $false
    }
}

# Function to check if Terraform is installed
function Check-TerraformExists {
    try {
        $terraformPath = Get-Command terraform -ErrorAction Stop
        Write-Host "Success: Terraform found at: $($terraformPath.Source)" -ForegroundColor Green
    }
    catch {
        Write-Error "Error: Terraform is not installed or not in PATH. Exiting."
        exit 1
    }
}

# Function to ensure the desired version of Terraform is installed
function Ensure-TerraformVersion {
    # Check if the specified version is already installed
    $tfVersion = $TerraformVersion.ToLower()
    if ($tfVersion -eq 'latest') {
        Write-Host "Success: Terraform version is set to 'latest', running install and use" -ForegroundColor Green
        tfenv install $tfVersion
        tfenv use $tfVersion
    }
    else {
        try {
            Write-Information "Info: Installing Terraform version $Version using tfenv..."
            tfenv install $Version
            tfenv use $Version
            Write-Host "Success: Installed and set Terraform version $Version" -ForegroundColor Green
        }
        catch {
            Write-Error "Error: Failed to install Terraform version $Version"
            exit 1
        }
    }
}

# Function to convert string to boolean
function Convert-ToBoolean($value) {
    $valueLower = $value.ToLower()
    if ($valueLower -eq "true") {
        return $true
    }
    elseif ($valueLower -eq "false") {
        return $false
    }
    else {
        Write-Error "Error: Invalid value - $value. Exiting."
        exit 1
    }
}

$tfenvExists = Check-TfenvExists
if ($tfenvExists) {
    Ensure-TerraformVersion -Version $TerraformVersion
}

Check-TerraformExists

# Convert string parameters to boolean
$RunTerraformInit = Convert-ToBoolean $RunTerraformInit
$RunTerraformPlan = Convert-ToBoolean $RunTerraformPlan
$RunTerraformPlanDestroy = Convert-ToBoolean $RunTerraformPlanDestroy
$RunTerraformApply = Convert-ToBoolean $RunTerraformApply
$RunTerraformDestroy = Convert-ToBoolean $RunTerraformDestroy
$DebugMode = Convert-ToBoolean $DebugMode
$DeletePlanFiles = Convert-ToBoolean $DeletePlanFiles

# Enable debug mode if DebugMode is set to $true
if ($DebugMode) {
    $DebugPreference = "Continue"
}

# Diagnostic output
Write-Debug "RunTerraformInit: $RunTerraformInit"
Write-Debug "RunTerraformPlan: $RunTerraformPlan"
Write-Debug "RunTerraformPlanDestroy: $RunTerraformPlanDestroy"
Write-Debug "RunTerraformApply: $RunTerraformApply"
Write-Debug "RunTerraformDestroy: $RunTerraformDestroy"
Write-Debug "DebugMode: $DebugMode"
Write-Debug "DeletePlanFiles: $DeletePlanFiles"

if ($RunTerraformPlan -eq $true -and $RunTerraformPlanDestroy -eq $true) {
    Write-Error "Error: Both Terraform Plan and Terraform Plan Destroy cannot be true at the same time"
    exit 1
}

if ($RunTerraformApply -eq $true -and $RunTerraformDestroy -eq $true) {
    Write-Error "Error: Both Terraform Apply and Terraform Destroy cannot be true at the same time"
    exit 1
}

if ($RunTerraformPlan -eq $false -and $RunTerraformApply -eq $true) {
    Write-Error "Error: You must run terraform plan and terraform apply together to use this script"
    exit 1
}

if ($RunTerraformPlanDestroy -eq $false -and $RunTerraformDestroy -eq $true) {
    Write-Error "Error: You must run terraform plan destroy and terraform destroy together to use this script"
    exit 1
}

# Change to the specified working directory
try {
    $CurrentWorkingDirectory = (Get-Location).path
    Set-Location -Path $WorkingDirectory
}
catch {
    Write-Error "Error: Unable to change to directory: $WorkingDirectory" -ForegroundColor Red
    exit 1
}

function Run-TerraformInit {
    if ($RunTerraformInit -eq $true) {
        try {
            Write-Host "Info: Running Terraform init in $WorkingDirectory" -ForegroundColor Green

            # Construct the backend config parameters
            $backendConfigParams = @(
                "-backend-config=subscription_id=$BackendStorageSubscriptionId",
                "-backend-config=resource_group_name=$BackendStorageResourceGroupName",
                "-backend-config=storage_account_name=$BackendStorageAccountName",
                "-backend-config=container_name=$BackendStorageAccountBlobContainerName",
                "-backend-config=key=$TerraformStateName"
            )

            # Run terraform init with the constructed parameters
            terraform init @backendConfigParams | Out-Host
            return $true
        }
        catch {
            Write-Error "Error: Terraform init failed" -ForegroundColor Red
            return $false
        }
    }
}

# Function to execute Terraform plan
function Run-TerraformPlan {
    if ($RunTerraformPlan -eq $true) {
        Write-Host "Info: Running Terraform Plan in $WorkingDirectory" -ForegroundColor Green
        terraform plan -out tfplan.plan | Out-Host
        if (Test-Path tfplan.plan) {
            terraform show -json tfplan.plan | Tee-Object -FilePath tfplan.json | Out-Null
            return $true
        }
        else {
            Write-Host "Error: Terraform plan file not created"
            return $false
        }
    }
    return $false
}

# Function to execute Terraform plan for destroy
function Run-TerraformPlanDestroy {
    if ($RunTerraformPlanDestroy -eq $true) {
        try {
            Write-Host "Info: Running Terraform Plan Destroy in $WorkingDirectory" -ForegroundColor Yellow
            terraform plan -destroy -out tfplan.plan
            if (Test-Path tfplan.plan) {
                terraform show -json tfplan.plan | Tee-Object -FilePath tfplan.json | Out-Null
                return $true
            }
            else {
                Write-Error "Error: Terraform plan file not created"
                return $false
            }
        }
        catch {
            Write-Error "Error: Terraform Plan Destroy failed"
            return $false
        }
    }
    return $false
}

# Function to execute Terraform apply
function Run-TerraformApply {
    if ($RunTerraformApply -eq $true) {
        try {
            Write-Host "Info: Running Terraform Apply in $WorkingDirectory" -ForegroundColor Yellow
            if (Test-Path tfplan.plan) {
                terraform apply -auto-approve tfplan.plan | Out-Host
                return $true
            }
            else {
                Write-Error "Error: Terraform plan file not present for terraform apply"
                return $false
            }
        }
        catch {
            Write-Error "Error: Terraform Apply failed"
            return $false
        }
    }
    return $false
}

# Function to execute Terraform destroy
function Run-TerraformDestroy {
    if ($RunTerraformDestroy -eq $true) {
        try {
            Write-Host "Info: Running Terraform Destroy in $WorkingDirectory" -ForegroundColor Yellow
            if (Test-Path tfplan.plan) {
                terraform apply -auto-approve tfplan.plan | Out-Host
                return $true
            }
            else {
                Write-Error "Error: Terraform plan file not present for terraform destroy"
                return $false
            }
        }
        catch {
            Write-Error "Error: Terraform Destroy failed"
            return $false
        }
    }
    return $false
}

# Execution flow
if (Run-TerraformInit) {
    $planSuccess = Run-TerraformPlan
    $planDestroySuccess = Run-TerraformPlanDestroy

    if ($planSuccess -and $RunTerraformApply -eq $true) {
        Run-TerraformApply
    }

    if ($planDestroySuccess -and $RunTerraformDestroy -eq $true) {
        Run-TerraformDestroy
    }
}

if ($DeletePlanFiles -eq $true) {
    $planFile = "tfplan.plan"
    if (Test-Path $planFile) {
        Remove-Item -Path $planFile -Force -ErrorAction Stop
        Write-Debug "Deleted $planFile"
    }
    $planJson = "tfplan.json"
    if (Test-Path $planJson) {
        Remove-Item -Path $planJson -Force -ErrorAction Stop
        Write-Debug "Deleted $planJson"
    }
}

Set-Location $CurrentWorkingDirectory
