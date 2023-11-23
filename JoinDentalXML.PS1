cd ./Dental-xml

Get-ChildItem ./Dental-xml*.zip | % {Expand-Archive $_ -verbose}

# Wichtig: durch das Zippen und jetzt wieder entpacken, liegen die xml-Dateien in einzelnen Unterverzeichnissen!

# nun die *-dental.xml-Dateien in ein gemeinsames Objekt einlesen
$startTime = Get-Date

$files=Get-ChildItem *-dental.xml -recurse | Sort-Object name
# $files=Get-Childitem FULLDownload_Part142_Of_144_2022-10-01-dental.xml -recurse
#$x = $files | Select-Object -First 3 | ForEach-Object {
$files | ForEach-Object {
        "Verarbeite: $($_.Name)"
        $c = (Get-Content $_.Fullname -encoding UTF8)
        $c[2..($c.length-2)]|Add-content .\Gudid-Dental.xml
        (Get-Date) - $startTime
        $startTime = Get-Date
        # geht nicht: Write-Host "$($_.Name) Anzahl: $($xml.devices.device.Count)"
        # $xml.devices.device 
}
# (Get-Date) - $startTime   # 2021: dauert ca. 20 Minuten! 2023 mit PS7.4: ca. 9 Minuten
""
# "Anzahl Dental Devices: $($x.Length)"   #2023: 500000 Devices

"======= Beispiel 1. und letztes Device =============="
# $x[0]
"------------------------"
# $x[-1]
"========================"

"Export in Gudid-Dental.xml"
$startTime = Get-Date
"Start-Zeit: $startTime"
$x |Export-Clixml -Depth 5 ./Gudid-Dental.xml
(Get-Date) - $startTime

