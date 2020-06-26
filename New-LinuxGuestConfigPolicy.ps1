<#
    .DESCRIPTION
    Use this script to gain an understanding about how packages are created. Run it line by line to understand what happens behind the scenes.
    The script is based on commands found at https://docs.microsoft.com/en-us/azure/governance/policy/how-to/guest-configuration-create

    Before you start, make sure you have the following folder structure set up:
    / New-LinuxGuestConfigPolicy.ps1
    / AuditLinuxCronjob / AuditLinuxCronjob.ps1
    
    By the end of the script, you should have the following folder structure:
    / New-LinuxGuestConfigPolicy.ps1
    / AuditLinuxCronjob / AuditLinuxCronjob.ps1

    / AuditLinuxCronjob / CompiledPolicy / AuditLinuxCronjob.mof
    / AuditLinuxCronjob / Package / AuditLinuxCronjob / AuditLinuxCronjob.zip
    / AuditLinuxCronjob / Package / AuditLinuxCronjob / unzippedPackage / AuditLinuxCronjob.mof
    / AuditLinuxCronjob / Package / AuditLinuxCronjob / unzippedPackage / Modules / **
    / AuditLinuxCronjob / PolicyDefinitions / AuditIfNotExists.json
    / AuditLinuxCronjob / PolicyDefinitions / DeployIfNotExists.json
    / AuditLinuxCronjob / PolicyDefinitions / Initiative.json
#>

# Before you start, make sure your terminal is in the directory of the script, the GuestConfigPolicyWithParams folder
# Install the Guest Configuration module. I've tested this demo on 1.19.4
Install-Module -Name GuestConfiguration -RequiredVersion 1.19.4

# Run AuditLinuxCronjob.ps1 first. You will now get the MOF file in AuditLinuxCronjob/CompiledPolicy directory
.\AuditLinuxCronjob\AuditLinuxCronjob.ps1

# The following cmdlet will create the policy package in the AuditLinuxCronjob/Package folder. It will create the AuditLinuxCronjob.zip file and also the unzippedPackage folder
New-GuestConfigurationPackage `
    -Name 'AuditLinuxCronjob' `
    -Configuration './AuditLinuxCronjob/CompiledPolicy/AuditLinuxCronjob.mof' `
    -Path './AuditLinuxCronjob/Package' `
    -ChefInspecProfilePath ./

# We can now test the package to ensure it's valid. Run this on the same type of machine as the policy target machine
Test-GuestConfigurationPackage `
    -Path './AuditLinuxCronjob/Package/AuditLinuxCronjob/AuditLinuxCronjob.zip' 

# Now we need to upload the package to a Storage Account. We use the Publish-GuestConfigurationPackage function to accomplish this
function Publish-GuestConfigPolicyPackageToStorage {
    <#
    .DESCRIPTION
    Uploads the Guest Configuration policy to Azure Storage

    Source: https://docs.microsoft.com/en-us/azure/governance/policy/how-to/guest-configuration-create
    #>

    param(
    [Parameter(Mandatory=$true)]
    $resourceGroup,
    [Parameter(Mandatory=$true)]
    $storageAccountName,
    [Parameter(Mandatory=$true)]
    $storageContainerName,
    [Parameter(Mandatory=$true)]
    $filePath,
    [Parameter(Mandatory=$true)]
    $blobName
    )

    # Get Storage Context
    $Context = Get-AzStorageAccount -ResourceGroupName $resourceGroup `
        -Name $storageAccountName | `
        ForEach-Object { $_.Context }

    # Upload file
    $Blob = Set-AzStorageBlobContent -Context $Context `
        -Container $storageContainerName `
        -File $filePath `
        -Blob $blobName `
        -Force

    # Get url with SAS token
    $StartTime = (Get-Date)
    $ExpiryTime = $StartTime.AddYears('3')  # THREE YEAR EXPIRATION
    $SAS = New-AzStorageBlobSASToken -Context $Context `
        -Container $storageContainerName `
        -Blob $blobName `
        -StartTime $StartTime `
        -ExpiryTime $ExpiryTime `
        -Permission rl `
        -FullUri

    # Output
    return $SAS
}

<# Set these variables to a valid storage account or run the 5 lines of code to randomly generate a storage account name
    $random = Get-Random -Minimum 10 -Maximum 1000
    $storageAccountName = "guestconfigdemo$random"
    $resourceGroupName = "guestconfigdemo$random"
    $containerName = "policies"
    $location = "westeurope"
#>

# Create a Resource Group to store the Storage Account
if (!(Get-AzResourceGroup -Name $resourceGroupName -Location $location -ErrorAction SilentlyContinue)) {
    Write-Host "Resource Group '$($resourceGroupName)' does not exist in location '$($location)'. Creating now..."
    New-AzResourceGroup -Name $resourceGroupName -Location $location
}

# Create a Storage Account
# The storage account won't have any default allow permissions as we will use SAS tokens to provide the permissions
if (!(Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName  -ErrorAction SilentlyContinue)) {
    $storageAccount = New-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -SkuName Standard_LRS -Location $location -Kind StorageV2

    # Set Storage Account Contributor permissions so that we can create containers and blobs
    New-AzRoleAssignment -SignInName $(Get-AzContext).Account -RoleDefinitionName "Storage Blob Data Contributor" -Scope $storageAccount.Id

    # Create the container to store the policy package
    $storageAccount | New-AzStorageContainer -Name $containerName -Permission Off
}

# Upload the policy package to Azure Storage
$uri = $null
$uri = Publish-GuestConfigPolicyPackageToStorage `
    -resourceGroup $resourceGroupName `
    -storageAccountName $storageAccountName `
    -storageContainerName $containerName `
    -filePath ./AuditLinuxCronjob/Package/AuditLinuxCronjob/AuditLinuxCronjob.zip `
    -blobName 'AuditLinuxCronjob'

# Test if the URI works
if ((Invoke-WebRequest $uri).Statuscode -ne 200) {
    throw "The URI does not seems to be correct. Please check the URI: $URI"
}

# Define the policy parameters that we want to add to the policy.
# As I like JSON, I'm importing the variables in JSON but you can also uncomment the array below
$policyParameters = Get-Content ./AuditLinuxCronjob/PolicyParameters.json | ConvertFrom-Json -AsHashtable

<#
$policyParameters = @(
    @{
        Name = ''                         # Policy parameter name (mandatory)
        DisplayName = ''                  # Policy parameter display name (mandatory)
        Description = ''                  # Policy parameter description (optional)
        ResourceType = ''                 # DSC configuration resource type (mandatory). Get this value from the AuditLinuxCronjob.ps1 file.
        ResourceId = ''                   # DSC configuration resource property name (mandatory). Get this value from the AuditLinuxCronjob.ps1 file.
        ResourcePropertyName = ''         # DSC configuration resource property name (mandatory). Get this value from the AuditLinuxCronjob.ps1 file.
        DefaultValue = ''                 # Policy parameter default value (optional)
    }
)
#>

# Create the Guest Configuration Policy
New-GuestConfigurationPolicy `
    -ContentUri $uri `
    -DisplayName 'Guest Configuration Demo - Audit Linux Cronjob' `
    -Description 'Audit if a Linux Cronjob is set.' `
    -Path './AuditLinuxCronjob/PolicyDefinitions' `
    -Platform 'Linux' `
    -Parameter $policyParameters `
    -Version 1.0.0 `
    -Verbose

# Publish the Guest Configuration Policy
Publish-GuestConfigurationPolicy -Path './AuditLinuxCronjob/PolicyDefinitions' -Verbose

# Display the Guest Configuration Policy
(Get-AzPolicyDefinition | Where-Object {$_.Properties.DisplayName -like "*Guest Configuration Demo - Audit Linux Cronjob"}).Properties

# If you want to update a Guest Configuration policy, it should work just fine. You can see that the metadata property changes when the policy is updated:
# createdOn=2020-06-24T09:25:43.0301822Z; updatedOn=2020-06-24T10:53:13.9929041Z
# Do make sure that the remediation tasks are updated / re-applied to ensure the latest policy package is available on the machine. Otherwise the Deploy Prereq policy will report non-compliant with a difference in package hash.

# Congratulations!
# The Guest Configuration Policy Definitions and Policy Definition Set should now be visible in the Azure Portal.
# You can test with it by creating a new Linux Virtual Machine and assigning the policy definition set to the Resource Group of the VM
# Open the README.md for more details

<# Cleanup the environment
    Remove-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName
    Remove-AzResourceGroup -Name $resourceGroupName
    Get-AzPolicySetDefinition | Where-Object {$_.Properties.DisplayName -like "*Guest Configuration Demo - Audit Linux Cronjob"} | Remove-AzPolicySetDefinition
    Get-AzPolicyDefinition | Where-Object {$_.Properties.DisplayName -like "*Guest Configuration Demo - Audit Linux Cronjob"} | Remove-AzPolicyDefinition
#>