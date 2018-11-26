#Import custom PSM files
Import-Module -Name "C:\scripts\Get-CanonicalName.psm1"
Import-Module -Name "C:\scripts\Choose-ADOU.psm1" 3>$null
Import-Module -Name "C:\scripts\Get-SDRequest.psm1"
Import-Module -Name "C:\scripts\Get-OfficeOU.psm1"

#Gather migration (o365) and directory sync (Azure AD Connect) credentials
$dircreds = "\\exchange.contoso.com\c$\scripts\"+$env:username.substring(0,2).ToUpper()+"dirsynccreds.xml"
$dircreds = import-clixml $dircreds
$migcreds = "\\exchange.contoso.com\c$\scripts\"+$env:username.substring(0,2).ToUpper()+"Migcreds.xml"
$migcreds = import-clixml $migcreds

#Set admin user that is running script
$currentuser = $env:username.split(".")[0]
Write-Host "Current user: $currentuser"
$apikey = Get-Content -Path "C:\scripts\sdapikeys\$currentuser.txt"
Write-Host "User API key: $apikey"

#Capture ServiceDesk ticket number
$requestID = Read-Host "Please enter the ServiceDesk onboard ticket number"

#Send request to ServiceDesk for ticket information
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$data = get-request -SdpUri "https://servicedesk.contoso.com" -ApiKey $apikey -RequestID $requestID

#Do some creplace so that we can work with the data pulled from ServiceDesk
$datacorrected = $data -creplace '"DEPARTMENT":','"Requester_Department":'
$datacorrected = $datacorrected -creplace '"Employee Middle Initial":','"EmployeeMiddleInitial":'
$datacorrected = $datacorrected -creplace '"Employee First Name":','"EmployeeFirstName":'
$datacorrected = $datacorrected -creplace '"Employee Last Name":','"EmployeeLastName":'
$datacorrected = $datacorrected -creplace '"Job Title":','"JobTitle":'
$datacorrected = $datacorrected -creplace '"Employee ID":','"EmployeeID":'
$datacorrected = $datacorrected -creplace '"SUBJECT":','"Subject":'
$datacorrected = $datacorrected -creplace '"Manager":','"UserManager":'
$datacorrected = $datacorrected -creplace '"Start Date":','"StartDate":'
$datacorrected = $datacorrected -creplace '"Office":','"Office":'
$servicedesk = $datacorrected | convertfrom-json -ErrorAction SilentlyContinue
$subject = $servicedesk.SUBJECT

#Check to see if the ticket is actually an onboarding ticket
if ($subject -notlike "*Employee On*") {
    Write-Host "This does not appear to be an on-boarding ticket. Please verify and try again." -foregroundcolor "Red"
} else {
    Write-Host "`n Subject:"$servicedesk.Subject
    Write-Host "This looks like an on-boarding ticket. Importing employee information..." -ForegroundColor "Green"

}
#Convert variables from ServiceDesk API request to more readable ones
$firstname = $servicedesk.EmployeeFirstName
$middleinitial = $servicedesk.EmployeeMiddleInitial
$lastname = $servicedesk.EmployeeLastName
$title = $servicedesk.JobTitle
$global:depart = $servicedesk.Department
$employeeID = $servicedesk.EmployeeID
$manager = $servicedesk.UserManager
$global:office = $servicedesk.Office
$startdate = $servicedesk.StartDate.split(",")[0] | get-date -UFormat "%m%d"
$password = "Todayis_"+$startdate
$manageraccount = Get-ADUser -searchbase "DC=corp,DC=contoso,DC=com" -Filter {name -like $manager} -Properties name,samaccountname | select -expandproperty samaccountname

$unameFirst = $firstname
$unameMiddle = $middleinitial
$unameLast = $lastname

#Convert names to lowercase
$unamefirst = $unameFirst.ToLower()
if ($unameMiddle) {
    $unameMiddle = $unameMiddle.ToLower()
    $unameMiddle = $unameMiddle.SubString(0,1)
    }
$unameLast = $unameLast.ToLower()

#Select next available username based on first,middle,last name. This is checked against AD and loops around if it exists.
$count = 1
while (!$check) {
    if ($count -gt $unameFirst.Length) {
        Write-Host "Search limit exceeded!"
        break
    }

    if (!$unameMiddle) {
        $possibleName = $unameFirst.Substring(0,$count)+$unameLast
    }
    else {
        $possibleName = $unameFirst.Substring(0,$count)+$unameMiddle+$unameLast
    }
    
    try {
    $namecheck = get-aduser -filter {samaccountname -like $possibleName}
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]
    { }
    if ($namecheck.Enabled -eq $true) {
        $count++
    }
    else {
        $check = $true
        $username = $possibleName
    }
}

#Connect to on-prem Exchange
$session = new-pssession -configurationname microsoft.exchange -connectionuri http://exchange.contoso.com/Powershell -authentication kerberos
import-pssession $session 3>$null

#Create the password secure string
$password = convertto-securestring -string $password -asplaintext -force

#Use the Get-OfficeOU PSM logic to figure out which OU will be in and set the OU
$ouname = Get-OfficeOU -office $office -depart $depart
$ouname = "CORP.contoso.com/"+$ouname+"/Users"

#Write out a switch menu that will allow you to select fields for editing, if they were not properly importing or changes need to be made.
#Pay close attention to the Org Unit field.
while (!$switchcheck) {
Write-Host "`n`n"
Write-Host "1: First Name: $firstname"
Write-host "2: Middle Initial: $middleinitial"
Write-host "3: Last Name: $lastname"
Write-Host "4: Username: $username"
Write-Host "5: Title: $title"
Write-Host "6: Department: $depart"
Write-Host "7: Employee ID: $employeeID"
Write-Host "8: Manager: $manager"
Write-Host "9: Org Unit: $ouname"
Write-Host "`n"

$selection = Read-Host "Please select which field to update. Type CREATE to proceed with user creation"
switch ($selection) {
    "1" {$firstname = Read-Host "Input new first name"; Write-Host "First name updated to $firstname"}
    "2" {$middleinitial = Read-Host "Input new middle initial"; Write-Host "Middle initial updated to $middleinitial"}
    "3" {$lastname = Read-host "Input new last name"; Write-Host "Last Name updated to $lastname"}
    "4" {$username = Read-Host "Input new username"; Write-Host "Username updated to $username"}
    "5" {$title = Read-Host "Input new title"; Write-Host "Title updated to $title"}
    "6" {$depart = Read-Host "Input new department"; Write-Host "Department updated to $depart"}
    "7" {$employeeID = Read-Host "Input new employee ID"; Write-Host "Employee ID updated to $employeeID"}
    "8" {$manager = Read-Host "Input new manager username"; $manager = get-aduser $manager -properties displayname | select -expandproperty displayname; Write-Host "Manager updated to $manager"}
    "9" {$ou = Choose-adorganizationalunit; $distinguishedname = $ou.distinguishedname; $ouname = Get-CanonicalName $distinguishedname; Write-Host "Org Unit updated to $ouname"}
    "CREATE" {$createverify = $true; $switchcheck = $true}

}
}

if ($createverify -ne $true) {
Write-Host "User creation aborted, please run script again." -foregroundcolor "Red" -backgroundcolor "Black"
Write-Host 'Press any key to close this window....';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
exit
}

#Form the DisplayName, Username, and UserPrincipalName
if ($middleinitial) {
$displayname = $firstname+" "+$middleinitial+" "+$lastname
} 
else {
$displayname = $firstname + " " + $lastname
}
$upn = $username + "@contoso.com"

#Create the on-prem and o365 mailboxes with the desired information
Write-Host "Creating mailbox on-prem and in o365"
new-remotemailbox -name $displayname -firstname $firstname -lastname $lastname -onpremisesorganizationalunit $ouname -userprincipalname $upn -password $password -resetpasswordonnextlogon:$false

remove-pssession $session
Write-Host "Exchange session disconnected"

#Initiate manual Directory Sync
Write-Host "Initiating manual directory sync"
Invoke-Command -ComputerName "dirsync.contoso.com" -ScriptBlock {C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -command "Start-ADSyncSyncCycle -PolicyType Delta"} -Credential $dircreds

#Connect to o365 to run OWA/ActiveSync disables
Write-Host "Connecting to o365..."
$ex = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell -Credential $migcreds -Authentication basic -AllowRedirection
Import-PSSession $ex 3>$null
Connect-MsolService -Credential $migcreds

$check = Get-MsolUser -userprincipalname $upn -erroraction silentlycontinue

#Wait for the user mailbox to show up in o365, meaning sync is complete.
while (!$check) {
$date = (get-date -format "g")
$check = Get-MsolUser -userprincipalname $upn -erroraction silentlycontinue
Write-Host "$date Waiting for account to sync, checking again in 60 seconds..."
start-sleep -seconds 60
}

Write-Host "User account synced"

#disable OWA/ Exchange ActiveSync
$emailaddress = Get-ADUser -Identity $username -Properties EmailAddress | %{(Get-AdUser $username -Properties EmailAddress).EmailAddress}
$check = get-casmailbox $emailaddress 3>$null

#Wait for confirmation that OWA and ActiveSync are disabled
while (!$check){
Write-Host "$date Disabling OWA for Devices and ActiveSync, please wait...."
$check = get-casmailbox $emailaddress 3>$null
Start-Sleep -s 30
}
Set-CASMailbox -Identity $emailaddress -OWAforDevicesEnabled $False 
Set-CASMailbox -Identity $emailaddress -ActiveSyncEnabled $False

#Assign o365 licenses
$licensestatus = get-msoluser -userprincipalname $username@contoso.com | select userprincipalname,islicensed,licenses
while ($licensestatus.isLicensed -eq $False) {
Write-Host "Assigning o365 licenses, please wait...."
set-msoluser -userprincipalname $username@contoso.com -usagelocation US
set-msoluserlicense -UserPrincipalName $username@contoso.com -Addlicenses contoso:ENTERPRISEPACK
$disabledLicenses = New-MsolLicenseOptions -AccountSkuId "contoso:EMS" -DisabledPlans "MFA_PREMIUM"
Set-MsolUserLicense -UserPrincipalName $username@contoso.com -Addlicenses contoso:EMS
Set-MsolUserLicense -UserPrincipalName $username@contoso.com -licenseoptions $disabledlicenses
start-sleep -seconds 30
$licensestatus = get-msoluser -userprincipalname $username@contoso.com | select userprincipalname,islicensed,licenses
}
remove-pssession $ex
Write-Host "o365 disconnected"

#Set additional AD attributes
Write-Host "Setting additional AD attributes"
set-aduser $username -Company "Contoso"
set-aduser $username -HomePage "www.contoso.com" 
set-aduser $username -employeeID $employeeid
set-aduser $username -department $depart
set-aduser $username -title $title
set-aduser $username -description $title
set-aduser $username -manager $manageraccount

Write-Host "Completed"

Write-Host 'Press any key to close this window....';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');

