cd ./dental-Xml

Expand-Archive *Dental-xml -verbose

# nun die *-dental.xml-Dateien in ein gemeinsames Objekt einlesen
$startTime = Get-Date
$files=Get-ChildItem *-dental.xml | Sort-Object name
#$x = $files | Select-Object -First 3 | ForEach-Object {
$x = $files | ForEach-Object {
        $xml = [xml](Get-Content $_.Fullname -encoding UTF8)
        Write-Host "$($_.Name) Anzahl: $($xml.devices.device.Count)"
        $xml.devices.device 
}
(Get-Date) - $startTime   # 2021: dauert ca. 20 Minuten!
""
"Anzahl Dental Devices: $($x.Length)"
