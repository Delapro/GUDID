"Download FDI FoiClass"
Invoke-WebRequest http://www.accessdata.fda.gov/premarket/ftparea/foiclass.zip -OutFile ./foiclass.zip
"Expand FDI FoiClass"
Expand-Archive ./foiclass.zip -Verbose

# https://www.fda.gov/medical-devices/classify-your-medical-device/download-product-code-classification-files
# http://www.accessdata.fda.gov/premarket/ftparea/foiclass.zip
$foi=Import-Csv -Path ./foiclass/foiclass.txt -Delimiter '|'
$dental = $foi| Where-Object medicalspecialty -eq DE
$deProdCode = $dental | Select-Object -ExpandProperty ProductCode
$deProdCodeAnzahl = $deProdCode.Length

# benötigte Funktionen
Function New-GS1Checksum {
  Param(
      $gs1GTIN
  )

  # https://www.gs1us.org/tools/check-digit-calculator
  # https://www.gs1-germany.de/fileadmin/gs1/basis_informationen/die_pruefziffer_fuer_gtin_gln_und_nve.pdf
  $sum = 0
  $m3 = $true
  for ($i = $gs1GTIN.length-1; $i -ge 0; $i--) {
      $sum += ($gs1GTIN[$i]-48) * (&{If ($m3) {3} else {1}})
      $m3 = -not $m3
  }
  # auf Zehner aufrunden
  If ($sum%10 -eq 0) {
      '0'
  } else {
      10-$sum%10
  }
}

Function Test-GS1Checksum {
  Param(
      $gs1GTIN
  )

  $sum = 0
  $m3 = $false
  for ($i = $gs1GTIN.length-1; $i -ge 0; $i--) {
      $sum += ($gs1GTIN[$i]-48) * (&{If ($m3) {3} else {1}})
      $m3 = -not $m3
  }
  $sum%10 -eq 0 # Modulo 10 muss 0 ergeben
}
Function New-HIBCChecksum {
  Param(
    [String]$HIBC
  )

  $RefTable = @('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
                'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V',
                'W', 'X', 'Y', 'Z', '-', '.', ' ', '$', '/', '+', '%')

  $Sum = 0
  for ($i = 0; $i -lt $Hibc.Length; $i++) {
    $sum += $RefTable.IndexOf([String]$HIBC[$i])
  }
  $RefTable[$sum % 43]
}

Function Test-HIBCChecksum {
  Param(
    [String]$HIBC
  )

  $HIBC[-1] -eq (New-HIBCChecksum ($HIBC[0..($HIBC.Length-2)] -join ''))
}

"Entpacken"
cd ./Dental-xml
Get-ChildItem ./Dental-xml*.zip | % {Expand-Archive $_ -verbose}

"Auswerten"
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
# Anzahl 2021: 417607

"Anzahl: $($x.Length)"

# Suche nach bestimmter Catalognummer
$x|where catalognumber -eq '66017316'

# Statistik

"GS1 Barcodes"
$gs1=$x|? {$_.identifiers.identifier.deviceIdIssuingAgency -eq 'GS1'}
$gs1 | measure
# Count             : 2021: 241578    2020: 175529

# ungültige DI mit falscher Checksumme!
$gs1Prob=$x|? {$_.identifiers.identifier.deviceIdIssuingAgency -eq 'GS1' -and $_.identifiers.identifier.deviceIdType -eq 'Primary' -and $_.identifiers.identifier -isnot [array] -and  (-not (Test-GS1Checksum $_.identifiers.identifier.deviceID)) }

"HIBC Barcodes"
$x|? {$_.identifiers.identifier.deviceIdIssuingAgency -eq 'HIBCC'} | measure
# Count             : 2021: 184509     2020: 167147

"Verpackungen"
$x|? {$_.identifiers.identifier.deviceIdType -eq 'Package'} | measure
# Count             : 7248

"reale Produkte"
$x|? {$_.identifiers.identifier.deviceIdType -eq 'Primary'} | measure
# Count             : 336427

"GS1-Produkte mit Lot und Seriennummer"
$gs1|? {($_.lotbatch -eq $true) -and ($_.serialnumber -eq $true)} | measure
# Count             : 2021: 22636    2020: 19443

"GS1-Hersteller mit Lot und Seriennummer"
$gs1|? {($_.lotbatch -eq $true) -and ($_.serialnumber -eq $true)} | select companyname -Unique|measure
# Count             : 2021: 105       2020: 79

"um die DIs einer gs1 Firma zu erhalten:"
$gs1Company=$gs1| group -Property CompanyName
($gs1Company| where name -match straumann| select -ExpandProperty group).identifiers.identifier | select -first 5


"nicht mehr im Vertrieb"
$x| ? deviceCommDistributionStatus -ne 'In Commercial Distribution'|measure
# Count             : 11504

"Produkte mit mehr 1 Identifier"
$x|? {$_.identifiers.identifier.count -gt 1 }| measure
# Count             : 61825

"Produkte mit mehr 2 Identifier"
$x|? {$_.identifiers.identifier.count -gt 2 }| measure
# Count             : 4565

"Produkte mit mehr 3 Identifier"
$x|? {$_.identifiers.identifier.count -gt 3 }| measure
# Count             : 117

"Produkte mit mehr 4 Identifier"
$x|? {$_.identifiers.identifier.count -gt 4 }| measure
# Count             : 21

"Produkte mit mehr 5 Identifier"
$x|? {$_.identifiers.identifier.count -gt 5 }| measure
# Count             : 13


$h=$x| group companyName | measure -Property Count -Sum
"Hersteller: $($h.Count), mit insgesamt $($h.Sum) Produkten"

"Hersteller ausgeben"
$x | group companyname | select Name | select -first 5

"Ausgabe der Produktcodes"
$p= $x | select *, @{N='ProdCode';E={$_.productCodes.fdaProductCode.productCode}} | group -Property ProdCode
$codes=$p| select -ExpandProperty name
# da Codes mehrfach Nennungen enthalten können, diese nun entflechten:
$codeList=$codes | % {IF ($_.length -gt 3) {$_.split()} else {$_}}
# damit kann man nun wieder auf die Foi zurückgreifen:
$dental| where {$codeList -contains $_.productcode} | select medicalspecialty, productcode, devicename

"welche Firma bedient welchen Code?"
$p| % {New-Object PSObject -Property @{Code=$_.Name;Companies=($_.Group| select -ExpandProperty companyname -Unique) }}

"nur Codes ermitteln, wo bestimmte Companies drin vorkommen"
$cc=$p| % {New-Object PSObject -Property @{Code=$_.Name;Companies=($_.Group| select -ExpandProperty companyname -Unique) }}
$Zahnhersteller=$cc | ? { $c=($_.companies | % {$_|Out-String -Stream}); $c -match 'kulzer' -and $c -match 'bredent' -and $c -match 'candulor'} 

$Zähne = ($p|where Name -eq 'ELM').Group

"alle Zähne ausgeben"
$Zähne| select companyname,brandname,devicedescription,catalognumber

"alle Zähne eines bestimmten Herstellers ausgeben"
$Zähne|where companyname -match vita| select companyname,brandname,devicedescription,catalognumber

$Zahn=$Zähne|where catalognumber -eq '66017316'

# neben den FDA ProductCode (FDA PT-Code) gibt es noch die GMDN-Nomenklatur, allerdings taucht aus rechtlichen Gründen dort der GMDN-PT-Code nicht auf sondern nur der GMDN-PT-Name!
# FDA-PT-Code "ELM" entpsricht z. B. GMDN-PD-Name "DENTAL VENEER, CUSTOM-MADE"
# aber es gibt mehrere entsprechnungen von FDA nach GMDN:
# FDA-PT-Code "ELM" entpsricht auch GMDN-PD-Name "DENTAL CROWN, METAL/CERAMIC
$gmdn=$Zähne| select @{N='GMDN';E={$_.gmdnTerms.gmdn.gmdnPTName}} -Unique

$fmlist=$x| select @{N='FDA';E={$_.productCodes.fdaProductCode.productCode}},@{N='GMDN';E={$_.gmdnTerms.gmdn.gmdnPTName}}
$fmlist|group gmdn|select count, name|sort count
