"Download FDI FoiClass"
Invoke-WebRequest http://www.accessdata.fda.gov/premarket/ftparea/foiclass.zip -OutFile ./foiclass.zip
"Expand FDI FoiClass"
Expand-Archive ./foiclass.zip -Verbose

dir

# https://www.fda.gov/medical-devices/classify-your-medical-device/download-product-code-classification-files
# http://www.accessdata.fda.gov/premarket/ftparea/foiclass.zip
$foi=Import-Csv -Path ./foiclass.txt -Delimiter '|'
$dental = $foi| Where-Object medicalspecialty -eq DE
$deProdCode = $dental | Select-Object -ExpandProperty ProductCode
$deProdCodeAnzahl = $deProdCode.Length

cd ./Dental-xml
Get-ChildItem ./Dental-xml*.zip | % {Expand-Archive $_ -verbose}

# nun die *-dental.xml-Dateien in ein gemeinsames Objekt einlesen
$startTime = Get-Date

$files=Get-ChildItem *-dental.xml -recurse | Sort-Object name
$index=1

$x = $files | ForEach-Object {
        $xml = [xml](Get-Content $_.Fullname -encoding UTF8)
        Write-Host "$($_.Name) Anzahl: $($xml.devices.device.Count)"
        $xml.devices.device 
}
(Get-Date) - $startTime   # 2021: dauert ca. 20 Minuten!
$x.Length
# Anzahl 2021: 417607

"Anzahl: $($x.Length))"
