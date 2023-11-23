cd ./Dental-xml

Get-ChildItem ./Dental-xml*.zip | % {Expand-Archive $_ -verbose}

# Wichtig: durch das Zippen und jetzt wieder entpacken, liegen die xml-Dateien in einzelnen Unterverzeichnissen!

# nun die *-dental.xml-Dateien in ein gemeinsames Objekt einlesen
$startTime = Get-Date

$files=Get-ChildItem *-dental.xml -recurse | Sort-Object name
# $files=Get-Childitem FULLDownload_Part142_Of_144_2022-10-01-dental.xml -recurse
$index=1
@'
<?xml version="1.0" encoding="UTF-8"?>
<devices>
'@ | Set-Content ./Gudid-Dental.xml

#$x = $files | Select-Object -First 3 | ForEach-Object {
$files | ForEach-Object {
        "$($Index). verarbeite: $($_.Name)"
        $Index++
        $c = (Get-Content $_.Fullname -encoding UTF8)
        $c[2..($c.length-2)]|Add-content ./Gudid-Dental.xml
        (Get-Date) - $startTime
        $startTime = Get-Date
        # geht nicht: Write-Host "$($_.Name) Anzahl: $($xml.devices.device.Count)"
        # $xml.devices.device 
}

@'

</devices>
'@ | Add-Content .\Gudid-Dental.xml

#$startTime = Get-Date
#"Start einlesen: $StartTime"
#$x=[xml](Get-Content ./Gudid-Dental.xml)
#(Get-Date) - $startTime
#"Devices: $($x.Length)"
