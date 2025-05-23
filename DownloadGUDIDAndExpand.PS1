# GUDID downloaden
# TODO Artefakte nicht hochladen, sondern direkt mittels
# git config --global user.name 'My Name'
# git config --global user.email 'my-name@gmail.com'
# git add
# git commit
# git push
# direkt ins Repository hochladen
# oder direkt in YAML:
#    - name: git
#      run: |
#        # setup the username and email. I tend to use 'GitHub Actions Bot' with no email by default
#        git --version
#        git config user.name "GitHub Actions Bot"
#        git config user.email "<>"
#        git status
#        git tag
#        git describe
# usw.

# Import-Module BitsTransfer  # geht nur unter Windows!

"Namen ermitteln"
# aktuellen Link aus RSS-Feed ermitteln https://accessgudid.nlm.nih.gov/download.rss?files=full
[xml]$res=Invoke-WebRequest -Uri https://accessgudid.nlm.nih.gov/download.rss?files=full -UseBasicParsing
$name=$res.rss.channel.Item.title.replace('.zip','')

"Download GUDID Database"
Invoke-WebRequest "https://accessgudid.nlm.nih.gov/release_files/download/$($Name).zip" -OutFile "./$($Name).zip"
"Expand GUDID Database $Name"
Expand-Archive "./$($Name).zip"
"Download FDI FoiClass"
Invoke-WebRequest http://www.accessdata.fda.gov/premarket/ftparea/foiclass.zip -OutFile ./foiclass.zip
"Expand FDI FoiClass"
Expand-Archive ./foiclass.zip

$foi=Import-Csv -Path ./foiclass/foiclass.txt -Delimiter '|'
$dental = $foi| Where-Object medicalspecialty -eq DE
$deProdCode = $dental | Select-Object -ExpandProperty ProductCode
$deProdCodeAnzahl = $deProdCode.Length

Function New-DevicesXMLDocument {

        $newxml=[xml]@"
<?xml version="1.0" encoding="UTF-8"?>
"@
        $devices=$newxml.CreateElement('devices')
        $newxml.AppendChild($devices) |Out-Null
        $newxml
}

# nun aus der GUDID-Datenbank die gesuchten Einträge herausholen
# https://www.fda.gov/medical-devices/global-unique-device-identification-database-gudid/gudid-guidance

cd "./$($Name)"

$Slice="*Part$($env:Slice)?_*.xml"
"Durchlaufe: $Slice"

$startTime = Get-Date
# zunächst alle XML-Dateien durchgehen und Dentalprodukte ermitteln, diese werden in eine *-dental.xml-Datei geschrieben
$files=Get-ChildItem $Slice -Exclude *-dental.xml|Sort-Object name
# $x= $files | Select-Object -first 4 | ForEach-Object {
$x= $files  | ForEach-Object {
        Write-Host "Reading $($_.Fullname)"
        $xml = [xml](Get-Content $_.Fullname -encoding UTF8)
        Write-Host "Selecting Dental"
        # $xr = $xml.gudid.device| Where-Object { $_.productCodes.fdaProductCode.productCodeName -match 'Dental' }
        # durch die Compare-Object-Methode findet man auch mehrere productCodes, die einem Device zugeordnet sind!
        $xr = $xml.gudid.device| Where-Object { $code=$_.productCodes.fdaProductCode.productCode; If ($null -eq $code) {$false} else { If ($code -isnot [array]) {$deProdCode -contains $code} else { (Compare-Object -ReferenceObject $deProdCode -DifferenceObject ($_.productCodes.fdaProductCode.productCode) -PassThru).Length -lt $deProdCodeAnzahl}} }
        Write-Host "gefunden: $($xr.Length) von $($xml.gudid.device.Count)"
        # die ermittelten Dental-XML-Nodes speichern
        # alte Methode: $xr |Export-Clixml -Depth 100 -Path $_.FullName.Replace('.xml', '-dental.xml')
        $newxml = New-DevicesXMLDocument
        $devices = $newxml.GetElementsByTagName('devices')
        $xr | % { $import=$newxml.ImportNode($_, $true); $devices.AppendChild($import) | Out-Null }
        $newxml.Save($_.FullName.Replace('.xml', '-dental.xml'))
}
"Verarbeitungszeit: $((Get-Date) - $startTime)"
$x.Length

