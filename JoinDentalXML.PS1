cd ./Dental-xml

Get-ChildItem ./Dental-xml*.zip | % {Expand-Archive $_ -verbose}

# Wichtig: durch das Zippen und jetzt wieder entpacken, liegen die xml-Dateien in einzelnen Unterverzeichnissen!

# nun die *-dental.xml-Dateien in ein gemeinsames Objekt einlesen
$startTime = Get-Date

$files=Get-ChildItem *-dental.xml -recurse | Sort-Object name
# $files=Get-Childitem FULLDownload_Part142_Of_144_2022-10-01-dental.xml -recurse
#$x = $files | Select-Object -First 3 | ForEach-Object {
$x = $files | ForEach-Object {
        $xml = [xml](Get-Content $_.Fullname -encoding UTF8)
        Write-Host "$($_.Name) Anzahl: $($xml.devices.device.Count)"
        $xml.devices.device 
}
(Get-Date) - $startTime   # 2021: dauert ca. 20 Minuten!
""
"Anzahl Dental Devices: $($x.Length)"

"========================"
$x[0]
"------------------------"
$x[-1]
"========================"

"Export in Gudid-Dental.xml"
$startTime = Get-Date
$x |Export-Clixml -Depth 5 ./Gudid-Dental.xml
(Get-Date) - $startTime
