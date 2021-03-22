##### Local Device Account Creation Script v1
#### Created By Oliver Norton for Mangano IT
#### See MIT IT Glue Article: https://mits.itglue.com/797747/docs/7084733

### Check for required modules
### Az Module
if ((Get-Module -ListAvailable -Name Az.KeyVault) -and (Get-Module -ListAvailable -Name Az.Accounts)){
    Write-Host "Found Az module."
} else {
    Write-Host "Missing Az module. Installing now."
    Install-Module -Name Az -AllowClobber
    Write-Host "Az module installation complete."
}
### PowerShell PnP Module
if(Get-Module -ListAvailable -Name PnP.PowerShell){
    Write-Host "Found Powershell PnP module."
} else {
    Write-Host "Missing PowerShell PnP module. Installing now."
    Install-Module -Name PnP.PowerShell
    Write-Host "PowerShell PnP module installation complete."
}

### Prompt for Azure authentication
### Use adm.firstname.lastname@manganoit.com.au account
Connect-AzAccount

### Prompt for SharePoint authentication
### Use adm.firstname.lastname@manganoit.com.au account
Connect-PnPOnline -Url "https://manganoit.sharepoint.com/sites/MITInternalSystems/" -Interactive

### Get required details to complete account creation
$CompanyCode = Read-Host 'Please enter the 3 letter site code'

### IT Glue Local Device Account Script Reference
$ListName = "IT Glue Local Device Account Script Reference"

$items = $(Get-PnPListItem -List $ListName -Fields "Title", "organization_x002d_id", "PasswordFolderID").fieldValues

foreach ($item in $items) {
    if ($item.Title -eq $CompanyCode) {
        Write-Output "Found $($CompanyCode) within the IT Glue Device Account Script Reference SharePoint List."
        $ITGlueOrganisationID = $item.organization_x002d_id
        $ITGluePasswordFolderID = $item.PasswordFolderID
    }
}

### DinoPass Strong Password API URL
$DinoPassURL = "https://www.dinopass.com/password/strong"

### Get Password via DinoPass API
$Password = Invoke-RestMethod -Uri $DinoPassURL

### Convert password to secure string
$SecurePassword = $Password | ConvertTo-SecureString -AsPlainText -Force

### Create Local Device User
try {
    New-LocalUser -Name "$CompanyCode.LocalDevice" -AccountNeverExpires -Description "Local Device Account" -FullName "$CompanyCode Local Device" -Password $SecurePassword -PasswordNeverExpires
    ### Check For Local User & Add to Administrators Group
    $CheckUser = try {
        Get-LocalUser -Name "$CompanyCode.LocalDevice"
        Add-LocalGroupMember -Group "Administrators" -Member "$CompanyCode.LocalDevice"
    }
    catch {
        Write-Host "Can't find $CompanyCode.LocalDevice. Creation failed. Please try again."
        Exit
    }
    ### Check Enabled
    if($CheckUser.Enabled){
        Write-Host "$CompanyCode.LocalDevice successfully created and enabled."
        $UserCreated = 'true'
    } else {
        Write-Host "$CompanyCode.LocalDevice successfully created but is disabled. Password likely didn't meet complexity. Please delete account and try again."
        $UserCreated = 'false'
        Exit
    }
}
catch {
    Write-Host "Failed to create $CompanyCode.LocalDevice account. Please try again."
}

### Get Serial Number
$PCDetails = Get-WmiObject win32_bios

### Get IT Glue API Key from Azure Key Vault
$APIKey = Get-AzKeyVaultSecret -VaultName 'MIT-AZU1-PROD1-AKV1' -Name 'ITGlueAPIKey' -AsPlainText

### Enter Password to IT Glue
$ITGlueURL = "https://api.itglue.com/"
$ITGlueOrganisationURL = "organizations/$ITGlueOrganisationID/"
$ITGlueOrganisationPasswordURL = "relationships/passwords"
$ITGlueJSONRequest = @"
{
    "data" : {
        "type": "passwords",
        "attributes": {
            "name": "Local Device Account - $env:computername",
            "username": "$CompanyCode.LocalDevice",
            "password": "$Password",
            "notes": "Device Serial Number: $($PCDetails.Serialnumber)",
            "password-folder-id": $ITGluePasswordFolderID
        }
    }
}
"@

### Prepare Params for API Call
$params = @{
    Uri = $ITGlueURL+$ITGlueOrganisationURL+$ITGlueOrganisationPasswordURL
    Headers = @{"x-api-key" = $APIKey}
    Method = 'POST'
    Body = $ITGlueJSONRequest
    ContentType = 'application/vnd.api+json'
}

### Run API Call
if ($UserCreated -eq 'true') {
    try {
        Invoke-RestMethod @params
        "Details successfully added to IT Glue. Find Local Device Account - $env:computername under the Local Device Accounts folder for $CompanyCode."
    } catch {
        Write-Host "Adding Password to IT Glue failed. The password for $CompanyCode.LocalDevice is $Password. Please manually add."
    }
}