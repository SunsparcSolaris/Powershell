#Only two examples are going to be listed. If you have more "Office OUs", you will need to add more logic.

function Get-OfficeOU {
    param(
        [string]
        $office,

        [string]
        $depart
    )

#TX.Houston
if ($office -like "*Houston*") {
    $site = "TX.Houston"
    $div = ""
}
#FL.Miami
elseif ($office -like "*Miami*") {
    $site = "FL.Miami"
    if ($depart -like "Finance") {
        $div = "/FIN"
    }
    if ($depart -like "Administration") {
        $div = "/ADM"
    }
}
else {
    Write-Host "No matching office found!"
}

$global:ou = $site+$div
$global:ou
}
