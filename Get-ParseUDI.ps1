# Beispiele:
# .\Get-ParseUDI.ps1 -UDI '(01)00208851107345(17)150331'
# $parsed=.\get-parseudi.ps1 '+DVIV572812AN1/$XL2389/16D20190517/14D20210830Y'
# $parsed

Param([string]$Udi,[ValidateSet('Xml', 'Json')][string]$Format='Xml')

# obwohl V3 existiert, muss hier V2 angegeben werden!
If ($Format -eq 'xml') {
	$url = 'https://accessgudid.nlm.nih.gov/api/v2/parse_udi.xml'
} else {
	If ($Format -eq 'json') {
		$url = 'https://accessgudid.nlm.nih.gov/api/v2/parse_udi.json'
	} else {
		throw 'Unbekanntes Format!'
	}
}

# wichtig nicht EscapeURIString sondern EscapeDataString:
$request = "$($url)?udi=$([URI]::EscapeDataString($Udi))"
# Write-Host $request
$resp = Invoke-WebRequest $request
If ($resp.StatusCode -eq 200) {
	If ($Format -eq 'xml') {
		  ([xml]$resp.Content).result
	} else {
		[JsonObject]$resp.Content
	}
}
