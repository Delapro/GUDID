# Read FDA-Database

# https://www.fda.gov/medical-devices/classify-your-medical-device/download-product-code-classification-files
# http://www.accessdata.fda.gov/premarket/ftparea/foiclass.zip
$foi=Import-Csv -Path .\foiclass.txt -Delimiter '|'
$dental = $foi| Where-Object medicalspecialty -eq DE
$deProdCode = $dental | Select-Object -ExpandProperty ProductCode
$deProdCodeAnzahl = $deProdCode.Length

# Datengröße ermitteln
(Get-ChildItem *-dental.xml|Measure-Object length -Sum).Sum/1GB
# falls schon vorhanden
(Get-ChildItem *.xml -Exclude *-dental.xml |Measure-Object length -Sum).Sum/1GB

Function New-DevicesXMLDocument {

        $newxml=[xml]@"
<?xml version="1.0" encoding="UTF-8"?>
"@
        $devices=$newxml.CreateElement('devices')
        $newxml.AppendChild($devices) |Out-Null
        $newxml
}

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

# nun aus der GUDID-Datenbank die gesuchten Einträge herausholen
# https://www.fda.gov/medical-devices/global-unique-device-identification-database-gudid/gudid-guidance

$startTime = Get-Date
# zunächst alle XML-Dateien durchgehen und Dentalprodukte ermitteln, diese werden in eine *-dental.xml-Datei geschrieben
$files=Get-ChildItem *.xml -Exclude *-dental.xml|Sort-Object name
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
(Get-Date) - $startTime
$x.Length

<#
# nun die *-dental.xml-Dateien in ein gemeinsames Objekt einlesen
$files=Get-ChildItem *-dental.xml | Sort-Object name
# $x = $files | Select-Object -First 10 | ForEach-Object {
$x = $files | ForEach-Object {
        Write-Host "Reading $($_.Fullname)"
        Import-Clixml $_.FullName
        Start-Sleep -Seconds 1
}
$x.Length
#>


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
$x.Length
# Anzahl 2021: 417607

# Suche nach bestimmter Catalognummer
$x|where catalognumber -eq '66017316'

# Statistik

# GS1 Barcodes
$gs1=$x|? {$_.identifiers.identifier.deviceIdIssuingAgency -eq 'GS1'}
$gs1 | measure
# Count             : 2021: 241578    2020: 175529

# ungültige DI mit falscher Checksumme!
$gs1Prob=$x|? {$_.identifiers.identifier.deviceIdIssuingAgency -eq 'GS1' -and $_.identifiers.identifier.deviceIdType -eq 'Primary' -and $_.identifiers.identifier -isnot [array] -and  (-not (Test-GS1Checksum $_.identifiers.identifier.deviceID)) }

# HIBC Barcodes
$x|? {$_.identifiers.identifier.deviceIdIssuingAgency -eq 'HIBCC'} | measure
# Count             : 2021: 184509     2020: 167147

# Verpackungen
$x|? {$_.identifiers.identifier.deviceIdType -eq 'Package'} | measure
# Count             : 7248

# reale Produkte
$x|? {$_.identifiers.identifier.deviceIdType -eq 'Primary'} | measure
# Count             : 336427

# GS1-Produkte mit Lot und Seriennummer
$gs1|? {($_.lotbatch -eq $true) -and ($_.serialnumber -eq $true)} | measure
# Count             : 2021: 22636    2020: 19443

# GS1-Hersteller mit Lot und Seriennummer
$gs1|? {($_.lotbatch -eq $true) -and ($_.serialnumber -eq $true)} | select companyname -Unique|measure
# Count             : 2021: 105       2020: 79

# um die DIs einer gs1 Firma zu erhalten:
$gs1Company=$gs1| group -Property CompanyName
($gs1Company| where name -match straumann| select -ExpandProperty group).identifiers.identifier|  Out-GridView


# nicht mehr im Vertrieb
$x| ? deviceCommDistributionStatus -ne 'In Commercial Distribution'|measure
# Count             : 11504

# Produkte mit mehr 1 Identifier
$x|? {$_.identifiers.identifier.count -gt 1 }| measure
# Count             : 61825

# Produkte mit mehr 2 Identifier
$x|? {$_.identifiers.identifier.count -gt 2 }| measure
# Count             : 4565

# Produkte mit mehr 3 Identifier
$x|? {$_.identifiers.identifier.count -gt 3 }| measure
# Count             : 117

# Produkte mit mehr 4 Identifier
$x|? {$_.identifiers.identifier.count -gt 4 }| measure
# Count             : 21

# Produkte mit mehr 5 Identifier
$x|? {$_.identifiers.identifier.count -gt 5 }| measure
# Count             : 13


$h=$x| group companyName | measure -Property Count -Sum
"Hersteller: $($h.Count), mit insgesamt $($h.Sum) Produkten"

# Hersteller ausgeben
$x | group companyname | select Name

# Ausgabe der Produktcodes
$p= $x | select *, @{N='ProdCode';E={$_.productCodes.fdaProductCode.productCode}} | group -Property ProdCode
$codes=$p| select -ExpandProperty name
# da Codes mehrfach Nennungen enthalten können, diese nun entflechten:
$codeList=$codes | % {IF ($_.length -gt 3) {$_.split()} else {$_}}
# damit kann man nun wieder auf die Foi zurückgreifen:
$dental| where {$codeList -contains $_.productcode} | select medicalspecialty, productcode, devicename

# welche Firma bedient welchen Code?
$p| % {New-Object PSObject -Property @{Code=$_.Name;Companies=($_.Group| select -ExpandProperty companyname -Unique) }}

# nur Codes ermitteln, wo bestimmte Companies drin vorkommen
$cc=$p| % {New-Object PSObject -Property @{Code=$_.Name;Companies=($_.Group| select -ExpandProperty companyname -Unique) }}
$Zahnhersteller=$cc | ? { $c=($_.companies | % {$_|Out-String -Stream}); $c -match 'kulzer' -and $c -match 'bredent' -and $c -match 'candulor'} 

$Zähne = ($p|where Name -eq 'ELM').Group

# alle Zähne ausgeben
$Zähne| select companyname,brandname,devicedescription,catalognumber |Out-GridView

# alle Zähne eines bestimmten Herstellers ausgeben
$Zähne|where companyname -match vita| select companyname,brandname,devicedescription,catalognumber |Out-GridView

$Zahn=$Zähne|where catalognumber -eq '66017316'



# neben den FDA ProductCode (FDA PT-Code) gibt es noch die GMDN-Nomenklatur, allerdings taucht aus rechtlichen Gründen dort der GMDN-PT-Code nicht auf sondern nur der GMDN-PT-Name!
# FDA-PT-Code "ELM" entpsricht z. B. GMDN-PD-Name "DENTAL VENEER, CUSTOM-MADE"
# aber es gibt mehrere entsprechnungen von FDA nach GMDN:
# FDA-PT-Code "ELM" entpsricht auch GMDN-PD-Name "DENTAL CROWN, METAL/CERAMIC
$gmdn=$Zähne| select @{N='GMDN';E={$_.gmdnTerms.gmdn.gmdnPTName}} -Unique
<#
  GMDN
  ----
  Dental veneer, custom-made
  Resin artificial teeth
  Ceramic artificial teeth
  Partial denture
  Dental crown, metal/ceramic
  Dental repair kit, ceramic
  Dental impression tray material
  Dental prosthesis veneer resin
  Dental implant x-ray template
  Dental shaded pontic kit
#>

$fmlist=$x| select @{N='FDA';E={$_.productCodes.fdaProductCode.productCode}},@{N='GMDN';E={$_.gmdnTerms.gmdn.gmdnPTName}}
$fmlist|group gmdn|select count, name|sort count

<#

FDA                  GMDN
---                  ----
NOF                  Dental CAD/CAM system, laboratory
NHA                  Dental implant suprastructure, permanent, preformed
DZE                  Screw endosteal dental implant, two-piece
NUN                  Bone matrix implant, human-derived
ELM                  Dental veneer, custom-made
EBF                  Dental composite resin
NHA                  Dental implant system
EBI                  Dental prosthesis restorative material, unfilled resin
EBG                  Dental crown/bridge, temporary
ELM                  Resin artificial teeth
EIA                  General/plastic surgical procedure kit, non-medicated, single-use
DZE                  Dental implant system
{MPI, LZD}           Craniofacial bone screw, non-bioabsorbable, sterile
LZD                  Mandibular condyle prosthesis
{MPI, LZD}           Mandibular fossa prosthesis
{LZD, MPI}           Mandibular fossa prosthesis
EFL                  Airway tube forceps, reusable
EFL                  Dressing/utility forceps, tweezers-like, reusable
EMH                  Surgical soft-tissue manipulation forceps, tweezers-like, reusable
EIA                  General surgical procedure kit, medicated
EIC                  Dental irrigation/aspiration syringe
NDP                  Dental implant system
OFY                  Dental implant system
NYE                  Dental implant system
EKX                  Dental power tool system handpiece, line-powered
EBW                  Dental drilling system attachment
EFA                  Dental drilling system attachment
EGS                  Dental drilling system attachment
EBW                  Dental power tool system handpiece, line-powered
EFA                  Dental power tool system handpiece, line-powered
DZA                  Dental implant system
EKF                  Haematological concentrate system
NDP                  Fixture/appliance dental drill bit, reusable
EGS                  Dental power tool system handpiece, line-powered
NDP                  Test tube rack
EMH                  Dental rongeur
NDP                  General-purpose bowl, reusable
EGN                  Dental surgical scissors
NDP                  Haematological concentrate system
NDP                  Dental amalgam condenser, reusable
NDP                  General-purpose surgical spatula
ELW                  Alginate dental impression material
DYH                  Orthodontic bracket adhesive
KLE                  Dental etching solution
KIF                  Endodontic filling/sealing material
KLE                  Dental coating, tooth-desensitizing
LBH                  Dental coating, tooth-desensitizing
LBH                  Dental cavity varnish
EBC                  Dental pit/fissure sealant
EMA                  Glass ionomer dental cement
EMA                  Zinc phosphate dental cement
KLE                  Dentine bonding agent/set
DYH                  Dentine bonding agent/set
EBG                  Dental crown/bridge resin, temporary
EJJ                  Dental amalgam alloy
EBI                  Dental pulp-capping material
EMA                  Dental crown/bridge resin, temporary
KIF                  Endodontic dressing
EMA                  Silicone dental impression material
ELW                  Silicone dental impression material
KLE                  Dental composite adhesive kit
EBF                  Light-cured dental restorative composite resin
EBF                  Self-cured dental restorative composite resin
ELW                  Polysulfide dental impression material
EBI                  Denture reliner, soft, professional
ELC                  Ultrasonic dental scaling/debridement system handpiece tip, endodontic
ELC                  Ultrasonic dental scaling/debridement system
ELL                  Dental appliance fabrication material, ceramic
LBH                  Dental cavity varnish solvent
EBF                  Orthodontic bracket adhesive
EMA                  Temporary dental filling material
EBF                  Endodontic dressing
EJK                  Zinc polycarboxylate dental cement
EJK                  Dental restorative material varnish
EMB                  Zinc sulfate dental cement
EMA                  Zinc sulfate dental cement
ELW                  Polyether dental impression material
EIH                  Dental porcelain/ceramic restoration kit
LFC                  Dental caries removal solution
EMA                  Zinc polycarboxylate dental cement
KLE                  Dental restorative material varnish
EBF                  Glass ionomer dental cement
EBZ                  Dental/surgical polymerization lamp
EEG                  Dental/surgical polymerization lamp
EAT                  Cryogenic spray, dental
EID                  Dental material mixing nozzle, non-sterile
EBF                  Dental etching solution
EIH                  Dental appliance fabrication material, ceramic
ELC                  Ultrasonic dental scaling/debridement system handpiece tip, periodontal
LYC                  Pliable-polymer dental regeneration membrane, bioabsorbable, ligated
NPL                  Collagen dental regeneration membrane
EKO                  Preformed complete denture
EBI                  Dental appliance fabrication material, cured
{EBG, EBI}           Dental appliance fabrication material, thermoplastic
EBF                  Preformed dental crown, permanent
EJJ                  Dental amalgam
EJS                  Dental brazing alloy
EJT                  Dental brazing alloy
EJH                  Dental brazing alloy
EJT                  Dental casting noble alloy
ELW                  Dental impression tray material
ELW                  Dental impression material syringe, single-use
ELM                  Ceramic artificial teeth
EJS                  Dental casting noble alloy
EJH                  Dental casting non-noble alloy
NXV                  Oral lesion examination light
EFB                  Dental power tool system handpiece, pneumatic
EFB                  Pneumatic dental handpiece coupler
EGS                  Dental power tool system, pneumatic
EKX                  Dental power tool system handpiece, battery-powered
EIA                  Medical device light source controller
EFB                  Dental power tool system, pneumatic
EFB                  Surgical instrument maintenance lubricant
ELC                  Pneumatic dental scaling/debridement system
{ELC, EGS, EFB}      {Pneumatic dental scaling/debridement system, Dental drilling system attachment, Dental power t...
ELC                  Pneumatic dental scaling/debridement system handpiece tip, periodontal
{EFB, ELC}           {Dental power tool system, pneumatic, Pneumatic dental scaling/debridement system}
EGS                  {Dental drilling system attachment, Dental power tool system, pneumatic}
EGS                  {Pneumatic dental handpiece coupler, Dental drilling system attachment, Dental power tool syste...
ELC                  Pneumatic dental handpiece coupler
EGS                  Pneumatic dental handpiece coupler
EMA                  Endodontic filling/sealing material
EJE                  Rubber dam frame
EMN                  Manual dental scaler, reusable
EKR                  Endodontic plugger
EKK                  Manual endodontic spreader
EKB                  Dental explorer
EKC                  Dental excavator, reusable
EMS                  Periodontal curette
DZP                  Diamond dental bur, reusable
EMA                  Dental composite resin
EJK                  Dental composite resin
EJK                  Calcium hydroxide dental cement
EMA                  Dentine adhesive
KLE                  Dentine adhesive
EBG                  Dental composite resin
EJK                  Dental pulp-capping material
EMA                  Dentine bonding agent/set
{EBF, EBC}           Dental composite resin
EIE                  Rubber dam kit
EJR                  Dentifrice
EJK                  Endodontic filling/sealing material
EBC                  Dental composite resin
EBF                  Dental unfilled resin sealant/coating
EBF                  Medical device cleaning agent
{EMA, EBF}           Dental composite resin
KLE                  Dental repair kit, ceramic
EJK                  Calcium hydroxide suspension
EMA                  {Dentine adhesive, Orthodontic bracket adhesive}
{EBD, EBC}           Dental unfilled resin sealant/coating
EJK                  {Calcium hydroxide dental cement, Calcium hydroxide suspension}
EKL                  Endodontic reaming aid material
{KLE, EBF}           Dental unfilled resin sealant/coating
EMA                  Dental repair kit, ceramic
EBF                  Dental tooth-cleaning solution
EFT                  Dentifrice
EFT                  Denture cleanser
EFH                  Dental cement trial
EMB                  Denture reliner, soft, professional
LBH                  Dentifrice
MUH                  Radiography digital imaging scanner
NBL                  Dental caries detector, optical induced fluorescence
EGZ                  Cable/lead/sensor/probe cover, non-sterile
EJQ                  Dental abrasive point, reusable
EJL                  Carbide dental bur, reusable
DZB                  Orthodontic extraoral headgear
EID                  Syringe tip cap
EJI                  Dental anaesthesia syringe, reusable
KXR                  Syringe tip cap
EMB                  Fatty acid dental cement
KXX                  Surgical respirator
EJB                  Dental curette, basic
EIF                  Gingival retraction kit
EBF                  Dental pit/fissure sealant
LFC                  Dental caries detector, optical induced fluorescence
EBI                  Denture reliner, elastic, long-term
EBI                  Denture reliner, hard
NJM                  Orthodontic bracket, ceramic
{EBC, EBF}           Dental composite resin
KIF                  Synthetic gutta-percha
EBL                  Dental restoration retention pin
EKZ                  Electrosurgical system generator
NDP                  Dental laboratory power tool system
ELR                  Root canal post, preformed
DZA                  Pin/post dental drill bit
DZN                  Dental mould
DZN                  Root canal post, preformed
DZN                  Pin/post dental drill bit
EKS                  Rotary/reciprocating endodontic file/rasp, reusable
EIE                  Rubber dam, Hevea-latex
EEF                  Rubber dam clamp
EIE                  Rubber dam, non-latex
EBI                  Resin artificial teeth
EGD                  Dental base plate
EBF                  Dental prosthesis veneer resin
EJK                  Dental cavity liner
KHR                  Saliva absorbent
EJG                  Rubber dam clamp forceps
EJG                  Rubber dam punch
JEX                  Orthodontic pliers
EMD                  Orthodontic pliers
EHY                  Dental impression tray, single-use
DZN                  Dental restoration retention pin
NDP                  Dental prosthesis bite verification device
DZM                  Dental material injection cannula, single-use
EKQ                  Dental tooth-cleaning solution
EGD                  Saliva pH IVD, kit, colorimetric dipstick, rapid
EJQ                  Dental mandrel
EHM                  Dental abrasive strip, single-use
EMA                  Dental coating, tooth-desensitizing
DYH                  Glass ionomer dental cement
DZN                  Dental impression spacer
EJB                  Two-component dental material applicator, manual
{EMA, EJK}           Glass ionomer dental cement
EJR                  Dental coating, tooth-desensitizing
ELW                  Dental material application tool, single-use
EBG                  Dental material application tool, single-use
ELZ                  Preformed dental crown, temporary
KLE                  Light-cured dental restorative composite resin
DZA                  Root canal post, preformed
EBI                  Denture base resin, heat-cured
EBI                  Denture reliner, elastic, short-term
EBG                  Dental acrylic resin
EBH                  Dental impression tray, reusable
ELW                  Dental impression spacer
ELW                  Dental impression tray, single-use
EBH                  Dental impression tray, single-use
EBH                  Dental impression spacer
EID                  Dental impression material syringe, reusable
EID                  Haemoglobin E (HbE) IVD, calibrator
EID                  Dental material mixing surface, single-use
ELW                  Pharmaceutical fluid-dispensing system
EMA                  Silicophosphate dental cement
EMA                  Fatty acid dental cement
KIF                  Fatty acid dental cement
EMA                  Clinical periodontal dressing
ELW                  Denture reliner, soft, professional
ELW                  Dental impression adhesive
EBH                  Dental impression tray material
EBG                  Dental prosthesis restorative material, unfilled resin
DZD                  Orthodontic tube
ECI                  Orthodontic metal band
EMA                  Dental pulp-capping material
ECI                  Orthodontic inter-bracket elastic chain
EBF                  Dental cement trial
{EBF, EBG}           Dental implant suprastructure, permanent, preformed
{EBG, EBF}           Dental implant suprastructure, permanent, preformed
EMA                  Dental etching solution
EBD                  Dental unfilled resin sealant/coating
EMA                  Two-component dental material applicator, manual
EMA                  Dental material application tool, single-use
NYH                  Dental caries detecting stain
EFD                  Dental impression material mixer
DYH                  Dental etching solution
EBD                  Dental restorative material varnish
{EMA, EJK}           Dental cavity liner
LBH                  Dental crown/bridge resin, temporary
EBD                  Dental material application tool, single-use
EBI                  Dental mandrel
EBI                  Dental abrasive disk, reusable
EMA                  Dental cavity liner
ELW                  Composite dental impression material
EMA                  Dental restorative material varnish
EIH                  Dental crown, ceramic
ELW                  Dental composite resin
EBG                  Silicone dental impression material
EBG                  {Ultrasonic dental scaling/debridement system handpiece tip, periodontal, Silicone dental impre...
JES                  Dental floss
EFW                  Basic manual toothbrush
EFW                  Oral care kit, single-use
EJK                  Dentifrice
ELW                  Body aspiration needle, single-use
EFB                  Instrument/equipment drape, single-use, non-sterile
{EBF, EJK, EMA, EBC} Glass ionomer dental cement
{EBF, EMA, EBC, EJK} Glass ionomer dental cement
{EBC, EMA, EJK, EBF} Glass ionomer dental cement
{EMA, EBF, EBC, EJK} Glass ionomer dental cement
{EMA, EBF, EJK, EBC} Glass ionomer dental cement
ELC                  Dental scaling solution
ELC                  Dental abrasive air jet system
ELC                  Oral lavage system
LBH                  Dental unfilled resin sealant/coating
{EBC, EFB, PEM}      {Cable/lead/sensor/probe cover, non-sterile, Dental composite resin}
{EBC, PEM, EFB}      {Cable/lead/sensor/probe cover, non-sterile, Dental composite resin}
EBC                  Dental unfilled resin sealant/coating
EBC                  Dental etching solution
KOJ                  Dentifrice
ELC                  Dentifrice
EFD                  Dental amalgam mixer
EFK                  Rubber dam clamp forceps
EBH                  Dental composite resin
EBI                  Medicine bottle
EHZ                  Two-component dental material applicator, electric
EID                  Two-component dental material applicator, electric
EHZ                  Two-component dental material applicator, pneumatic
EHZ                  Dental material mixing nozzle, non-sterile
{EMA, EBG}           Dental crown/bridge, temporary
EMA                  ESDP endoscope
DZN                  Dental matrix band tensioner
DZN                  Dental matrix band, single-use
DZN                  Dental wedge, single-use
DZP                  Dental abrasive disk, reusable
{EJR, EHJ}           Dental abrasive disk, reusable
DZN                  {Dental matrix band tensioner, Dental matrix band, single-use, Dental wedge, single-use}
DZN                  {Dental wedge, single-use, Dental matrix band, single-use, Rubber dam clamp forceps, Dental mat...
DZN                  {Dental matrix band, single-use, Dental wedge, single-use, Rubber dam clamp forceps, Dental mat...
DZN                  {Rubber dam clamp forceps, Dental dressing forceps, reusable}
DZN                  {Dental dressing forceps, reusable, Rubber dam clamp forceps}
DZN                  {Dental matrix band tensioner, Dental dressing forceps, reusable, Dental matrix band, single-us...
DZN                  Rubber dam clamp forceps
DZN                  {Dental matrix band tensioner, Dental matrix band, single-use}
DZN                  {Dental matrix band, single-use, Dental matrix band tensioner}
EJJ                  Transabdominal amnioscope
EBI                  Dental composite resin
EBI                  Orthodontic retainer
EBF                  Dental/surgical polymerization lamp
EBC                  Silicone dental impression material
EBF                  Dental material injection cannula, reusable
EID                  Silicone dental impression material
EJR                  Dental abrasive disk, reusable
{EHJ, EJR}           Dental abrasive disk, reusable
EBF                  Dental mandrel
EBF                  {Dental unfilled resin sealant/coating, Dental mandrel}
EKP                  Dental composite resin
EBI                  Polyether dental impression material
{EBF, EMA}           Dental composite resin
EMA                  Zinc oxide eugenol dental cement
EMB                  Zinc oxide eugenol dental cement
KLE                  Dental composite resin
EMA                  Dental cement trial
EGG                  Complete upper denture
EJT                  Dental soldering alloy
EHP                  Dental appliance fabrication material, thermoplastic
EJH                  Dental soldering alloy
DZC                  Dental soldering alloy
EJS                  Dental casting non-noble alloy
ELE                  Subperiosteal dental implant material
{EBG, EBD}           Dental crown/bridge, temporary
{EBD, EBG}           Dental crown/bridge, temporary
{EBD, KLE, EBI}      Dental appliance fabrication material, cured
{KLE, EBI, EBD}      Dental appliance fabrication material, cured
{EBI, KLE, EBD}      Dental appliance fabrication material, cured
{EBD, EBI, KLE}      Dental appliance fabrication material, cured
{EBI, EBD, KLE}      Dental appliance fabrication material, cured
{KLE, EBD, EBI}      Dental appliance fabrication material, cured
EBI                  Dental appliance fabrication material, thermoplastic
{EBI, KLE}           Dental appliance fabrication material, cured
{KLE, EBI}           Dental appliance fabrication material, cured
EBG                  Dental prosthesis veneer resin
EJS                  Dental soldering alloy
ELL                  Ceramic artificial teeth
LBH                  Dental composite resin
EMA                  Dental acrylic resin
LRK                  Mandible-repositioning sleep-disordered breathing orthosis
KKO                  Teething device, fluid-filled
NXZ                  Oral care kit, single-use
EHZ                  Dental suction system
EJK                  Dental coating, tooth-desensitizing
OFX                  Dental/maxillofacial surgical procedure kit, non-medicated, single-use
LZD                  Total temporomandibular joint prosthesis
LZD                  Surgical implant template, single-use
LZD                  Craniofacial bone screw, non-bioabsorbable, non-sterile
EJT                  Dental casting non-noble alloy
ELR                  Fluted surgical drill bit, reusable
EBI                  Dental material mixing nozzle, sterile
EBI                  Dental reinforcing fibre
EBI                  {Dental prosthesis restorative material, unfilled resin, Dental reinforcing fibre}
MUH                  Dental computed radiography digital imaging scanner
EAP                  Dental digital imaging sensor, intraoral
NOF                  Dental CAD/CAM system, chairside
EIA                  Flexible video stomatoscope
MUH                  {Stationary extraoral dental x-ray system, digital, Stationary cephalometric x-ray system, digi...
MUH                  Stationary cephalometric x-ray system, digital
MUH                  Stationary extraoral dental x-ray system, digital
EHD                  Stationary cephalometric x-ray system, digital
EHD                  {Stationary cephalometric x-ray system, digital, Stationary extraoral dental x-ray system, digi...
EHD                  {Stationary extraoral dental x-ray system, digital, Stationary cephalometric x-ray system, digi...
MUH                  {Stationary cephalometric x-ray system, digital, Stationary extraoral dental x-ray system, digi...
EHD                  Stationary intraoral dental x-ray system, digital
EME                  Biopsy punch, reusable
LYC                  Synthetic bone graft
KKO                  Baby care kit
LPK                  Dental bone matrix implant, synthetic
EAX                  Dental mirror, reusable
JEX                  Dressing/utility forceps, tweezers-like, single-use
JEY                  Craniofacial bone screw, non-bioabsorbable, sterile
JEY                  Craniofacial bone screw, non-bioabsorbable, non-sterile
EHO                  Orthopaedic surgical procedure kit, non-medicated, single-use
JEY                  Craniofacial bone wire/bar
JEY                  Craniofacial fixation plate, non-bioabsorbable
DZL                  Craniofacial bone screw, non-bioabsorbable, sterile
NEI                  Craniofacial bone screw, non-bioabsorbable, sterile
JEY                  Orthopaedic bone wire
MQN                  Orthopaedic bone pin, non-bioabsorbable
DZE                  Craniofacial bone screw, non-bioabsorbable, sterile
DZM                  Dental syringe needle, single-use
EMM                  Surgical gouge
EMM                  Orthopaedic osteotome
EFW                  Tracheal suction catheter
{EBF, KLE}           {Dental composite resin, Dentine bonding agent/set}
EBF                  Dental material injection cannula, single-use
{KLE, EBF}           {Dentine bonding agent/set, Dental composite resin}
{KLE, EBF}           {Dental composite resin, Dentine bonding agent/set}
EBF                  Resin dental inlay
DZE                  Screw endosteal dental implant, one-piece
NDP                  Dental implant/prosthesis surgical procedure kit
{KLE, EBF}           {Dentine bonding agent/set, Dental composite resin, Dental etching solution}
{EBF, KLE}           {Dentine bonding agent/set, Dental etching solution}
{KLE, EBF}           {Dentine bonding agent/set, Dental etching solution, Dental composite resin}
{KLE, EBF}           {Dental etching solution, Dentine bonding agent/set, Dental composite resin}
EID                  Two-component dental material applicator, manual
ELW                  Two-component dental material applicator, manual
EIH                  Dentine bonding agent/set
KXR                  Dental material application tool, single-use
EIR                  Dental collar/crown scissors
EJY                  Orthodontic pliers
KCQ                  Dental matrix band, single-use
{EBC, KLE}           {Dental unfilled resin sealant/coating, Dental etching solution}
{EID, EBF, KLE}      {Dentine bonding agent/set, Dental composite resin, Dental material injection cannula, single-use}
{EBC, KLE}           {Dental pit/fissure sealant, Dentine bonding agent/set}
EMI                  Bone file
MQN                  Craniofacial bone screw, non-bioabsorbable, sterile
JEY                  Orthopaedic bone screw, non-bioabsorbable, non-sterile
JEY                  Orthopaedic bone screw, bioabsorbable
{MQN, JEY, HWC}      Orthopaedic bone screw, non-bioabsorbable, non-sterile
{HWC, JEY, MQN}      Orthopaedic bone screw, non-bioabsorbable, non-sterile
{HWC, MQN, JEY}      Orthopaedic bone screw, non-bioabsorbable, non-sterile
{JEY, MQN, HWC}      Orthopaedic bone screw, non-bioabsorbable, non-sterile
{JEY, MQN}           Orthopaedic bone screw, non-bioabsorbable, non-sterile
{MQN, JEY}           Orthopaedic bone screw, non-bioabsorbable, non-sterile
{JEY, DZL}           Orthopaedic bone screw, non-bioabsorbable, non-sterile
{DZL, JEY}           Orthopaedic bone screw, non-bioabsorbable, non-sterile
{JEY, HWC, MQN, DZL} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{HWC, MQN, JEY, DZL} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{HWC, MQN, DZL, JEY} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{DZL, JEY, HWC, MQN} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{MQN, HWC, DZL, JEY} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{HWC, DZL, JEY, MQN} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{JEY, MQN, DZL, HWC} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{MQN, HWC, JEY, DZL} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{MQN, DZL, HWC, JEY} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{JEY, DZL, HWC, MQN} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{HWC, JEY, MQN, DZL} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{JEY, MQN, HWC, DZL} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{DZL, MQN, HWC, JEY} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{DZL, JEY}           Craniofacial bone screw, non-bioabsorbable, sterile
{HWC, MQN, DZL}      Orthopaedic bone screw, non-bioabsorbable, non-sterile
{MQN, DZL, HWC}      Orthopaedic bone screw, non-bioabsorbable, non-sterile
{HWC, DZL, MQN}      Orthopaedic bone screw, non-bioabsorbable, non-sterile
{DZL, MQN}           Orthopaedic bone screw, non-bioabsorbable, non-sterile
{MQN, DZL}           Orthopaedic bone screw, non-bioabsorbable, non-sterile
{DZL, HWC, MQN}      Orthopaedic bone screw, non-bioabsorbable, non-sterile
DZL                  Implantable craniofacial bone distractor
DZL                  Orthopaedic bone screw, non-bioabsorbable, non-sterile
OAT                  Orthodontic anchoring screw
{JDW, DZL, MQN}      Orthopaedic bone wire
EIC                  Dental syringe needle, single-use
EIC                  Irrigation syringe
DZI                  Surgical power tool system handpiece, sawing, pneumatic
DZI                  Drilling power tool attachment, basic
NHA                  Dental prosthesis/implant abutment screw
KIF                  Dental etching solution
PLV                  Dental stereotactic surgery system
EFN                  Dissection sponge
KHR                  Dental bib
EFN                  Dental cotton roll
NRU                  Medical equipment drape, single-use, non-sterile
EJI                  Dental computer assisted anaesthesia injection handpiece
EJI                  Dental computer assisted anaesthesia injection unit
{JEY, DZE}           Bone-screw internal spinal fixation system, non-sterile
{DZE, JEY}           Bone-screw internal spinal fixation system, non-sterile
LBH                  Fluoride gel
NHA                  Dental implant suprastructure, temporary, preformed, single-use
NDP                  Dental implant suprastructure, temporary, preformed, reusable
DZE                  Dental implant suprastructure, temporary, preformed, single-use
DZE                  Dental implant suprastructure, permanent, preformed
DZM                  General-purpose syringe, single-use
EBW                  Surgical irrigation tubing set, single-use
DZL                  Cranioplasty plate screw
ELC                  Ultrasonic dental scaling/debridement system handpiece
ELC                  Foot-switch, electrical
ELC                  Ultrasonic dental scaling/debridement system generator
OFX                  General/plastic surgical procedure kit, non-medicated, single-use
NEA                  Glass ionomer dental cement
JEY                  {Cranioplasty plate, alterable, Craniofacial fixation plate, non-bioabsorbable}
JEY                  {Craniofacial fixation plate, non-bioabsorbable, Cranioplasty plate, alterable}
OFX                  Dental anaesthesia injection kit
PWL                  Dental/maxillofacial surgical procedure kit, non-medicated, single-use
EFN                  General/plastic surgical procedure kit, non-medicated, single-use
OFX                  Dental/maxillofacial surgical procedure kit, medicated, single-use
KMY                  Dental occlusal splint, custom-made
MQN                  Craniofacial bone screw, non-bioabsorbable, non-sterile
DZL                  Craniofacial bone screw, non-bioabsorbable, non-sterile
MQN                  Implantable craniofacial bone distractor
JEY                  Craniofacial bone tack, bioabsorbable
JEY                  Craniofacial bone screw, bioabsorbable
JEY                  Implantable craniofacial bone distractor
JEY                  Ultrasonic osteosynthesis system
JEY                  Temporary mandibular condyle prosthesis
NEI                  Temporary mandibular condyle prosthesis
JEY                  Orthopaedic fixation plate, bioabsorbable
JEY                  Craniofacial bone distractor extension
{JEY, MQN}           Implantable craniofacial bone distractor
{MQN, JEY}           Implantable craniofacial bone distractor
NEI                  Craniofacial fixation plate, non-bioabsorbable
{DZL, JEY}           Craniofacial fixation plate, non-bioabsorbable
{JEY, DZL}           Craniofacial fixation plate, non-bioabsorbable
DZL                  Craniofacial fixation plate, non-bioabsorbable
{HWC, JEY, DZL, MQN} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{HWC, DZL, MQN, JEY} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{DZL, HWC, JEY, MQN} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{DZL, HWC, MQN, JEY} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{JEY, HWC, DZL, MQN} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{DZL, MQN, HWC}      Orthopaedic bone screw, non-bioabsorbable, non-sterile
DZI                  Fluted surgical drill bit, reusable
DZJ                  Bone tap, single-use, non-sterile
DZJ                  Surgical countersink, single-use
{HWE, DZI, DZJ}      Surgical power tool maintenance adaptor
{DZI, DZJ}           Surgical screwdriver, reusable
JEY                  Craniofacial fixation plate kit, non-bioabsorbable
OAT                  Orthodontic anchor plate
MQN                  Orthopaedic bone screw, non-bioabsorbable, non-sterile
MQN                  External orthopaedic fixation system, reusable
{DZJ, DZI}           Fluted surgical drill bit, reusable
{DZI, DZJ}           Fluted surgical drill bit, reusable
{HXX, DZI, DZJ}      Surgical screwdriver, reusable
{DZI, DZJ, HXX}      Surgical screwdriver, reusable
{DZJ, DZI}           Surgical screwdriver, reusable
{HXX, DZJ, DZI}      Surgical screwdriver, reusable
{DZI, HXX, DZJ}      Surgical screwdriver, reusable
{DZJ, DZI, HXX}      Surgical screwdriver, reusable
JEY                  Orthopaedic fixation plate bending insert, single-use
EBO                  Dental/maxillofacial surgical procedure kit, non-medicated, single-use
OFW                  Dental/maxillofacial surgical procedure kit, non-medicated, single-use
EFN                  Dental/maxillofacial surgical procedure kit, non-medicated, single-use
{JEY, DZL, MQN, HWC} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{DZL, JEY, MQN, HWC} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{MQN, JEY, DZL, HWC} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{DZL, MQN, JEY, HWC} Orthopaedic bone screw, non-bioabsorbable, non-sterile
{MQN, HWC, DZL}      Orthopaedic bone screw, non-bioabsorbable, non-sterile
EML                  Orthopaedic chisel
EML                  Surgical instrument handle, non-torque-limiting
{JEY, KTT, DZL}      External orthopaedic fixation system, reusable
{JEY, DZL, KTT}      External orthopaedic fixation system, reusable
{KTT, DZL, JEY}      External orthopaedic fixation system, reusable
{JEY, MQN, DZL, KTT} External orthopaedic fixation system, reusable
{MQN, DZL, KTT, JEY} External orthopaedic fixation system, reusable
{MQN, KTT, JEY, DZL} External orthopaedic fixation system, reusable
ECI                  Dental/maxillofacial surgical procedure kit, non-medicated, single-use
EFL                  Dental/maxillofacial surgical procedure kit, non-medicated, single-use
EMM                  Dental osteotome
EIG                  Hand-held surgical retractor, reusable
DZN                  Dental rongeur
EMJ                  Dental osteotome
EML                  Dental osteotome
EMJ                  Periosteal elevator, reusable
EIG                  Bone holding forceps
EMM                  Orthopaedic knife
EIG                  Hand-held dental retractor
EMM                  Hand-held dental retractor
EMJ                  Hand-held surgical retractor, reusable
EHO                  Orthodontic archwire
EMG                  Tooth extraction forceps
EMJ                  ENT elevator
EMG                  Dental explorer
EMG                  Periosteal elevator, reusable
EMK                  Periodontal curette
EMI                  Bone file/rasp, manual
EMI                  Nasal file/rasp
EMJ                  Dental pick, massaging
EMM                  Plastic surgery osteotome
EMK                  Intrauterine curette, manual
EFL                  Surgical soft-tissue manipulation forceps, tweezers-like, reusable
EMJ                  Orthodontic ligature director
EBA                  Head-worn light, line-powered
EFN                  Woven gauze roll, sterile
EFN                  Woven gauze roll, non-sterile
MDL                  Arterial/central venous catheterization support/maintenance kit
DYN                  Dental suction system
LRK                  Sleep apnoea palate implant, non-bioabsorbable
ELC                  Dental delivery system instrument unit, electric
EHD                  Stationary extraoral dental x-ray system, digital
DZP                  Diamond dental bur, single-use
ECB                  Medical equipment drape, single-use, non-sterile
ECB                  Dental material mixing nozzle, non-sterile
EGS                  Dental polishing cup, reusable
EID                  Dental suction system cannula, single-use
EHZ                  Dental suction system cannula, single-use
EGS                  Dental polishing cup, single-use
EHJ                  Dental abrasive disk, reusable
EFH                  Interproximal/occlusal dental gauge, single-use
KMT                  Fluoride gel tray
EMA                  Ethoxy benzoic acid dental cement
EID                  Dental material injection cannula, single-use
MZW                  Dental composite resin
EHY                  Dental impression spacer
NDP                  Dental guided surgery reference pin
NDP                  Dental implant suprastructure, temporary, preformed, single-use
NDP                  Surgical screwdriver, reusable
NDP                  Instrument tray
NDP                  Dental torque wrench
NDP                  Surgical drill guide, reusable
NPM                  Dental bone matrix implant, animal-derived
NDP                  Dental implant suprastructure, permanent, preformed
NDP                  Dental implant extractor
NDP                  Dental implantation depth/angle gauge, reusable
NDP                  Diamond dental bur, reusable
DZI                  Dental drill bit extension
EKZ                  Open-surgery electrosurgical electrode, monopolar, reusable
EJH                  Dental tooth-cleaning solution
EFH                  Dental articulation paper
EKZ                  Electrosurgical system
KOJ                  Dental abrasive powder
EAT                  Dental pulp analysis system
EKZ                  Electrosurgical return electrode, reusable
EKZ                  Electrosurgical handpiece, reusable
EAT                  Endodontic obturation system
OHP                  Nasal dilator
NPL                  Multi-purpose surgical mesh, collagen, bioabsorbable
DZN                  Dental implant system
LFC                  Dental caries detecting stain
EBF                  Dental prosthesis priming agent
KLE                  Dental prosthesis priming agent
EMA                  Orthodontic bracket adhesive
DZM                  Orthodontic extraoral headgear
{EIA, EKX, ELC}      Ultrasonic dental scaling/debridement system
{ELC, EKX, EIA}      Ultrasonic dental scaling/debridement system
EBF                  Dental material mixing nozzle, non-sterile
LYC                  Dental bone matrix implant, synthetic
DZE                  Total haemoglobin (totHb) IVD, control
DZE                  Quetiapine IVD, reagent
EBG                  Dental material mixing nozzle, non-sterile
EIG                  Dental dry field kit
EBZ                  Medical equipment drape, single-use, non-sterile
EBG                  Mechanical pipette
ELW                  Dental material mixing nozzle, non-sterile
EMA                  Dental material mixing nozzle, non-sterile
EJQ                  Dental abrasive point, single-use
NSB                  Personal care kit
NSB                  Baby care kit
OFX                  Oral care kit, single-use
ELS                  Dental reinforcing fibre
DZI                  Bone trephine
LYC                  Bone graft delivery kit
EGD                  Wax dental impression material
ECB                  Dental delivery system irrigation handpiece
DYN                  Dental suction system cannula, single-use
EMJ                  Dental root elevator
EMG                  Surgical soft-tissue manipulation forceps, tweezers-like, reusable
EMJ                  Bone lever/elevator
EHY                  Dental impression tray, reusable
EAX                  Rhinoscopic mirror
EAX                  Laryngeal mirror, reusable
EKH                  Dental wax carver
EKH                  Dental plastic restoration carver
EMM                  Orthopaedic osteotome blade, reusable
EMM                  Nasal speculum, reusable
EMM                  Chisel/osteotome blade handle
EIY                  Dental plastic restoration carver
EMM                  Nasal chisel
EMJ                  Bone curette, reusable
EMK                  Dental curette, basic
EKB                  Hand-held surgical retractor, reusable
LRK                  Tongue-retaining sleep-disordered breathing orthosis
EKK                  Endodontic filling material condenser
EAX                  Rechargeable battery pack
EIX                  Periodontal probe, reusable
DZN                  Dental impression tray, reusable
EJB                  Surgical instrument handle, non-torque-limiting
EKS                  Manual endodontic file/rasp, single-use
EJZ                  Periodontal knife
EJL                  Carbide dental bur, single-use
EKP                  Manual endodontic file/rasp, reusable
EIK                  Dental wax carver
EKI                  Dental amalgam carrier
EKG                  Dental amalgam condenser, reusable
EID                  Orthopaedic graft inserter
EJB                  Dental mirror, reusable
{EIK, EKJ}           Dental wax carver
EKJ                  Manual dental burnisher, reusable
EIS                  Hand-held surgical retractor, reusable
EAX                  Dental mirror, single-use
EHJ                  Dental laboratory mandrel
EGS                  Dental laboratory drilling system handpiece
EKI                  Dental amalgam well
EMD                  Dental dressing forceps, reusable
EMB                  Endodontic filling/sealing material
EGD                  Dental casting wax
ECB                  Dental irrigation/aspiration syringe
EKS                  Manual endodontic file/rasp, reusable
EKS                  Endodontic stopper
EMK                  Bone curette, reusable
EKS                  Rotary/reciprocating endodontic file/rasp, single-use, non-sterile
EIK                  Dental spatula, reusable
EGZ                  Dental x-ray film holder
DZN                  Dental spatula, reusable
EFL                  Dental dressing forceps, reusable
EIL                  Interproximal dental gauge, reusable
EIG                  Mouth gag, non-adjustable
EKP                  Manual endodontic file/rasp, single-use
EKW                  Endodontic broach, serrated, single-use
EKM                  Synthetic gutta-percha
EFL                  Surgical soft-tissue manipulation forceps, tweezers-like, single-use
JEP                  Dental matrix band, single-use
EJL                  Steel dental bur
DZN                  Endodontic filling material carrier
EML                  Dental excavator, reusable
EIL                  Periodontal probe, reusable
EKH                  Dental amalgam carver, reusable
EJB                  Laryngeal mirror, reusable
EGD                  Bite registration rim wax
DZN                  Dental suction system
EMQ                  Periotome, reusable
JEP                  Dental matrix band retainer
ECS                  Orthodontic pliers
EMP                  Periodontal probe, reusable
JEX                  Dental dressing forceps, reusable
EFL                  Surgical soft-tissue manipulation forceps, scissors-like, reusable
EJY                  Dental dressing forceps, reusable
EKC                  Bone curette, reusable
EIR                  Wire cutter
EFK                  Dental articulation paper forceps
ECS                  Orthodontic metal band pusher
EIS                  Dental collar/crown scissors
EIL                  Surgical depth gauge, reusable
EMI                  Periodontal file/rasp
EMQ                  Periodontal hoe
EKH                  Periotome, reusable
JEX                  Surgical flat-nosed pliers
EKF                  Dental plastic restoration carver
EGN                  General-purpose surgical scissors, reusable
EMI                  Manual endodontic file/rasp, reusable
EMO                  Periodontal knife
EKT                  Periodontal curette
DZN                  Root canal obturating point
LYC                  General oral wound dressing, animal-derived
LYC                  Dental soft-tissue matrix implant, animal-derived
LYC                  Collagen dental regeneration membrane
DZL                  Instrument tray
DZL                  Surgical mallet
DZL                  Dappen dish, reusable
DZL                  ENT elevator
DZL                  Paranasal sinus curette
DZL                  Plastic surgery file/rasp
DZL                  Membrane fixation tack, non-bioabsorbable
DZL                  Periodontal probe, reusable
DYX                  Orthopaedic bone wire
EGZ                  Digital imaging cassette/storage phosphor screen
ECI                  Orthodontic appliance relief material
DZC                  Orthodontic archwire
ECI                  Orthodontic inter-arch elastic band
ECM                  Orthodontic metal band
EJF                  Orthodontic bracket, metal
EKM                  Warm-bonded endodontic obturation system obturator
ELR                  Root canal post kit
EID                  Material-handling lift
EID                  General-purpose endoscopic needle, single-use
EIG                  Dental cheek retractor, professional, reusable
NXC                  Orthodontic appliance system, progressive
EHL                  Dental abrasive point, reusable
ECI                  Orthodontic archwire/bracket ligature
EJF                  Orthodontic retainer
JET                  Dental floss
EHZ                  Suction system canister liner
EIC                  Anaesthesia Luer syringe, non-sterile
EID                  Dental impression material syringe, single-use
EID                  Dental impression material kit, reusable
EKF                  Dental wedge, reusable
EKP                  Pin/post dental drill bit
ELR                  Pin/post dental drill bit
DZM                  General-purpose endoscopic needle, single-use
EKN                  Endodontic paper point
EHK                  Dental polishing cup, single-use
EFA                  Dental polishing cup, single-use
EFW                  Dental floss
LCN                  Dental floss
{KXR, DYH}           {Dental material injection cannula, single-use, Dental etching solution}
DYW                  Orthodontic bracket, plastic, single-use
KXR                  Dental material injection cannula, single-use
EBH                  Preformed dental crown, permanent
EBF                  {Preformed dental crown, permanent, Dental appliance fabrication material, ceramic}
EBF                  {Dental composite resin, Dental veneer, custom-made}
EBF                  {Dental veneer, custom-made, Dental composite resin}
EIH                  Surgical staple remover, reusable
EJL                  Dental implant/prosthesis surgical procedure kit
ELB                  Denture cleaning brush
EBF                  Dental implant suprastructure, permanent, preformed
NDP                  Dental implant analog
NHA                  Dental torque wrench
DZE                  Orthodontic anchoring screw
EMJ                  Dental implant system
EJB                  Dental implant system
EJL                  Dental implant system
EIL                  Dental implantation depth/angle gauge, reusable
DZN                  Gingiva-coring punch, reusable
NDP                  Fluted surgical drill bit, reusable
EAX                  Surgical video camera
DZI                  Dental ultrasonic surgical system
NHA                  Dental implant suprastructure kit
EMJ                  Dental implant suprastructure, temporary, preformed, single-use
LYC                  Intracardiac electrode
LYC                  Automatic-inflation electronic sphygmomanometer, portable, finger
JEY                  {Orthodontic anchor plate, Craniofacial fixation plate, non-bioabsorbable}
DZL                  Orthodontic anchoring screw
JEY                  Orthodontic anchor plate
DZL                  Dental implant suprastructure, temporary, preformed, reusable
{DZL, DZE, HWC}      Craniofacial bone screw, non-bioabsorbable, sterile
{DZL, DZE, HWC}      {Orthodontic anchoring screw, Craniofacial bone screw, non-bioabsorbable, sterile}
JEY                  {Craniofacial fixation plate, non-bioabsorbable, Orthodontic anchor plate}
EKQ                  Endodontic reaming aid material
NDP                  Dental etching solution
{EGS, EBW, DZI}      Dental power tool system, line-powered
{EBW, EGS, DZI}      Dental power tool system, line-powered
EBF                  Dental crown/bridge, temporary
EBC                  Dental unfilled resin sealant
{EBF, EBC}           {Dental unfilled resin sealant, Dental etching solution}
{EBF, KLE}           {Dental etching solution, Dentine bonding agent/set, Dental composite resin}
EHD                  Portable basic diagnostic x-ray system, digital
MUH                  Stationary panoramic dental x-ray system, digital
MUH                  Dental digital imaging sensor, intraoral
NFS                  Bite registration rim
EEA                  Dental base plate
EBH                  Composite dental impression material
{NPM, LYC}           Dental bone matrix implant, synthetic
{LYC, NPM}           Dental bone matrix implant, synthetic
NYH                  Diagnostic-imaging multiformat camera
NBL                  Diagnostic-imaging multiformat camera
JEY                  Cranioplasty plate screw
JEY                  Multi-purpose surgical mesh, metallic
DZA                  Fluted surgical drill bit, single-use, non-sterile
JEY                  Neurosurgical procedure kit, non-medicated, single-use
NPK                  Spinal bone screw, bioabsorbable
JEY                  Multi-purpose surgical mesh, synthetic polymer, bioabsorbable
NPK                  Pliable-polymer dental regeneration membrane, bioabsorbable, tacked
JEY                  Surgical screwdriver, reusable
JEY                  Bone tap, reusable
NPK                  Bone tack inserter, basic
JEY                  Fluted surgical drill bit, reusable
JEY                  Surgical implant template, reusable
JEY                  Instrument tray
KHR                  Bedding set
ELR                  Root canal post, custom-made
DZN                  Root canal post kit
EBI                  Dental material application tool, single-use
EBI                  Dentine adhesive
EBI                  Dental restoration retention pin
KMW                  Dental power tool system handpiece, remotely-driven
EBW                  Remotely-driven dental drilling system motor
EFB                  Dental power tool system handpiece, remotely-driven
EFB                  Dental handpiece maintenance unit
EBW                  Dental power tool system, line-powered
EBW                  Foot-switch, electrical
EBW                  Line-powered dental drilling/sawing system handpiece
EFB                  Remotely-driven dental drilling system motor
EBW                  Dental power tool system handpiece, remotely-driven
EFB                  Dental implant stability measurement control unit
DZI                  Dental ultrasonic surgical system handpiece tip
EKX                  Surgical screwdriver, reusable
EFB                  Dental power tool system handpiece, line-powered
EFB                  Pneumatic dental scaling/debridement system handpiece
EGS                  Dental power tool system handpiece, remotely-driven
EFB                  Pneumatic dental scaling/debridement system
EBF                  Polymer-based dental model material
NUN                  Dental bone matrix implant, human-derived
NHA                  Dental implant/prosthesis surgical procedure kit
NHA                  Dental precision attachment simulator/analog, single-use
DZL                  Craniofacial fixation plate kit, non-bioabsorbable
DZA                  Fixture/appliance dental drill bit, reusable
NDP                  Dental suction system cannula, single-use
JEY                  Dental bone matrix implant, metallic
EIY                  Dental implant system
EIY                  Dental implant/prosthesis surgical procedure kit
EHY                  Dental implant system
{LYC, NPM}           Dental bone matrix implant, animal-derived
{NPM, LYC}           Dental bone matrix implant, animal-derived
{LYC, NPM}           Tungsten-weighted oesophageal dilator
{EKM, KIF}           Endodontic filling/sealing material
NHA                  Screw endosteal dental implant, two-piece
NHA                  Multi-purpose surgical mesh, metallic
EGD                  Orthodontic appliance relief material
EFL                  Tooth extraction forceps
ECT                  Surgical screwdriver, reusable
ECN                  Orthodontic lock
ECO                  Orthodontic spring
EHD                  Hand-held intraoral dental x-ray system, digital
NDP                  Dental/maxillofacial surgical procedure kit, non-medicated, reusable
NHA                  Dental implant analog
NDP                  Dental implant suprastructure kit
DZE                  Fixture/appliance dental drill bit, single-use
EHD                  Diagnostic x-ray system generator, portable
NHA                  Haemoglobin B2 (HbB2) IVD, kit, electrophoresis
{NHA, DZE}           {Screw endosteal dental implant, two-piece, Screw endosteal dental implant, one-piece, Dental i...
{NHA, DZE}           Dental implant system
{NHA, DZE}           Haemoglobin E (HbE) IVD, calibrator
{NHA, DZE}           Screw endosteal dental implant, one-piece
{NHA, DZE}           {Dental implant system, Screw endosteal dental implant, one-piece}
EBL                  Dental implant system
EIL                  Dental implant system
DZP                  Ultrasonic dental scaling/debridement system handpiece tip, endodontic
EIY                  Dental syringe needle, single-use
ELW                  Dental impression material kit, single-use
DZA                  Dental implant suprastructure, permanent, preformed
EHY                  Fixture/appliance dental drill bit, reusable
EHY                  Screw endosteal dental implant, one-piece
EKR                  Endodontic obturation system
MUH                  Stationary panoramic/tomographic dental x-ray system, digital
NHA                  Screw endosteal dental implant, one-piece
{KMW, EGS, EBW}      Dental implant system
{KMW, EGS, EBW}      Dental power tool system handpiece, line-powered
JEY                  Dental implant suprastructure, permanent, preformed
JEY                  Screw endosteal dental implant, two-piece
OAT                  Screw endosteal dental implant, one-piece
MUH                  Hand-held intraoral dental x-ray system, digital
MUH                  Diagnostic x-ray system generator, portable
MYB                  Sleep apnoea pillow
EEA                  Dental prosthesis bite verification device
NDP                  Dental guided surgery reference plate
DYT                  Dental occlusal splint, custom-made
{ELJ, ELK}           {Dental prosthesis veneer resin, Dental crown/bridge resin, temporary, Dental crown, polymer, D...
{ELK, ELJ}           {Dental prosthesis veneer resin, Dental crown, polymer, Dental veneer, custom-made, Dental brid...
{ELJ, ELK}           {Dental crown, polymer, Dental crown/bridge, temporary, Dental veneer, custom-made, Dental pros...
{ELJ, ELK}           {Dental prosthesis veneer resin, Dental crown, polymer, Dental crown/bridge, temporary, Dental ...
{ELK, ELJ}           {Dental prosthesis veneer resin, Dental crown, polymer, Dental crown/bridge, temporary, Dental ...
EBH                  Dental occlusal splint, custom-made
DYT                  {Dental prosthesis veneer resin, Dental crown/bridge resin, temporary, Dental crown, polymer, D...
DYT                  {Dental bridge, polymer, Dental crown/bridge, temporary, Dental veneer, custom-made, Dental cro...
DYT                  {Dental crown, polymer, Dental prosthesis veneer resin, Dental crown/bridge resin, temporary, D...
DYT                  {Dental bridge, polymer, Dental veneer, custom-made, Dental crown/bridge, temporary, Dental cro...
DYT                  {Dental crown, polymer, Dental veneer, custom-made, Dental crown/bridge resin, temporary, Denta...
DYT                  {Dental crown, polymer, Dental crown/bridge resin, temporary, Dental veneer, custom-made, Denta...
DYT                  {Dental crown/bridge resin, temporary, Dental crown, polymer, Dental prosthesis veneer resin, D...
DYT                  {Dental crown/bridge, temporary, Dental crown/bridge resin, temporary, Dental veneer, custom-ma...
DYT                  {Dental crown, polymer, Dental prosthesis veneer resin, Dental bridge, polymer, Dental crown/br...
DYT                  {Dental bridge, polymer, Dental prosthesis veneer resin, Dental crown, polymer, Dental veneer, ...
DYT                  {Dental veneer, custom-made, Dental bridge, polymer, Dental crown, polymer, Dental prosthesis v...
DYT                  {Dental bridge, polymer, Dental crown, polymer, Dental prosthesis veneer resin, Dental crown/br...
DYT                  {Dental prosthesis veneer resin, Dental crown, polymer, Dental veneer, custom-made, Dental brid...
DYT                  {Dental bridge, polymer, Dental veneer, custom-made, Dental crown/bridge, temporary, Dental pro...
DYT                  {Dental bridge, polymer, Dental veneer, custom-made, Dental crown/bridge resin, temporary, Dent...
DYT                  {Dental veneer, custom-made, Dental crown/bridge, temporary, Dental crown/bridge resin, tempora...
DYT                  {Dental bridge, polymer, Dental crown/bridge resin, temporary, Dental crown/bridge, temporary, ...
DYT                  {Dental crown/bridge, temporary, Dental crown, polymer, Dental crown/bridge resin, temporary, D...
DYT                  {Dental veneer, custom-made, Dental crown, polymer, Dental prosthesis veneer resin, Dental brid...
DYT                  {Dental veneer, custom-made, Dental bridge, polymer, Dental crown, polymer, Dental prosthesis v...
DYT                  {Dental crown/bridge, temporary, Dental crown, polymer, Dental prosthesis veneer resin, Dental ...
DYT                  {Dental crown/bridge resin, temporary, Dental crown/bridge, temporary, Dental crown, polymer, D...
DYT                  {Dental veneer, custom-made, Dental bridge, polymer, Dental prosthesis veneer resin, Dental cro...
DYT                  {Dental crown/bridge, temporary, Dental prosthesis veneer resin, Dental bridge, polymer, Dental...
DYT                  {Dental occlusal splint, custom-made, Orthodontic retainer}
DYT                  {Orthodontic retainer, Dental occlusal splint, custom-made}
EBI                  {Dental prosthesis restorative material, unfilled resin, Dental appliance fabrication material,...
EBI                  {Dental appliance fabrication material, cured, Dental prosthesis restorative material, unfilled...
DYT                  {Dental prosthesis veneer resin, Dental bridge, polymer, Dental crown, polymer, Dental crown/br...
DYT                  {Dental crown/bridge, temporary, Dental crown, polymer, Dental veneer, custom-made, Dental crow...
DYT                  {Dental veneer, custom-made, Dental bridge, polymer, Dental crown/bridge, temporary, Dental cro...
NDP                  {Dental appliance fabrication material, cured, Dental prosthesis fabrication material, polymer}
EBF                  Dental reinforcing fibre
DZN                  Surgical soft-tissue manipulation forceps, tweezers-like, reusable
DZN                  Dental/maxillofacial surgical procedure kit, non-medicated, reusable
NDP                  Surgical torque wrench adaptor
DZN                  Orthopaedic implant impactor
DZN                  Surgical mallet
DZI                  Fixture/appliance dental drill bit, reusable
NDP                  Dental drill bit extension
{EBG, MQC, EBI}      Dental crown/bridge, temporary
{EBI, MQC, EBG}      Dental crown/bridge, temporary
{EBG, EBI}           Dental crown/bridge, temporary
{EBI, EBG}           Dental crown/bridge, temporary
DZA                  Fixture/appliance dental drill bit, single-use
DZI                  Bone tap, reusable
DZL                  Dental prosthesis/implant abutment screw
NHA                  Resilient dental precision attachment
DZI                  Dental/maxillofacial surgical procedure kit, medicated, reusable
EHD                  Stationary intraoral dental x-ray system, analogue
MUH                  Cone beam computed tomography system, head/neck
EHD                  Stationary panoramic/tomographic dental x-ray system, analogue
DZI                  Ultrasonic dental scaling/debridement system
{EHD, MUH}           Stationary panoramic/tomographic dental x-ray system, analogue
{EHD, MUH}           Stationary panoramic/tomographic dental x-ray system, digital
DZE                  Intramucosal dental implant
DZB                  Orthodontic face bow
{NDP, EJL, EKD, OAT} Orthodontic anchoring screw
DZB                  Orthodontic chin cap
EJS                  Orthodontic wire
DZL                  Orthopaedic fixation plate bending insert, single-use
NHA                  Dental bridge, ceramic
DZE                  Dental implant/prosthesis surgical procedure kit
{OIV, ELY, EJJ}      Dental amalgam alloy
{EJJ, ELY, OIV}      Dental amalgam alloy
EGG                  Dental anchor
NDP                  Dental precision attachment fitting/adjustment tool
NDP                  Surgical instrument handle, non-torque-limiting
EJX                  Dental anchor
NDP                  Dental impression spacer
NDP                  Dental implant abutment impression cap
NDP                  Dental implant abutment analog, laboratory
NDP                  Dental precision attachment simulator/analog, single-use
EBF                  Custom-made dental composite resin kit
NDP                  Steel dental bur
{DZE, NHA}           {Fluted surgical drill bit, reusable, Screw endosteal dental implant, two-piece}
{NHA, DZE}           {Fluted surgical drill bit, reusable, Screw endosteal dental implant, two-piece}
{NHA, DZE}           {Screw endosteal dental implant, two-piece, Fluted surgical drill bit, reusable}
EBG                  Dental bridge, polymer
EBG                  Dental crown, polymer
EBW                  Dental implant system
NDP                  Custom-made orthopaedic surgical guide, non-sterile
EBI                  Dental bridge, polymer
EBI                  Dental crown, polymer
EIH                  Dental bridge, ceramic
NHA                  Dental appliance fabrication material, ceramic
NQA                  Periodontal root surface regeneration material
NHA                  Dental bridge, metal-ceramic
NPK                  Hydrogel dental regeneration membrane
ELB                  Dental implant debridement brush
DZE                  Dental casting wax
DZE                  Dental implant prosthetic teeth bar
NHA                  Bar dental precision attachment
OAT                  Dental implant suprastructure, temporary, preformed, single-use
OAT                  Dental implant suprastructure, permanent, preformed
DZL                  Screw endosteal dental implant, one-piece
DZE                  Dental implant suprastructure kit
NHA                  Dental casting wax
EHO                  Dental implant suprastructure, permanent, preformed
EJH                  Dental bridge, metal-ceramic
NHA                  Dental implant prosthetic teeth bar
EJR                  Dental abrasive powder
ELC                  {Ultrasonic dental scaling/debridement system, Dental abrasive air jet system}
KOJ                  Dental abrasive air jet system
EFB                  Dental abrasive air jet system handpiece
DZI                  Dental ultrasonic surgical system handpiece
EFB                  Dental abrasive air jet system
ELC                  {Dental abrasive air jet system, Ultrasonic dental scaling/debridement system}
ELB                  Ultrasonic dental scaling/debridement system
KOJ                  {Ultrasonic dental scaling/debridement system handpiece tip, periodontal, Dental abrasive air j...
KOJ                  Electromechanical device/system transport trolley
EJR                  Electromechanical device/system transport trolley
EFB                  Dental abrasive powder
KOJ                  Foot-switch, electrical
EFB                  Foot-switch, electrical
MQN                  Orthopaedic surgical procedure kit, non-medicated, reusable
EIA                  Surgical irrigation/aspiration tubing set
JEY                  Polyethylene craniofacial tissue reconstructive material
EIA                  Surgical instrument/endoscope cleaning brush/tool, reusable
EIA                  Sterilization/disinfection container
EIA                  Drilling power tool attachment, basic
JEY                  Surgical implant template, single-use
NPK                  Synthetic bone graft
JEY                  Craniofacial alignment rod
DZJ                  Foot-switch, electrical
DZE                  Craniofacial fixation plate, non-bioabsorbable
EIA                  Surgical power tool hand-switch
NPL                  Dental soft-tissue matrix implant, animal-derived
{NPM, NPL}           {Dental bone matrix implant, animal-derived, Collagen dental regeneration membrane}
{NPL, NPM}           {Collagen dental regeneration membrane, Dental bone matrix implant, animal-derived}
PLV                  Surgical planning/navigation-enhancement system
NXV                  {Oral lesion examination light, Medical equipment handle cover, single-use, non-sterile, Optica...
NXV                  {Medical equipment handle cover, single-use, non-sterile, Oral lesion examination light, Optica...
NXV                  Medical equipment handle cover, single-use, non-sterile
NXV                  Optical medical device procedural cover
KOO                  Dental impression adhesive
EFD                  Two-component dental material applicator, electric
{ELW, EID}           Silicone dental impression material
{EID, ELW}           Silicone dental impression material
{EHY, EID, EBG, E... Dental crown/bridge resin, temporary
{EBF, JEW}           Dental etching solution
{EBF, EID}           Dental etching solution
{EBF, KXR, JEW, KLE} Dentine bonding agent/set
{EID, EBG}           Dental crown/bridge resin, temporary
{EJK, EID}           Calcium hydroxide suspension
{ELW, EBG, EMA, E... Dental crown/bridge resin, temporary
{EBG, EID}           Dental crown/bridge resin, temporary
EJR                  Dental polishing brush
EHY                  Facebow
{ELW, EID, EHY}      Silicone dental impression material
{EID, ELW, EHY}      Silicone dental impression material
JES                  Gingival retraction cord, medicated
{EBF, EID}           Endodontic filling/sealing material
{EID, EBF}           Endodontic filling/sealing material
{EMA, EID}           Fatty acid dental cement
EMA                  Dental unfilled resin sealant/coating
NHA                  Transgingival implant
NHA                  Intramucosal dental implant
NDP                  Surgical drill guide, single-use
DZE                  Transgingival implant
DZE                  Dental implant x-ray template
EJL                  Fluted surgical drill bit, reusable
{NHA, PNP}           Dental implant suprastructure, permanent, preformed
{PNP, NHA}           Dental implant suprastructure, permanent, preformed
PNP                  CAD/CAM software
{NOF, NHA}           CAD/CAM software
{NHA, NOF}           Dental CAD/CAM system, laboratory
{NOF, NHA}           Dental CAD/CAM system, laboratory
NHA                  Dental CAD/CAM system, laboratory
DZI                  Fixture/appliance dental drill bit, single-use
DZI                  Dental implantation drilling template retention pin
ELL                  Dental bridge, ceramic
EJH                  Dental implant suprastructure, permanent, preformed
{NHA, PNP}           Dental implant suprastructure, temporary, preformed, single-use
{PNP, NHA}           Dental implant suprastructure, temporary, preformed, single-use
NHA                  Dental implant suprastructure, temporary, preformed, reusable
DZI                  Bone tap, single-use, sterile
{DZE, NHA}           Dental implant suprastructure, permanent, preformed
{NHA, DZE}           Dental implant suprastructure, permanent, preformed
DZI                  Dental implant/prosthesis surgical procedure kit
DZI                  Gingiva-coring punch, reusable
DZI                  Fluted surgical drill bit, single-use, sterile
DZI                  Dental/maxillofacial surgical procedure kit, medicated, single-use
DZI                  Manual bone mill
DZE                  Dental laboratory power tool system
DZE                  Screw extractor, single-use
DZE                  Dental/maxillofacial surgical procedure kit, medicated, single-use
DZI                  Fluted surgical drill bit, single-use, non-sterile
DZI                  Bone tap, single-use, non-sterile
EGG                  Dental implant suprastructure, permanent, preformed
ELL                  Dental implant suprastructure, temporary, preformed, single-use
DZI                  Dental/maxillofacial surgical procedure kit, non-medicated, reusable
DZI                  Surgical screwdriver, reusable
DZA                  Fluted surgical drill bit, reusable
NDP                  Gingiva-coring punch, reusable
NDP                  Surgical mallet
NDP                  Dental osteotome set
DZA                  Bone trephine
DZA                  Surgical countersink, reusable
NDP                  Sterilization/disinfection container
NDP                  Dental implant/syringe connector
NDP                  Surgical screwdriver, single-use, non-sterile
NDP                  Surgical torque wrench, reusable
NDP                  Composite dental impression material
NDP                  Dental impression tray, single-use
{NHA, DZE}           Screw endosteal dental implant, two-piece
NDP                  Screw endosteal dental implant, two-piece
{DZE, NHA}           Screw endosteal dental implant, two-piece
EGG                  Sliding dental precision attachment
NDP                  Dental prosthesis/implant abutment screw analog, reusable
OFY                  Dental implant/prosthesis surgical procedure kit
NHA                  Fixture/appliance dental drill bit, reusable
NHA                  Surgical screwdriver, reusable
{NHA, DZE}           Dental implant suprastructure kit
{DZE, NHA}           Dental implant suprastructure kit
NDP                  Dental prosthesis/implant abutment screw
NHA                  Dental implant abutment analog, laboratory
NHA                  Dental implant abutment analog, scanning
NHA                  Transmandibular implant
DZE                  Basket endosteal dental implant, two-piece
{DZE, NHA}           Basket endosteal dental implant, two-piece
DZA                  Basket endosteal dental implant, two-piece
NHA                  Basket endosteal dental implant, two-piece
{NHA, DZE}           Basket endosteal dental implant, two-piece
DZI                  Periodontal probe, reusable
NHA                  Dental prosthesis/implant abutment screw analog, reusable
DZI                  Dental osteotome
DZI                  Dental osteotome set
DZI                  Dental torque wrench
NHA                  Surgical mallet
NHA                  Dental implantation depth/angle gauge, reusable
NDP                  Dental implant abutment analog, scanning
EJL                  Dental torque wrench
EJL                  Borna disease virus immunoglobulin G (IgG) antibody IVD, reagent
DZN                  Dental implant/prosthesis surgical procedure kit
NDP                  Dental osteotome
KOJ                  Ultrasonic dental scaling/debridement system
KOJ                  Dental abrasive air jet system control unit
KOJ                  Dental abrasive air jet system handpiece
NPM                  Dental bone matrix implant, synthetic
ELC                  Dental drilling system attachment
ELC                  Dental power tool system, pneumatic
PZY                  Resin artificial teeth
KLE                  Dental cavity varnish
{LBH, KLE}           Dentine bonding agent/set
{KLE, LBH}           Dentine bonding agent/set
EBF                  Dental appliance fabrication material, thermoplastic
EID                  Polyether dental impression material
DYJ                  Orthodontic teeth positioner, preformed
EJF                  Orthodontic bracket, ceramic
DYO                  Orthodontic metal band
DZD                  Orthodontic bracket, metal
EGG                  Orthodontic bracket, metal
ECI                  Orthodontic metal band pusher
ECO                  Orthodontic wire
DZC                  Orthodontic wire
KCR                  Orthodontic extraoral headgear
EEJ                  Orthodontic teeth positioner, preformed
EHO                  Orthodontic retainer
EHO                  Orthodontic wire
DYW                  Orthodontic bracket, metal
EHP                  Orthodontic wire
EHP                  Orthodontic teeth positioner, preformed
KCR                  Orthodontic tube
DYJ                  Orthodontic appliance system, adjustable
DZC                  Dental brazing alloy
ECN                  Orthodontic tube
EGG                  Orthodontic wire
ECN                  Orthodontic wire
NDP                  Orthodontic appliance system, adjustable
OAT                  Surgical screwdriver, reusable
DZA                  Steel dental bur
NDP                  Orthodontic teeth positioner, preformed
OAT                  Orthodontic teeth positioner, preformed
OAT                  Orthodontic tube
OAT                  Orthodontic wire
OAT                  Steel dental bur
NDP                  Orthodontic anchoring screw
EME                  Gingiva-coring punch, single-use
EBL                  Sliding dental precision attachment
EBL                  Root canal post, preformed
KMY                  Orthodontic appliance system, adjustable
KMY                  Orthodontic teeth positioner, preformed
EGD                  Bite registration rim
EJL                  Dental abrasive point, reusable
EJH                  Orthodontic bracket, metal
EIG                  Orthodontic pliers
EEJ                  Orthodontic appliance remover
DZN                  Surgical instrument maintenance lubricant
ECT                  Orthodontic metal band pusher
DZN                  Orthodontic ligature director
EIL                  Orthodontic metal band pusher
DZN                  Orthodontic metal band pusher
EJB                  Orthodontic metal band pusher
EFL                  Orthodontic pliers
DZN                  Dental mirror, reusable
ECP                  Orthodontic ligature director
EJB                  Dental abrasive strip, single-use
ECR                  Orthodontic metal band pusher
DZN                  Orthodontic pliers
EBF                  Zinc sulfate dental cement
EBF                  Dentine bonding agent/set
EBF                  Daptomycin susceptibility testing disc IVD
EMA                  Dental crown/bridge, temporary
{EBF, KLE}           Resin dental inlay
{DZN, KLE, EMA, EID} {Dental etching solution, Dental composite resin, Dentine bonding agent/set, Dental material in...
{ELW, EID}           {Polyether dental impression material, Dental impression adhesive, Dental material mixing nozzl...
{EID, EBG}           {Dental crown/bridge, temporary, Dental material mixing nozzle, non-sterile}
{DZN, KLE}           {Dental etching solution, Dental material injection cannula, single-use, Dentine bonding agent/...
{KLE, DZN}           {Dental material injection cannula, single-use, Dentine bonding agent/set, Dental etching solut...
{EID, EBG}           {Dental material mixing nozzle, non-sterile, Dental crown/bridge, temporary}
{EBG, EID}           {Dental material mixing nozzle, non-sterile, Dental crown/bridge, temporary}
{EBG, EID}           {Dental crown/bridge, temporary, Dental material mixing nozzle, non-sterile}
EBH                  Dental impression adhesive
{EBF, ELR, EMA, K... {Dentine bonding agent/set, Dental material injection cannula, single-use, Dental composite res...
{EMA, ELR, EID, DZA} {Dental material injection cannula, single-use, Dental material mixing nozzle, non-sterile, Den...
EBZ                  Dental laboratory curing unit
{KLE, EBF}           {Dentine bonding agent/set, Denture reliner, hard}
PIP                  Dental abrasive powder
EMA                  {Glass ionomer dental cement, Dentine bonding agent/set, Two-component dental material applicat...
{KLE, EMA}           {Dental unfilled resin sealant/coating, Two-component dental material applicator, manual, Glass...
{ELW, EID}           {Silicone dental impression material, Dental material mixing nozzle, non-sterile}
{EFD, ELW, EID}      {Dental impression adhesive, Silicone dental impression material, Dental impression material mi...
{EID, ELW}           {Dental impression adhesive, Silicone dental impression material, Dental material mixing nozzle...
{EID, ELW}           {Dental impression adhesive, Dental material mixing nozzle, non-sterile, Silicone dental impres...
KOJ                  Dental composite resin kit
{ELW, EID}           {Silicone dental impression material, Two-component dental material applicator, manual, Dental ...
{ELW, EID}           {Silicone dental impression material, Dental material mixing nozzle, non-sterile, Two-component...
{EID, ELW}           {Silicone dental impression material, Dental material mixing nozzle, non-sterile}
{ELW, EID}           {Dental material mixing nozzle, non-sterile, Silicone dental impression material}
{EID, ELW}           {Dental material mixing nozzle, non-sterile, Silicone dental impression material}
{ELW, EID}           {Dental material mixing nozzle, non-sterile, Dental material injection cannula, single-use, Sil...
{ELW, EID}           {Silicone dental impression material, Dental material mixing nozzle, non-sterile, Dental materi...
{EID, ELW}           {Silicone dental impression material, Dental material mixing nozzle, non-sterile, Dental materi...
{EID, EFD, ELW}      {Dental impression material mixer, Dental impression adhesive, Dental material injection cannul...
{EFD, EID, ELW}      {Dental impression material mixer, Dental material injection cannula, single-use, Dental materi...
{ELW, EFD, EID}      {Dental material mixing nozzle, non-sterile, Dental impression adhesive, Dental impression mate...
{EID, DZA, ELR, EMA} {Dental composite resin, Dental material injection cannula, single-use, Dental material mixing ...
{EID, EMA}           {Dental composite resin, Dental material injection cannula, single-use, Dental material mixing ...
{EMA, EID}           {Dental material injection cannula, single-use, Dental material mixing nozzle, non-sterile, Den...
{EID, EMA}           {Dental material mixing nozzle, non-sterile, Dental composite resin, Dental material injection ...
{EID, EMA}           {Dental material injection cannula, single-use, Dental material mixing nozzle, non-sterile, Den...
{EMA, EID}           {Dental composite resin, Dental material mixing nozzle, non-sterile, Dental material injection ...
{DZN, KLE}           {Dentine bonding agent/set, Dental etching solution, Dental material injection cannula, single-...
{DZN, KLE}           {Dental material injection cannula, single-use, Dentine bonding agent/set, Dental etching solut...
{DZN, KLE}           {Dental material injection cannula, single-use, Dental etching solution, Dentine bonding agent/...
{EID, DZN, EMA, KLE} {Dental material injection cannula, single-use, Dental material mixing nozzle, non-sterile, Den...
{EMA, EID, KLE, DZN} {Dental material mixing nozzle, non-sterile, Dentine bonding agent/set, Dental etching solution...
{EMA, EID, KLE, DZN} {Dental etching solution, Dentine bonding agent/set, Dental material injection cannula, single-...
{EMA, EID}           {Dental composite resin, Dental material injection cannula, single-use, Dental material mixing ...
{EMA, EID}           {Dental material injection cannula, single-use, Dental composite resin, Dental material mixing ...
{EMA, EID}           {Dental material mixing nozzle, non-sterile, Dental composite resin, Dental material injection ...
{EBH, ELW, EFD, EID} {Polyether dental impression material, Dental impression adhesive, Dental material mixing nozzl...
{ELW, EID, EFD, EBH} {Dental material injection cannula, single-use, Dental material mixing nozzle, non-sterile, Pol...
{ELW, EID, EBH}      {Dental impression adhesive, Dental material injection cannula, single-use, Polyether dental im...
{EID, EBH, ELW}      {Dental impression adhesive, Polyether dental impression material, Dental material injection ca...
{EID, ELW}           {Silicone dental impression material, Neurofilament light protein IVD, calibrator}
{ELW, EID}           {Dental material mixing nozzle, non-sterile, Polyether dental impression material}
{ELW, EID}           {Polyether dental impression material, Dental material mixing nozzle, non-sterile}
{EBF, EBG, EID, EMA} {Fatty acid dental cement, Two-component dental material applicator, manual, Dental composite r...
{EMA, EID}           {Dental material mixing nozzle, non-sterile, Dental material injection cannula, single-use, Den...
{EID, EMA}           {Dental material injection cannula, single-use, Dental composite resin, Dental material mixing ...
EBG                  Fatty acid dental cement
EJH                  Dental composite resin kit
{EID, ELW}           {Dental material mixing nozzle, non-sterile, Polyether dental impression material}
{EID, ELW, EBH}      {Dental material mixing nozzle, non-sterile, Two-component dental material applicator, manual, ...
{EID, EBH, EFD, ELW} {Dental material mixing nozzle, non-sterile, Dental impression adhesive, Polyether dental impre...
{EBH, ELW, EID, EFD} {Two-component dental material applicator, manual, Polyether dental impression material, Dental...
{EID, EMA}           {Dental composite resin, Two-component dental material applicator, manual}
{EID, EMA}           {Dental material injection cannula, single-use, Dental composite resin}
{EMA, EID}           {Dental material injection cannula, single-use, Dental composite resin}
{EMA, EID}           {Dental composite resin, Dental material injection cannula, single-use}
{EID, EMA}           {Dental material injection cannula, single-use, Two-component dental material applicator, manua...
ELW                  {Silicone dental impression material, Dental material mixing nozzle, non-sterile}
EBF                  Denture reliner, hard
{EBG, EID}           {Dental crown/bridge, temporary, Two-component dental material applicator, manual}
{EID, EBG}           {Dental crown/bridge, temporary, Two-component dental material applicator, manual}
{EBF, KOJ, KLE}      {Denture reliner, hard, Dentine bonding agent/set, Dental composite resin kit}
{KLE, EBF}           {Dental composite resin kit, Dentine bonding agent/set, Denture reliner, hard}
{EBG, EID}           {Two-component dental material applicator, manual, Dental crown/bridge, temporary}
EBD                  Glass ionomer dental cement
{KLE, EJH}           {Dentine bonding agent/set, Dental composite resin kit}
{EID, ELW}           {Two-component dental material applicator, manual, Polyether dental impression material}
EBF                  Dental laboratory curing unit
KLE                  Dental unfilled resin sealant/coating
{EID, EMA}           {Two-component dental material applicator, manual, Glass ionomer dental cement}
{EMA, EID}           {Two-component dental material applicator, manual, Glass ionomer dental cement}
KLE                  Dental composite resin kit
KLC                  Dental bib
KLC                  Instrument/equipment drape, single-use, non-sterile
{ELM, ELL, EJH}      {Partial denture, Dental bridge, ceramic, Dental bridge, metal-ceramic}
{ELL, EJH}           {Partial denture, Dental bridge, ceramic, Dental bridge, metal-ceramic}
{ELL, EJH}           {Dental bridge, ceramic, Dental bridge, metal-ceramic}
{EJH, ELL}           {Dental bridge, ceramic, Dental bridge, metal-ceramic}
ELM                  Partial denture
NXC                  {Orthodontic appliance system, progressive, Orthodontic retainer}
MDL                  Audiometer testing system
ELC                  Dental ultrasonic surgical system handpiece
DZI                  Ultrasonic dental scaling/debridement system handpiece tip, endodontic
DZL                  Dental ultrasonic surgical system handpiece tip
ELC                  Dental ultrasonic surgical system handpiece tip
EHS                  Denture cushion
NBL                  Dental surgical microscope
EHD                  Stationary panoramic/tomographic dental x-ray system, digital
EIA                  Dental delivery system
EAZ                  LED dental light, line-powered
EHD                  Dental digital imaging sensor, intraoral
KLC                  Dental chair, electric
NDP                  Manual bone mill
NDP                  Fixture/appliance dental drill bit, single-use
NDP                  Bone tap, reusable
NDP                  Hand-held dental retractor
NDP                  Bone trephine
NDP                  Surgical countersink, reusable
PNN                  CAD/CAM software
NOF                  CAD/CAM software
NDP                  Dental CAD/CAM system, laboratory
NOF                  Intraoral optical scanning system
EJP                  Dental CAD/CAM system, laboratory
EGM                  Dental anaesthesia syringe, intraligamentary
DZE                  Subperiosteal dental implant material
JEY                  Custom-made orthopaedic surgical guide, non-sterile
JEY                  Cranial bone prosthesis, custom-made
JEY                  Custom-made organ/bone anatomy model/surgical guide kit
{EBF, EBC}           Light-cured dental restorative composite resin
{EBC, EBF}           Light-cured dental restorative composite resin
EMA                  Hygroscopic dental cement
DZI                  Surgical countersink, reusable
NDP                  {Dental implant/prosthesis surgical procedure kit, Surgical screwdriver, reusable}
DZA                  Bone tap, reusable
DZA                  Manual bone mill
DZA                  Surgical screwdriver, reusable
EBH                  Dental base plate
EBI                  Denture base resin kit
EMA                  Gynaecological biopsy forceps, reusable
{EBF, EBG, EBI}      Dental appliance fabrication material, thermoplastic
{EBI, EBG, EBF}      Dental appliance fabrication material, thermoplastic
{MUH, EHD}           Stationary intraoral dental x-ray system, analogue
{EHD, MUH}           Stationary intraoral dental x-ray system, analogue
ELC                  {Ultrasonic dental scaling/debridement system handpiece, Ultrasonic dental scaling/debridement ...
ELC                  {Ultrasonic dental scaling/debridement system handpiece tip, periodontal, Ultrasonic dental sca...
EIF                  Dental cheek retractor, professional, single-use
{DZE, NHA}           Dental implant system
EBI                  Dental prosthesis fabrication material, polymer
EKX                  {Dental power tool system handpiece, remotely-driven, Line-powered dental drilling/sawing syste...
ELC                  {Ultrasonic dental scaling/debridement system generator, Ultrasonic dental scaling/debridement ...
EKX                  {Remotely-driven dental drilling system motor, Remotely-driven surgical/dental system drive cable}
EKX                  {Line-powered dental drilling/sawing system handpiece, Dental power tool system handpiece, remo...
EKX                  {Dental power tool system, line-powered, Line-powered dental drilling system, Surgical power to...
EKX                  Remotely-driven surgical/dental system drive cable
DZH                  {Surgical power tool system handpiece, sawing, line-powered, Sawing power tool attachment, sagi...
ELC                  {Dental ultrasonic surgical system handpiece, Ultrasonic dental scaling/debridement system hand...
ELC                  {Dental ultrasonic surgical system generator, Ultrasonic dental scaling/debridement system gene...
ELC                  {Dental ultrasonic surgical system generator, Dental ultrasonic surgical system, Ultrasonic den...
EKX                  {Dental power tool system handpiece, remotely-driven, Remotely-driven dental drilling system mo...
ELC                  {Ultrasonic dental scaling/debridement system handpiece tip, periodontal, Ultrasonic dental sca...
ELC                  {Ultrasonic dental scaling/debridement system handpiece, Dental ultrasonic surgical system hand...
EKX                  Dental laboratory drilling system motor
EKX                  Remotely-driven dental drilling system motor
DZH                  {Surgical power tool system handpiece, sawing, line-powered, Sawing power tool attachment, osci...
DZH                  {Surgical power tool system handpiece, sawing, line-powered, Line-powered dental drilling/sawin...
EKX                  {Remotely-driven surgical/dental system drive cable, Dental laboratory drilling system handpiec...
EKX                  Dental laboratory drilling system handpiece
EKX                  {Dental laboratory drilling system motor, Dental laboratory drilling system handpiece, Remotely...
EKX                  {Remotely-driven surgical/dental system drive cable, Remotely-driven dental drilling system motor}
EKX                  {Surgical power tool system control unit, line-powered, Line-powered dental drilling system, De...
EKX                  {Line-powered dental drilling system, Surgical power tool system control unit, line-powered, De...
EKX                  {Dental power tool system, line-powered, Surgical power tool system control unit, line-powered,...
EKX                  {Dental laboratory power tool system, Line-powered dental drilling system, Dental power tool sy...
EKX                  {Dental power tool system, line-powered, Dental laboratory power tool system, Line-powered dent...
{DZI, ELC}           Dental ultrasonic surgical system handpiece tip
{ELC, DZI}           Dental ultrasonic surgical system handpiece tip
{ELC, DZI}           Dental ultrasonic surgical system
{DZI, ELC}           Dental ultrasonic surgical system
{EFB, ELC, EGS}      Pneumatic dental scaling/debridement system handpiece
ELC                  Pneumatic dental scaling/debridement system handpiece
KMW                  Dental power tool system handpiece, line-powered
KMW                  Surgical irrigation tubing set, single-use
{EGS, KMW}           Dental power tool system handpiece, line-powered
{KMW, EGS}           Dental power tool system handpiece, line-powered
{ELC, EGS, EFB}      Pneumatic dental scaling/debridement system handpiece
{EGS, EFB, ELC}      Pneumatic dental scaling/debridement system handpiece
EBW                  Surgical irrigation tubing set, reusable
KMW                  Sawing power tool attachment, sagittal
KMW                  Sawing power tool attachment, oscillating
KMW                  Sawing power tool attachment, reciprocating
{EGS, ELC, EFB}      Pneumatic dental scaling/debridement system handpiece
KMW                  Oscillating surgical saw blade, reusable
LYC                  Dental bone matrix implant, animal-derived
{ELC, EFB, EGS}      Pneumatic dental scaling/debridement system handpiece
KMW                  Sagittal surgical saw blade, reusable
KMW                  Reciprocating surgical saw blade, reusable
EKX                  Endodontic enlarger, reusable
EBI                  {Denture reliner, elastic, long-term, Denture reliner, elastic, short-term}
EBI                  {Denture reliner, elastic, short-term, Denture reliner, elastic, long-term}
KLE                  Denture reliner, hard
{KLE, EMA}           {Dentine bonding agent/set, Dental composite resin}
LBH                  {Dental cavity varnish, Dental coating, tooth-desensitizing}
LBH                  {Dental coating, tooth-desensitizing, Dental cavity varnish}
EIA                  Surgical instrument maintenance lubricant
EIA                  Line-powered surgical power tool system motor
DZJ                  Rechargeable battery-powered surgical power tool system motor
EIA                  Foot-switch, electrical
EIA                  Electrical-only medical device connection cable, reusable
NDP                  Orthopaedic surgical procedure kit, non-medicated, reusable
NDP                  Manual orthopaedic bender, reusable
EJL                  Diamond dental bur, single-use
JEY                  Orthopaedic surgical procedure kit, non-medicated, single-use
EIA                  Intravenous pole
EIA                  Sawing power tool attachment, reciprocating
DZI                  Sawing power tool attachment, oscillating
EIA                  Sawing power tool attachment, oscillating
EJL                  Orthopaedic bur, single-use
EJH                  Rectal scissors
EMH                  Orthopaedic joint/limb rongeur
EIG                  Skin/tissue hook
EMH                  Rigid endoscopic sponge/swab forceps
EIG                  Enteral feeding/medication connector, non-sterile
EMH                  Wrist restraint
EMH                  Bone approximation clamp
EMH                  Arthroscopic probe
EIG                  Bone curette, reusable
{ELW, EFD, MVL, EID} {Dental material mixing nozzle, non-sterile, Gingival retraction kit, Dental material injection...
{MVL, EFD, ELW, EID} {Gingival retraction kit, Dental material injection cannula, single-use, Polyether dental impre...
{EID, ELW, MVL, EFD} {Dental material injection cannula, single-use, Dental impression adhesive, Dental material mix...
{EID, ELW}           {Dental material injection cannula, single-use, Polyether dental impression material, Dental ma...
{EID, ELW}           {Polyether dental impression material, Dental material mixing nozzle, non-sterile}
EFB                  Dental drilling system attachment
EIA                  Sialendoscope
EIA                  Rigid endoscope telescope
DZN                  Surgical instrument handle, non-torque-limiting
JEY                  Internal orthopaedic fixation system, plate/screw, non-bioabsorbable, non-sterile
JEY                  Internal orthopaedic fixation system, plate/screw, non-bioabsorbable, sterile
JEY                  General/plastic surgery bur
JEY                  Orthopaedic fixation plate bending insert, reusable
JEY                  Cranial bur, reusable
JEY                  Orthopaedic fixation implant alignment tool
EJI                  Dental anaesthesia syringe, intraligamentary
{EID, EMA}           {Glass ionomer dental cement, Two-component dental material applicator, manual}
{DZA, EID, ELR, K... {Dental material injection cannula, single-use, Dentine bonding agent/set, Dental material mixi...
{ELR, EMA, DZA, EID} {Dental material mixing nozzle, non-sterile, Dental material injection cannula, single-use, Roo...
{KLE, EBF}           {Denture reliner, hard, Dentine bonding agent/set}
EMA                  {Glass ionomer dental cement, Two-component dental material applicator, manual, Dentine bonding...
{EMA, KLE}           {Glass ionomer dental cement, Two-component dental material applicator, manual, Dentine bonding...
{EFD, EID, ELW}      {Silicone dental impression material, Dental material injection cannula, single-use, Dental imp...
{EID, ELW}           {Dental material mixing nozzle, non-sterile, Silicone dental impression material, Dental impres...
{EID, ELW}           {Two-component dental material applicator, manual, Dental material mixing nozzle, non-sterile, ...
{ELW, EID}           {Two-component dental material applicator, manual, Silicone dental impression material, Dental ...
{EID, ELW}           {Dental material mixing nozzle, non-sterile, Dental material injection cannula, single-use, Sil...
{ELW, EID}           {Dental material injection cannula, single-use, Dental material mixing nozzle, non-sterile, Sil...
{EFD, EID, ELW}      {Dental material injection cannula, single-use, Dental impression adhesive, Silicone dental imp...
{EID, ELW, EFD}      {Silicone dental impression material, Dental material injection cannula, single-use, Dental mat...
{EFD, ELW, EID}      {Dental impression adhesive, Dental material injection cannula, single-use, Dental impression m...
{EMA, DZA, ELR, EID} {Dental composite resin, Dental material mixing nozzle, non-sterile, Root canal post, preformed...
{EID, EMA}           {Dental composite resin, Dental material mixing nozzle, non-sterile, Dental material injection ...
{KLE, DZN}           {Dentine bonding agent/set, Dental etching solution, Dental material injection cannula, single-...
{DZN, EID, KLE, EMA} {Dental material mixing nozzle, non-sterile, Dentine bonding agent/set, Dental material injecti...
{EID, KLE, EMA, DZN} {Dentine bonding agent/set, Dental material injection cannula, single-use, Dental composite res...
{DZN, EID, KLE, EMA} {Dental etching solution, Dentine bonding agent/set, Dental composite resin, Dental material in...
{EID, EMA}           {Dental material mixing nozzle, non-sterile, Dental material injection cannula, single-use, Den...
{EBH, ELW, EID, EFD} {Dental impression adhesive, Polyether dental impression material, Dental material mixing nozzl...
{ELW, EFD, EID, EBH} {Dental material injection cannula, single-use, Dental material mixing nozzle, non-sterile, Pol...
{EBH, EID, ELW}      {Dental material mixing nozzle, non-sterile, Polyether dental impression material, Dental mater...
{ELW, EBH, EID}      {Dental impression adhesive, Polyether dental impression material, Dental material mixing nozzl...
{ELW, EID}           {Neurofilament light protein IVD, calibrator, Silicone dental impression material}
{EMA, EBG, EID, EBF} {Dental composite resin, Dental crown/bridge, temporary, Dental material mixing nozzle, non-ste...
{EID, ELW, EBH}      {Dental material mixing nozzle, non-sterile, Polyether dental impression material, Two-componen...
{ELW, EID, EBH, EFD} {Dental impression adhesive, Polyether dental impression material, Dental material mixing nozzl...
{EID, EBH, ELW, EFD} {Polyether dental impression material, Dental material mixing nozzle, non-sterile, Two-componen...
{EMA, EID}           {Two-component dental material applicator, manual, Dental composite resin}
{EID, EMA}           {Two-component dental material applicator, manual, Dental composite resin}
{EMA, EID}           {Two-component dental material applicator, manual, Dental material injection cannula, single-us...
ELW                  {Dental material mixing nozzle, non-sterile, Silicone dental impression material}
{EID, EBG}           {Two-component dental material applicator, manual, Dental crown/bridge, temporary}
{EBF, KLE, KOJ}      {Denture reliner, hard, Dentine bonding agent/set, Dental composite resin kit}
{KLE, EBF}           {Dentine bonding agent/set, Dental composite resin kit, Denture reliner, hard}
{KLE, EJH}           {Dental composite resin kit, Dentine bonding agent/set}
EBI                  Denture repair kit, professional
EIH                  Dental prosthesis dye
JER                  Denture cleanser
EHY                  Dental impression adhesive
EFS                  Dental delivery system irrigation handpiece
EBG                  Dental pulp-capping material
EBF                  Dental coating, tooth-desensitizing
EKW                  Endodontic broach, serrated, reusable
EBG                  Dental appliance fabrication material, cured
EJH                  Denture clasp, metal, custom-made
EGD                  Denture clasp, metal, custom-made
EGG                  Magnetic dental precision attachment
KLE                  Dental bridge, metal-polymer
{EMA, EBC, EBF}      Dental composite resin
NPZ                  Dental bone matrix implant, animal-derived
NHA                  {Dental implant suprastructure, permanent, preformed, Dental prosthesis/implant abutment screw}
NHA                  {Dental prosthesis/implant abutment screw, Dental implant suprastructure, permanent, preformed}
EGS                  Line-powered dental drilling/sawing system handpiece
EGS                  Surgical irrigation tubing set, single-use
DZI                  Remotely-driven dental drilling system motor
DZI                  Surgical irrigation tubing set, single-use
EJB                  Dental material application tool, reusable
DYH                  {Dental unfilled resin sealant/coating, Dental etching solution}
NDP                  Dental appliance fabrication material, cured
{KLE, EMA}           Dental composite resin
{EMA, KLE}           Dental composite resin
EBF                  Dental crown, polymer
{LBH, PME}           Dental restoration fixation cleaning solution
EMA                  Dental composite resin kit
{EMA, EBF, KLE}      Dentine bonding agent/set
{KLE, EBF, EMA}      Dentine bonding agent/set
{EBF, KLE}           Dental composite resin kit
{KLE, EBF, EBD}      {Dentine bonding agent/set, Dental prosthesis priming agent}
{EMA, KLE, EBF}      Dental composite resin kit
{EBF, KLE, EMA}      Dental composite resin kit
EBW                  Dental delivery system
EIA                  Multi-purpose digital medical camera
EBW                  Line-powered dental drilling system
NTK                  Dental caries detector, optical induced fluorescence
EBW                  Cardiac ablation system irrigation tubing set
EFB                  Ultrasonic dental scaling/debridement system
EIA                  Line-powered dental drilling system
EFB                  Line-powered dental drilling system
EBF                  Dental abrasive powder
NFS                  Facebow
EJP                  Facebow
KOJ                  Dental power tool system handpiece, line-powered
EHD                  Diagnostic x-ray system generator, hand-held
EIS                  Dental root elevator
ELC                  Dental power tool system handpiece, pneumatic
KIF                  Hygroscopic dental cement
DZE                  Dental anchor
DZN                  Self-ligating orthodontic bracket tool
LQZ                  Mandible-repositioning sleep-disordered breathing orthosis
LYC                  Bone matrix implant, synthetic
{EJK, KIF}           Dental pulp-capping material
EJJ                  Dental amalgam capsule
KIF                  Root canal filling-removal solution
EMA                  Endodontic dressing
EJI                  {Dental anaesthesia syringe, reusable, Dental syringe needle, single-use}
EJI                  {Dental syringe needle, single-use, Dental anaesthesia syringe, reusable}
EJI                  Dental syringe needle, single-use
ELC                  Dental/surgical polymerization lamp
EIA                  Surgical irrigation tubing set, single-use
DZI                  Remotely-driven surgical drilling system motor
EIA                  Dental abrasive air jet system
ELC                  {Ultrasonic dental scaling/debridement system handpiece, Ultrasonic dental scaling/debridement ...
LYC                  Bone matrix implant, animal-derived, non-bioabsorbable
LRK                  Mandible-repositioning/palate-lifting sleep-disordered breathing orthosis
EAT                  Endodontic filling material condenser
EAT                  Endodontic plugger
EIC                  Two-component dental material applicator, manual
EKM                  Warm-bonded endodontic obturation system
EHM                  Dental abrasive point, reusable
EKP                  Endodontic reamer
{EBF, EMA}           Light-cured dental restorative composite resin
DZA                  Dental implant/prosthesis surgical procedure kit
EAY                  Orthopaedic prosthesis implantation instrument, reusable
EIH                  Dental implant suprastructure, permanent, preformed
EBG                  Dental implant suprastructure, permanent, preformed
DZE                  Fixture/appliance dental drill bit, reusable
OAT                  Fixture/appliance dental drill bit, reusable
NDP                  Orthopaedic implantation sleeve, reusable
EBG                  Dental implant suprastructure, temporary, preformed, single-use
DZE                  Dental drill bit extension
NHA                  Gingiva-coring punch, reusable
NHA                  Dental implant extractor
NHA                  Orthopaedic implantation sleeve, reusable
EML                  Orthopaedic prosthesis implantation instrument, reusable
ECP                  Orthopaedic implant impactor
NDP                  Orthopaedic implant impactor
EIG                  Periocular/lacrimal retractor, hand-held, reusable
EIX                  Dental explorer
EKC                  Endodontic plugger
EIG                  Orthopaedic trocar blade, reusable
EIG                  Self-retaining surgical retractor, reusable
MQN                  Craniofacial fixation plate, non-bioabsorbable
EIG                  Tongue depressor, surgical
DZE                  Craniofacial bone screw, non-bioabsorbable, non-sterile
EMK                  Dental root elevator
ECP                  Surgical instrument guard, reusable
EIG                  Bone hook
JEY                  Ultrasonic osteosynthesis system sonotrode tip
JEY                  Craniofacial fixation plate, bioabsorbable
MQN                  Cranial bone prosthesis, custom-made
EJY                  Bone fixation plate pliers
EMN                  Periodontal curette
DZN                  Manual endodontic spreader
DZN                  Dental explorer
DZN                  Dental amalgam condenser, reusable
DZN                  Endodontic plugger
JEY                  Electrical-only medical device connection cable, reusable
JEY                  Ultrasonic osteosynthesis system handpiece
JEY                  Foot-switch, electrical
MQN                  External orthopaedic fixation system, single-use, non-sterile
EIG                  Periosteal elevator, reusable
EJY                  Surgical flat-nosed pliers
EFL                  Dental articulation paper forceps
JEP                  Dental matrix band, reusable
EKC                  Dental amalgam condenser, reusable
EKC                  Dental spatula, reusable
EIY                  Dental amalgam condenser, reusable
EKC                  Dental amalgam carrier
EIG                  Dental osteotome
EIX                  Dental osteotome
EMN                  Periodontal file/rasp
EMN                  Periodontal probe, reusable
DZN                  ENT powder applicator
EAX                  Tooth extraction forceps
EMD                  Surgical soft-tissue manipulation forceps, scissors-like, reusable
EIG                  Mouth gag, adjustable, reusable
DYX                  Craniofacial bone wire/bar
EMN                  Orthopaedic bone pin, non-bioabsorbable
EMJ                  Bone file/rasp, manual
EIG                  Fibreoptic retractor handle
DZN                  Mouth gag, non-adjustable
DZN                  Finger protector, reusable
EJB                  Manual surgical rotary handpiece
EFL                  Dressing/utility forceps, scissors-like, reusable
EGN                  Vascular scissors
EGN                  Tonsil scissors
EMJ                  Hand-held dental retractor
EMA                  Dental tooth-cleaning solution
DZC                  Orthodontic lock
JEX                  Orthodontic ligature director
DZC                  Orthodontic archwire/bracket ligature
DYJ                  Orthodontic spring
ECN                  Orthodontic power arm/lock
OAT                  Organic solvent metabolite IVD, kit, liquid chromatography
EBD                  Dental composite resin
{EBF, EBC}           {Dental pit/fissure sealant, Dental composite resin}
KLE                  {Dental etching solution, Dentine bonding agent/set}
{KLE, EMA, EBC}      {Dental etching solution, Dentine bonding agent/set, Dental composite resin, Dental unfilled re...
DYT                  Dental appliance fabrication material, cured
POW                  Dental composite resin
{EBF, EIH}           Dental appliance fabrication material, ceramic
EBG                  Dental appliance fabrication material, thermoplastic
ELM                  Dental crown, metal/ceramic
ELM                  Dental repair kit, ceramic
EGG                  Bar dental precision attachment
EBI                  Dental repair kit, ceramic
EBF                  Dental veneer, custom-made
EBL                  Screw endosteal dental implant, two-piece
EBF                  Dental bridge, polymer
KOL                  Dental repair kit, ceramic
EBI                  Bar dental precision attachment
DZA                  Screw endosteal dental implant, two-piece
DYH                  Light-cured dental restorative composite resin
DYO                  Orthodontic bracket, metal
{POW, EBG}           Dental crown/bridge, temporary
{EBG, POW}           Dental crown/bridge, temporary
EJH                  Dental appliance fabrication material, ceramic
{ELC, DZI}           {Ultrasonic dental scaling/debridement system, Dental ultrasonic surgical system}
{ELC, DZI}           {Dental ultrasonic surgical system handpiece tip, Ultrasonic dental scaling/debridement system ...
{ELC, DZI}           {Ultrasonic dental scaling/debridement system handpiece tip, periodontal, Dental ultrasonic sur...
{ELC, DZI}           {Ultrasonic dental scaling/debridement system handpiece, Dental ultrasonic surgical system hand...
ELC                  Ultrasonic surgical system torque wrench, reusable
{ELC, DZI}           Ultrasonic surgical system torque wrench, reusable
{ELC, DZI}           {Dental ultrasonic surgical system handpiece tip, Ultrasonic dental scaling/debridement system ...
EHD                  {Mobile intraoral dental x-ray system, digital, Stationary intraoral dental x-ray system, analo...
EHD                  {Stationary intraoral dental x-ray system, digital, Mobile intraoral dental x-ray system, analo...
{MUH, MQB, EHD}      Stationary panoramic dental x-ray system, analogue
{EHD, MQB, MUH}      Stationary panoramic dental x-ray system, analogue
{EHD, MQB, MUH}      Stationary panoramic dental x-ray system, digital
{MQB, EHD, MUH}      Stationary panoramic dental x-ray system, analogue
KHR                  {Dental suction system cannula, single-use, Surgical face mask, single-use}
KHR                  {Surgical face mask, single-use, Dental suction system cannula, single-use}
KHR                  {Dental suction system cannula, single-use, Surgical face mask, single-use, Dental cotton roll}
KHR                  {Dental cotton roll, Surgical face mask, single-use, Dental suction system cannula, single-use}
KHR                  Patient examination/treatment drape, single-use
EBI                  Dentine bonding agent/set
{PNP, NHA}           Dental CAD/CAM system, chairside
{NHA, PNP}           CAD/CAM software
EHD                  Stationary panoramic dental x-ray system, digital
{NHA, PNP}           Dental CAD/CAM system, chairside
{PNP, NHA}           CAD/CAM software
NHA                  CAD/CAM software
{EIA, EBW}           Dental delivery system
EIA                  Ultrasonic dental scaling/debridement system handpiece tip, periodontal
{ELC, EIA}           Ultrasonic dental scaling/debridement system handpiece tip, periodontal
NDP                  CAD/CAM software
EIA                  Dental power tool system handpiece, remotely-driven
EBW                  Dental delivery system irrigation handpiece
{EBW, EIA}           Dental delivery system
{EIA, ELC}           Ultrasonic dental scaling/debridement system handpiece tip, periodontal
EGS                  Surgical instrument maintenance lubricant
{NTK, NBL}           Dental caries detector, optical induced fluorescence
EEG                  Dental bleaching agent
EBD                  Polymer-based dental model material
KZN                  Dental CAD/CAM system, chairside
ELW                  Bite registration rim wax
EBH                  Orthodontic appliance positioning mould, basic
EMA                  Dental prosthesis restorative material, unfilled resin
EBF                  Dental CAD/CAM system, chairside
KLE                  Dental prosthesis restorative material, unfilled resin
KLE                  Dental prosthesis veneer resin
EEG                  Anaesthesia warmer
EJB                  Dental material injection cannula, single-use
{EFC, EEG, EBZ}      Anaesthesia warmer
{EFC, EBZ, EBF, EEG} {Dental composite resin, Anaesthesia warmer}
{EEG, EBF}           {Anaesthesia warmer, Dental composite resin}
KMY                  Dental guided surgery reference plate
{EBF, KLE, EMA}      {Dental composite resin, Dentine bonding agent/set, Dental crown/bridge, temporary}
{KLE, EMA, EBF}      {Dentine adhesive, Dental composite resin}
{EBF, EMA, KLE}      {Dentine adhesive, Dental composite resin}
{EMA, KLE, EBF}      Dental composite resin
{KLE, EBF}           {Dentine adhesive, Dental composite resin}
EBF                  Dentine adhesive
EHY                  Medical device cleaning agent
KMY                  Dental wedge, single-use
EHL                  Dental abrasive disk, reusable
EBF                  Silicone dental impression material
{EHQ, KLE, EMA, E... {Root canal post, preformed, Dental matrix band, single-use, Dentine bonding agent/set}
{EJK, EBF}           Dental composite resin
{EBF, EJK}           Dental composite resin
{EHQ, KLE, EMA, E... {Dental matrix band, single-use, Dental composite resin, Dentine bonding agent/set, Root canal ...
{EKS, DZA, ELR, E... {Pin/post dental drill bit, Root canal post, preformed, Dentine bonding agent/set, Dental compo...
{DZA, ELR}           {Pin/post dental drill bit, Root canal post, preformed}
{ELW, EBI}           {Silicone dental impression material, Denture reliner, hard}
{KLE, EMA}           Dentine bonding agent/set
{EBF, EMA, KLE}      Dentine bonding agent/set
{EMA, KLE}           Dentine bonding agent/set
EBG                  Preformed dental crown, temporary
EFB                  Endodontic filling/sealing material
ELW                  Dental pit/fissure sealant
EGD                  Orthodontic appliance system, adjustable
LBH                  Dental tooth-cleaning solution
DZN                  Dental composite resin
EIG                  Dental occlusal splint, custom-made
EBF                  Ertapenem susceptibility testing disc IVD
EBI                  Glass ionomer dental cement
EIG                  Rubber dam, non-latex
EIH                  Dental etching solution
EIH                  Dental repair kit, ceramic
KLE                  HIV1 antibody IVD, kit, immunochromatographic test (ICT), rapid
EBF                  Dental repair kit, ceramic
EBH                  Dental articulation paste/solution
DYH                  Dental pit/fissure sealant
EBF                  Dental caries detector, optical induced fluorescence
EBW                  Dental laboratory drilling system motor
EIC                  General-purpose syringe, single-use
EIG                  Dental cheek retractor, professional, single-use
KIF                  Dental composite resin
EHK                  Dental polishing cup, reusable
EJQ                  Dental abrasive disk, reusable
EJL                  Dental abrasive disk, reusable
EHM                  Dental abrasive disk, reusable
EIC                  Syringe tip cap
EIC                  Surgical/emergency suction cannula, non-illuminating, single-use
EHK                  Dental abrasive disk, reusable
EIY                  Surgical/emergency suction cannula, non-illuminating, single-use
EID                  Surgical/emergency suction cannula, non-illuminating, single-use
KXR                  Surgical/emergency suction cannula, non-illuminating, single-use
EJQ                  Dental-professional prophylaxis brush, reusable
DZN                  Dental coating, tooth-desensitizing
EKM                  Natural gutta-percha
EFB                  Dental laboratory drilling system motor
DZN                  Tooth separator
DZN                  Syringe tip cap
DZN                  Silicone dental impression material
EIC                  Dental suction system cannula, single-use
EJR                  Ertapenem susceptibility testing disc IVD
EIG                  Dental occlusal splint, preformed
EBH                  Silicone dental impression material
NPK                  Medical equipment handle cover, single-use, non-sterile
DZN                  Orthodontic bracket adhesive
JET                  Dental pick, massaging
JES                  Gingival retraction kit
JES                  Gingival retraction cord, non-medicated
MMD                  Basic electric toothbrush, battery-powered
{KLE, EBF, DYH, EMA} {Dental etching solution, Dentine bonding agent/set, Dental composite resin, Orthodontic bracke...
EHD                  Mobile intraoral dental x-ray system, digital
OYH                  Orthodontic vibrator
NOF                  Dental treatment application software
NRD                  Intraoral camera
EBP                  Denture reliner, soft, home-use
PLC                  Mandible-repositioning sleep-disordered breathing orthosis
{EMA, EJK}           {Dental composite resin, Glass ionomer dental cement}
{EMA, EJK}           {Glass ionomer dental cement, Dental composite resin}
KIF                  {Glass ionomer dental cement, Endodontic filling/sealing material}
EHD                  Stationary extraoral dental x-ray system, analogue
ORY                  Sleep apnoea tongue implant, non-bioabsorbable
ECB                  Dental delivery system
EJI                  Dental anaesthesia syringe cartridge
EGD                  Saliva absorbent
LCN                  Tongue scraper, single-use
PHR                  Dental coating, tooth-desensitizing
KIF                  {Endodontic filling/sealing material, Dental pulp-capping material}
KIF                  {Dental pulp-capping material, Endodontic filling/sealing material}
{DZE, NHA, NDP}      Dental implant system
{NHA, NDP, DZE}      Dental implant system
{NDP, DZE, NHA}      Dental implant system
{NDE, NHA, DZE}      Dental implant system
{NDP, NHA, DZE}      Dental implant system
{NHA, DZE, NDP}      Dental implant system
NPM                  Composite bone graft
DZE                  Dental torque wrench
DZE                  Gingiva-coring punch, reusable
DZE                  Pin/post dental drill bit
DZE                  Surgical screwdriver, reusable
DZE                  Dental implantation depth/angle gauge, reusable
EBF                  Dental material application tool, single-use
OIV                  Dental amalgam
ECR                  Orthodontic appliance system, adjustable
DZJ                  Surgical drill guide, single-use
EJB                  Surgical drill guide, single-use
EBO                  Denture repair kit, home-use
OZR                  General-purpose suction system, line-powered
OZR                  Wax dental impression material
OZR                  Physician-practice-management information system application software
OZR                  Breathing mouthpiece, reusable
OZR                  Electrical-only medical device connection cable, reusable
LRK                  Silicone dental impression material
DYN                  Medicine chamber spacer, reusable
EIA                  Dental delivery system instrument unit, electric
{LQY, EKX, EKR, E... Dental delivery system instrument unit, electric
{LQY, EKX, EKR, E... Laparoscopic wound closure thread
EBF                  Dental restorative unfilled resin kit, standard
KLE                  Dental tooth-cleaning solution
DZE                  Dental implant analog
{NHA, DZE}           Dental implant analog
EFS                  Water jet flosser
JEQ                  Basic electric toothbrush, battery-powered
KMY                  Orthodontic retainer
{EIG, EHY, ELW}      Silicone dental impression material
{ELW, EHY, EIG}      Silicone dental impression material
EJL                  Rotary/reciprocating endodontic file/rasp, reusable
EJL                  Bone trephine
EKB                  Manual endodontic spreader
DZN                  Endodontic file retrieval loop
NYD                  Dental/maxillofacial surgical procedure kit, non-medicated, reusable
{NPZ, NQA}           Periodontal root surface regeneration material
EIL                  Orthodontic appliance dimension gauge
EKB                  Orthodontic metal band pusher
NDP                  Resilient dental precision attachment
NDP                  Bone tack inserter, basic
NDP                  Carbide dental bur, reusable
NDP                  Bone tap, single-use, sterile
NDP                  Dental drilling system attachment
DZL                  Dental implant/prosthesis surgical procedure kit
NDP                  Surgical drill guide, single-use, non-sterile
NDP                  Dental implantation drilling template retention pin
EID                  Bone graft delivery kit
DZL                  General internal orthopaedic fixation system implantation kit
KMW                  General internal orthopaedic fixation system implantation kit
JEY                  General internal orthopaedic fixation system implantation kit
DZL                  Craniofacial bone wire/bar
MQN                  General internal orthopaedic fixation system implantation kit
DZL                  Orthopaedic fixation plate, non-bioabsorbable, sterile
DZL                  Surgical implant template, single-use
KMW                  Surgical power tool system control unit, line-powered
DZL                  Craniofacial bone screw, bioabsorbable
{JEY, MQN}           General internal orthopaedic fixation system implantation kit
DZE                  General internal orthopaedic fixation system implantation kit
LYC                  Pliable-polymer dental regeneration membrane, non-bioabsorbable
NDP                  Bone file/rasp, manual
NDP                  Orthopaedic implant/trial-implant holder, reusable
NDP                  Surgical tamp, reusable
NDP                  Periosteal elevator, reusable
NDP                  Radiographic image marker, manual
NDP                  Margin finishing dental file/rasp, reusable
NDP                  Orthopaedic implant/instrument depth limiter
EBF                  Dental crown/bridge resin, temporary
{EBI, EHP}           Dental appliance fabrication material, thermoplastic
{EHP, EBI}           Dental appliance fabrication material, thermoplastic
NHA                  Partial denture
DZE                  Partial denture
EAZ                  Reflective dental light
NRD                  Dental suction system
NRD                  {Dental suction system, Medical device air compressor}
NRD                  {Medical device air compressor, Dental suction system}
NRD                  Medical device air compressor
MUH                  General-purpose dental x-ray system application software
MUH                  Dental x-ray system collimator
EHD                  Dental x-ray system collimator
MUH                  X-ray tube housing assembly, diagnostic
EHD                  X-ray tube housing assembly, diagnostic
EHD                  Mobile specimen x-ray system, analogue
EJI                  Syringe-loaded injector, manual, professional
EBL                  Dental crown/bridge, temporary
EBL                  Dental occlusal splint, preformed
EJL                  Rotary dental scaler
JEX                  Dental rongeur
EBF                  Dental porcelain/ceramic restoration kit
DZN                  Two-component dental material applicator, manual
EBG                  Dental reinforcing fibre
EBG                  Dental porcelain/ceramic restoration kit
DZL                  Craniofacial bone tack, non-bioabsorbable
JEY                  Periocular/lacrimal retractor, hand-held, reusable
{JEY, DZL}           Orthopaedic fixation implant alignment tool
{JEY, DZJ, LLZ}      Craniofacial fixation plate, non-bioabsorbable
{LLZ, DZJ, JEY}      Craniofacial fixation plate, non-bioabsorbable
EIG                  Orthopaedic retractor
EIF                  Hand-held dental retractor
{JEY, DZL}           Sterilization/disinfection container
JEY                  Bone tap, single-use, non-sterile
{DZL, JEY}           Sterilization/disinfection container
{DZL, JEY}           Orthopaedic fixation implant alignment tool
JEY                  Orthopaedic trocar blade, reusable
JEY                  Sterilization/disinfection container
JEY                  Cranioplasty plate, alterable
JEY                  Orthopaedic retractor
JEY                  Cranioplasty sheet
JEY                  {Fluted surgical drill bit, reusable, Craniofacial bone screw, non-bioabsorbable, sterile, Cran...
NEA                  Orthopaedic cement, non-medicated
JEY                  {Craniofacial bone screw, non-bioabsorbable, sterile, Craniofacial fixation plate, non-bioabsor...
JEY                  {Craniofacial fixation plate, non-bioabsorbable, Craniofacial bone screw, non-bioabsorbable, st...
JEY                  Manual orthopaedic bender, reusable
JEY                  Suction cannula, reusable
JEY                  Surgical instrument handle, non-torque-limiting
DZE                  Orthopaedic bone screw, non-bioabsorbable, non-sterile
MQN                  Orthopaedic bone wire
JEY                  Hand-held dental retractor
JEY                  Orthopaedic implant/trial-implant holder, reusable
JEY                  Surgical drill guide, reusable
EIF                  Mouth gag, non-adjustable
DZN                  ENT elevator
JEY                  Orthopaedic implantable-device cutter
JEY                  Surgical depth gauge, reusable
EIG                  Surgical bulldog clamp, reusable
DZN                  Bone lever/elevator
ECS                  {Orthodontic metal band pusher, Manual dental scaler, reusable}
EJP                  Dental articulator
EHQ                  Dental matrix band, single-use
EJK                  Glass ionomer dental cement
EBH                  Polymer-based dental model material
EBI                  Dental crown/bridge, temporary
EJL                  Fixture/appliance dental drill bit, reusable
EJL                  Dental drill bit extension
EBF                  Dental composite resin kit
{ELM, ELL}           Ceramic artificial teeth
{KIF, EKM}           Endodontic filling/sealing material
EJK                  Root canal obturating point
DZN                  Dental material application tool, single-use
EBF                  Dentifrice
EBG                  Dental coating, tooth-desensitizing
EJK                  Hygroscopic dental cement
NPK                  Pliable-polymer dental regeneration membrane, non-bioabsorbable
EBC                  Glass ionomer dental cement
EHJ                  Dental abrasive point, reusable
NHA                  Dental crown/bridge, temporary
NHA                  Dental crown/bridge resin, temporary
ELM                  Dental impression tray material
ELM                  Dental prosthesis veneer resin
OAT                  Screw endosteal dental implant, two-piece
DZE                  Dental implant abutment analog, laboratory
DZE                  Dental implant suprastructure, temporary, preformed, reusable
DZE                  Dental prosthesis/implant abutment screw
DZE                  Dental prosthesis/implant abutment screw analog, reusable
NDP                  Dental implant x-ray template
NHA                  Dental implant suprastructure, permanent, custom-made
NHA                  Wheelchair, attendant/occupant-driven, rear-wheels-operated, collapsible
EHD                  Mobile extraoral dental x-ray system, analogue
EIF                  Dental wedge, single-use
NTK                  Fibreoptic dental light
NXV                  Toluidine blue O solution IVD
EFC                  Anaesthesia warmer
NXC                  Orthodontic appliance system, adjustable
ELC                  Rotary dental scaler
LRK                  Tongue-training sleep-disordered breathing orthosis
{EBI, ELS}           Dental reinforcing fibre
{ELS, EBI}           Dental reinforcing fibre
{EKO, EBH}           Dental acrylic resin
{EBH, EKO}           Dental acrylic resin
PME                  Dental cavity varnish
DZN                  Manual dental instrument handle
EBO                  Dental repair kit, ceramic
EJK                  Dental cavity varnish
EBD                  Dental crown/bridge resin, temporary
EBF                  Calcium hydroxide dental cement
DYH                  Dental composite resin
EHD                  Diagnostic x-ray system generator, mobile
MUH                  {General-purpose dental x-ray system application software, Dental digital imaging sensor, intra...
MUH                  {Dental digital imaging sensor, intraoral, General-purpose dental x-ray system application soft...
DZC                  Orthodontic appliance system, adjustable
EBH                  Orthodontic bracket adhesive
EIH                  Orthodontic bracket adhesive
EBI                  Orthodontic bracket adhesive
KLE                  Orthodontic bracket adhesive
NDP                  Basket endosteal dental implant, two-piece
EKO                  Dental prosthesis restorative material, unfilled resin
DZL                  Dental implant suprastructure, permanent, preformed
EBI                  Dental restorative material varnish
EBG                  Composite dental impression material
EBI                  Dental implant suprastructure, permanent, preformed
EMK                  Dental sinus lift elevator
EIS                  Dental prosthesis remover
EIY                  Dental spatula, reusable
EML                  Orthopaedic osteotome
EBA                  Endoscopic light source, line-powered
LYC                  Polyethylene craniofacial tissue reconstructive material
NJM                  Orthodontic bracket, metal
DYH                  Fatty acid dental cement
EMS                  Manual dental scaler, reusable
EIK                  Dental plastic restoration carver
EFL                  Paranasal sinus curette
EIK                  Periodontal probe, reusable
EGN                  Dental collar/crown scissors
EKD                  Dental rongeur
JEX                  Dental matrix band retainer
EJY                  Dental articulation paper forceps
EIY                  Paranasal sinus curette
EKR                  Dental amalgam carrier
EIK                  Periodontal knife
EIS                  Tooth extraction forceps
ECS                  Orthodontic ligature director
EJI                  Dental irrigation/aspiration syringe
DZN                  Dental matrix band retainer
EAX                  Tactile orientation material
EKQ                  Manual endodontic spreader
EMD                  Tooth extraction forceps
EKJ                  Dental burnisher
EMI                  Margin finishing dental file/rasp, reusable
EML                  Margin finishing dental file/rasp, reusable
EKE                  Dental curette, basic
EML                  Bone raspatory
EIK                  Dental amalgam carver, reusable
EKR                  Endodontic filling material condenser
ELZ                  Dental crown/bridge resin, temporary
PLV                  Dental treatment application software
EIH                  {Dental appliance fabrication material, ceramic, Dental porcelain/ceramic restoration kit}
EIH                  {Dental porcelain/ceramic restoration kit, Dental appliance fabrication material, ceramic}
{EIH, ELL}           Dental appliance fabrication material, ceramic
{ELL, EIH}           Dental appliance fabrication material, ceramic
EJT                  Dental restorative gold
{EMA, EJK}           Calcium hydroxide suspension
{EBF, EBC}           Dental pit/fissure sealant
{EBD, EBC}           Dental pit/fissure sealant
EJT                  In-exsufflator
EIG                  Dental matrix band, reusable
EIG                  Dental matrix band, single-use
EFN                  Woven surgical sponge
DZE                  Dental implantation drilling template retention pin
DZE                  Surgical drill guide, reusable
DZE                  Orthopaedic implant driver
DZE                  Orthopaedic implant/instrument adaptor, reusable
DZE                  Dental drilling system attachment
DZE                  Steel dental bur
ELC                  Ultrasonic surgical system adaptor, reusable
NHA                  Dental prosthesis thermal detacher
NHA                  Dental prosthesis thermal detacher tip
DYT                  Orthodontic teeth positioner, preformed
DYW                  Orthodontic teeth positioner, preformed
PLH                  Red-light phototherapy unit, line-powered
DZN                  Dental material mixing nozzle, non-sterile
EMA                  Dental/maxillofacial surgical procedure kit, non-medicated, single-use
EGM                  Needleless medication/vaccine injector, mechanical
DZL                  Screw endosteal dental implant, two-piece
LYC                  Dental material injection cannula, reusable
EIL                  Dental implant/prosthesis surgical procedure kit
EJL                  Titanium dental bur
DZN                  Dental curette, basic
NDP                  Dental irrigation/aspiration syringe
DZN                  Periotome, reusable
NDP                  Dental surgical scissors
DZN                  Dental implantation depth/angle gauge, reusable
EJQ                  Dental polishing brush
NDP                  Dappen dish, reusable
NDP                  Absorbent tipped applicator, non-sterile
NDP                  Stationary x-ray grid
EMM                  Dental osteotome set
NDP                  Root canal post thread cutter
EKX                  Dental power tool system, line-powered
DZE                  Basket endosteal dental implant, one-piece
{EBI, EBG, EBF}      Dental implant suprastructure, permanent, preformed
LYC                  Pliable-polymer dental regeneration membrane, bioabsorbable, tacked
EBR                  Dental suction system
EAZ                  Dental suction system
NHA                  Dental implant suprastructure, temporary, custom-made
EMM                  Orthopaedic chisel
EBG                  Two-component dental material applicator, manual
EBF                  Two-component dental material applicator, manual
ELR                  Steel dental bur
EFH                  Dental articulation paste/solution
EKZ                  Electrosurgical handpiece/electrode holder, reusable
EBF                  Self-cured dental restorative composite resin kit, standard
EMA                  Light-cured dental restorative composite resin kit, standard
LRK                  Sleep apnoea tongue implant, non-bioabsorbable
EIC                  Dental anaesthesia syringe, intraligamentary
EIF                  Instrument/equipment drape, single-use, non-sterile
EAX                  Dental cotton roll
EHZ                  Dental mirror, reusable
EHZ                  Dental suction system cannula, reusable
NRD                  Instrument/equipment drape, single-use, non-sterile
EIF                  Dental amalgam trap
DZM                  Needle recapping device, single-use
OFX                  Instrument tray
EKD                  Endodontic plugger
QJC                  Dental caries detecting stain
JEY                  Bone-screw internal spinal fixation system, non-sterile
JEY                  Vertebral body prosthesis, sterile
NJM                  {Orthodontic bracket adhesive, Orthodontic bracket, ceramic}
{DYH, NJM}           {Orthodontic bracket, ceramic, Orthodontic bracket adhesive}
{NJM, DYH}           {Orthodontic bracket, ceramic, Orthodontic bracket adhesive}
{NJM, DYH}           {Orthodontic bracket adhesive, Orthodontic bracket, ceramic}
{DYH, NJM}           {Orthodontic bracket adhesive, Orthodontic bracket, ceramic}
{NJM, DYH}           {Orthodontic bracket, metal, Orthodontic bracket adhesive, Orthodontic tube, Orthodontic bracke...
{NJM, DYH}           {Orthodontic bracket, ceramic, Orthodontic bracket, metal, Orthodontic tube, Orthodontic bracke...
{DYH, NJM}           {Orthodontic bracket adhesive, Orthodontic bracket, metal, Orthodontic tube, Orthodontic bracke...
DYH                  {Orthodontic bracket adhesive, Orthodontic bracket, metal, Orthodontic tube}
DYH                  {Orthodontic bracket, metal, Orthodontic bracket adhesive, Orthodontic tube}
{DZD, NJM, EJF}      {Orthodontic bracket, metal, Orthodontic tube, Orthodontic bracket, ceramic}
DYH                  Orthodontic tube
DYH                  Orthodontic bracket, ceramic
DYW                  Orthodontic bracket, ceramic
DYH                  Orthodontic bracket, metal
DZE                  Orthodontic appliance relief material
DZC                  Orthodontic clasp, metal, preformed
DYJ                  Orthodontic retainer
DZC                  Orthodontic retainer
ECN                  Orthodontic bracket, metal
EAX                  Dental explorer
KZP                  Orthodontic bracket adhesive
EAZ                  Oral lesion examination light
ELL                  Dental veneer, custom-made
EBI                  Custom-made mouthguard
{EKL, KIF}           Dental root surface conditioner
LFC                  Dental prosthesis dye
EMA                  Injectate temperature probe
{KIF, EKL}           Dental root surface conditioner
EMA                  Root canal post, preformed
EKL                  Dental root surface conditioner
{DZD, EJF}           {Orthodontic bracket, metal, Orthodontic tube}
NJM                  Self-ligating orthodontic bracket
{EJF, NJM}           {Orthodontic bracket, metal, Orthodontic bracket, ceramic}
NJM                  Orthodontic tube
DYH                  Dentine adhesive
EMB                  Dental composite resin
EBD                  Self-cured dental restorative composite resin
{EBG, POW}           Dental bridge, polymer
{POW, EBG}           Dental bridge, polymer
EIH                  Dental articulation paste/solution
ECP                  Dental spatula, reusable
ECP                  Ultraviolet view box
ECP                  LED dental light, battery-powered
{EBF, DZC, DYH, KLE} {Orthodontic wire, Dentine bonding agent/set, Orthodontic bracket adhesive}
EBG                  Orthodontic bracket adhesive
DYH                  Denture base resin kit, heat-cured
ECP                  Dental material application tool, single-use
KXR                  Orthodontic aligner auxiliary attachment kit
{KLE, DYH}           {Dental etching solution, Orthodontic bracket adhesive}
{DYH, KLE}           {Orthodontic bracket adhesive, Dental etching solution}
EHL                  Polymeric dental bur
EJR                  Dental polishing cup, reusable
{KLE, EIH, DYH}      Dentine bonding agent/set
{DYH, KLE}           {Orthodontic bracket adhesive, Dentine bonding agent/set}
{KLE, DYH}           {Dentine bonding agent/set, Orthodontic bracket adhesive}
{DYH, KLE}           {Dentine bonding agent/set, Dental etching solution, Orthodontic bracket adhesive}
EBD                  Dental pit/fissure sealant
NXC                  Dental shaded pontic kit
{KLE, DYH}           {Orthodontic bracket adhesive, Dentine bonding agent/set}
DYH                  {Dental composite resin, Orthodontic bracket adhesive}
{DYH, KLE}           {Orthodontic bracket adhesive, Dental etching solution, Dentine bonding agent/set}
EAY                  Dental photo-activated disinfection system handpiece light guide
EAY                  LED dental light, battery-powered
ECP                  Dental photo-activated disinfection system handpiece light guide
{KLE, EBI}           {Orthodontic bracket adhesive, Dentine bonding agent/set}
{EBI, KLE}           {Dentine bonding agent/set, Orthodontic bracket adhesive}
{DYH, KLE}           {Dentine bonding agent/set, Orthodontic bracket adhesive}
{KLE, DYH, DZC, EBF} {Orthodontic bracket adhesive, Dentine bonding agent/set, Orthodontic wire}
ECP                  Dental veneer, custom-made
EJR                  Dental polishing cup, single-use
{KLE, DYH}           {Orthodontic bracket adhesive, Dental etching solution, Dentine bonding agent/set}
{KLE, DYH}           {Dentine bonding agent/set, Dental etching solution, Orthodontic bracket adhesive}
DYH                  {Dentine bonding agent/set, Orthodontic bracket adhesive}
ECO                  Orthodontic aligner auxiliary attachment kit
{ECO, DYH, KLE}      {Orthodontic bracket adhesive, Orthodontic aligner auxiliary attachment kit, Dentine bonding ag...
{ECO, DYH, KLE}      {Dentine bonding agent/set, Orthodontic aligner auxiliary attachment kit, Orthodontic bracket a...
EJL                  Diamond dental bur, reusable
ECP                  Dental material injection cannula, reusable
{KLE, EBF}           {Dental etching solution, Dental prosthesis veneer resin}
{EBF, KLE}           {Dental prosthesis veneer resin, Dental etching solution}
EIF                  Dental cheek retractor, professional, reusable
{ECO, KLE, DYH}      {Orthodontic bracket adhesive, Orthodontic aligner auxiliary attachment kit, Dentine bonding ag...
{DYH, ECO, KLE}      {Dentine bonding agent/set, Orthodontic aligner auxiliary attachment kit, Orthodontic bracket a...
{KLE, KOJ, DYH}      {Dentine bonding agent/set, Dental abrasive air jet system}
{KLE, DYH, KOJ}      {Dentine bonding agent/set, Dental abrasive air jet system}
KXR                  Dental mould
{KLE, EBI, KXR}      {Orthodontic aligner auxiliary attachment kit, Dental mould, Dentine bonding agent/set}
ECP                  Dental material injection cannula, single-use
ECP                  Dappen dish, single-use
ECP                  Dental material mixing surface, single-use
NFS                  Jaw physiology evaluation system
NFQ                  Jaw physiology evaluation system
EBG                  Polymer-based dental model material
EIH                  Dental soldering alloy
EBE                  Polymer-based dental model material
DZN                  Dental osteotome set
DZN                  Dental osteotome
DZN                  Steel dental bur
{DZN, EIL}           Gingiva-coring punch, reusable
{KLE, EBC}           Dental composite resin
EMB                  Zinc phosphate dental cement
DYN                  Dental cheek retractor, professional, reusable
EGD                  Bite registration rim wax, plate
DYJ                  Mouthguard, reusable
DZN                  Mouthguard, reusable
EFH                  Dental crown/bridge, temporary
ELJ                  Resin artificial teeth
DZA                  Carbide dental bur, reusable
DZA                  Diamond dental bur, reusable
{NDP, NHA}           Dental implant/prosthesis surgical procedure kit
NDP                  Biopsy punch, reusable
DZN                  Dental torque wrench
DZN                  Surgical screwdriver, reusable
NDP                  Fluted surgical drill bit, single-use, non-sterile
NDP                  Surgical instrument seal/seal maintenance set
NDP                  Dental anchor
DZI                  Bone cutter
NDP                  Skin marking pen, reusable
DZN                  Orthopaedic implant driver
DZE                  Surgical instrument/implant rack
NDP                  Surgical instrument/implant rack
NDP                  Facebow
OFY                  Dental/maxillofacial surgical procedure kit, non-medicated, reusable
EJL                  Dental implant suprastructure, temporary, preformed, single-use
DZL                  Dental implant suprastructure, temporary, preformed, single-use
OFY                  Dental osteotome
NPK                  Pliable-polymer dental regeneration membrane, bioabsorbable, ligated
LYC                  Polyolefin suture, monofilament
EIA                  Diagnostic-imaging photographic film, self-developing
EAP                  Dental x-ray film holder
{MUH, MQB, EHD}      Dental digital imaging sensor, intraoral
{MQB, EHD, MUH}      Dental digital imaging sensor, intraoral
{MUH, EHD, MQB}      Dental digital imaging sensor, intraoral
{EHD, MQB, MUH}      Dental digital imaging sensor, intraoral
{MUH, MQB, EHD}      Medical device USB cable
{MUH, MQB, EHD}      Dental x-ray film holder
{MQB, MUH, EHD}      Dental x-ray film holder
{EHD, MQB, MUH}      Dental x-ray film holder
{MUH, EHD, MQB}      Dental x-ray film holder
{MQB, EHD, MUH}      Dental x-ray film holder
EAP                  Diagnostic x-ray digital imaging system workstation application software
{MQB, MUH, EHD}      Dental digital imaging sensor, intraoral
EAP                  Medical device USB cable
NDP                  Cannulated surgical drill guiding pin
EID                  Dental restorative material dispenser
EID                  Dental etching solution syringe
KXR                  Dental material mixing surface, reusable
KXR                  Dental material mixing surface, single-use
{KXR, KLE}           Dentine bonding agent/set
{KLE, KXR}           Dentine bonding agent/set
{KRX, EMA, EID, KLE} Dentine bonding agent/set
{KXR, EMA, EID, KLE} Dentine bonding agent/set
{EID, EBF}           Dental composite resin
{EBF, EID}           Dental composite resin
DZN                  Dental abrasive disk, reusable
DZN                  Dental plastic restoration carver
ELW                  Polymer-based dental model material
{EID, KXR, KLE, E... Dental composite resin kit
{KLE, EBD, EID, K... Dental composite resin kit
{KXR, EID, EBF, E... Dental composite resin kit
{EBD, EBF, EMA, E... Dental composite resin kit
EBG                  Dental coating, bond-reduction
{EID, EJK}           Dental composite resin
{EJK, EID}           Dental composite resin
{EID, EIH}           Dental etching solution
{EBD, KXR}           Dental unfilled resin sealant/coating
{EID, EBD}           Dental composite resin
{EBF, KXR}           Dental composite resin
{EBF, KXR, KLE}      Dental unfilled resin sealant/coating
{DZA, ELR}           Root canal post kit
{EMA, DZA, KXR, E... Root canal post kit
{EMA, EID, EBF, D... Root canal post kit
{KLE, DYH, EMA, E... Dentine bonding agent/set
{KXR, DYH}           Dentine bonding agent/set
{DYH, KXR}           Dentine bonding agent/set
{KLE, EID}           Dental etching solution
{EID, KLE}           Dental etching solution
{EIH, EID}           Dental etching solution
{EMA, EID}           Dental composite resin
{EID, EMA}           Dental composite resin
{EID, EBF}           Dental cement trial
{EIH, EID, EBC, E... Dental composite resin
{EBF, EID}           Dental cement trial
{EBF, KLE, KXR, E... Dental composite resin kit
{EBF, KXR, KLE, E... Dental composite resin kit
{EID, PME}           Dental restoration fixation cleaning solution
PME                  Dental restoration fixation cleaning solution
{KXR, EID, KLE}      Dentine bonding agent/set
{KLE, EID, KXR}      Dentine bonding agent/set
{KLE, EID}           Dentine bonding agent/set
EBC                  Dental prosthesis priming agent
{EMA, KXR}           Dental composite resin
{EBC, EID, KXR}      Dental composite resin kit
EBC                  Dentine bonding agent/set
{EID, EBC, KXR, K... Dental composite resin kit
{EBC, KLE, EID, K... Dental composite resin kit
{KLE, EBC, EID, E... Dental composite resin kit
{KLE, EMA, EID, K... Dental composite resin kit
{KXR, EMA}           Dental composite resin
{EID, KLE}           Dental composite resin
{KLE, EID}           Dental composite resin
{KXR, EBF}           Dental composite resin
ELM                  Dental implant x-ray template
{NXC, EBG, KMY, MQC} Orthodontic appliance relief material
{KMY, NXC, MQC, EBG} Orthodontic appliance relief material
NXC                  Dental composite adhesive kit
NXC                  Orthodontic retainer
{KMY, MQC, NXC, EBG} Dental implant x-ray template
{MQC, NXC, EBG, KMY} Dental implant x-ray template
{EBG, MQC, NXC, KMY} Dental implant x-ray template
{MQC, NXC, KMY, EBG} Dental implant x-ray template
{MQC, KMY, NXC, EBG} Dental implant x-ray template
{NXC, MQC, KMY, EBG} Dental implant x-ray template
{KMY, NXC, MQC, EBG} Dental implant x-ray template
{EBG, KMY, MQC, NXC} Dental implant x-ray template
{KMY, NXC, EBG, MQC} Dental implant x-ray template
{MQC, KMY, EBG, NXC} Dental implant x-ray template
{NXC, EBG, MQC, KMY} Dental implant x-ray template
ELM                  Dental shaded pontic kit
{MQC, KMY, EBG, NXC} Orthodontic retainer
{MQC, KMY, NXC, EBG} Orthodontic retainer
NXC                  Dental implant x-ray template
NXC                  Orthodontic pliers
{KMY, MQC, EBG, NXC} Dental implant x-ray template
{MQC, EBG, NXC, KMY} Dental implant x-ray template
{EBG, NXC, KMY, MQC} Dental implant x-ray template
{EBG, KMY, NXC, MQC} Dental implant x-ray template
{KMY, EBG, MQC, NXC} Dental implant x-ray template
{NXC, EBG, KMY, MQC} Dental implant x-ray template
{EBG, MQC, KMY, NXC} Dental implant x-ray template
{MQC, EBG, KMY, NXC} Dental implant x-ray template
{NXC, KMY, EBG, MQC} Dental implant x-ray template
{EBG, NXC, MQC, KMY} Dental implant x-ray template
{NXC, KMY, MQC, EBG} Dental implant x-ray template
{NXC, MQC, EBG, KMY} Dental implant x-ray template
{KMY, EBG, NXC, MQC} Dental implant x-ray template
EID                  Dental material injection cannula, reusable
EJB                  Dental material injection cannula, reusable
EFB                  Dental laboratory drilling system handpiece
EGS                  Dental power tool system handpiece, pneumatic
EGS                  Pneumatic surgical power tool system motor
NRD                  Surgical instrument maintenance lubricant
NRD                  Surgical power tool maintenance unit
ELW                  Dental impression material kit, reusable
{NSB, EFW, JOL}      {Dental suction system cannula, single-use, Dental tooth-cleaning solution, Basic manual toothb...
{JOL, NSB, EFW}      {Dental suction system cannula, single-use, Dental tooth-cleaning solution, Basic manual toothb...
EAG                  Facebow
EIA                  Dental irrigation/aspiration syringe
EFB                  Stool cover
EFB                  Headrest cover
EHL                  Dental polishing cup, single-use
EHA                  Dental x-ray film holder
DZE                  Dental prosthesis/implant abutment screw analog, single-use
EBR                  Suction/irrigation tubing, single-use
EJL                  Diamond dental laboratory bur
EMM                  Bone-coring punch, reusable
DZC                  Craniofacial bone wire/bar
NDP                  Dental prosthesis/implant abutment screw analog, single-use
EJB                  Surgical torque wrench adaptor
EGN                  Bandage scissors, reusable
EGN                  Wire cutter
EMH                  Dental dressing forceps, reusable
EKT                  General-purpose curette
EKT                  Bone curette, reusable
EIC                  Bone grafting cannula
EJB                  Scalpel handle, reusable
EJB                  Wire/ligature passer, reusable
DZA                  Dental drill bit extension
EJB                  Orthopaedic implant driver
LYC                  Dental root surface conditioner
NPL                  Enterovirus total antibody neutralization (serotypes 68-71) IVD, calibrator
{NPM, NPL}           Dental/maxillofacial surgical procedure kit, non-medicated, reusable
OAT                  Dental implantation drilling template retention pin
NHA                  Dental restoration retention pin
OAT                  Multi-purpose surgical mesh, metallic
EBA                  Instrument/equipment drape, single-use, non-sterile
{JEY, DZE}           Multi-purpose surgical mesh, metallic
DYX                  Temporary maxillomandibular fixation set
DZM                  Needle holder, reusable
EMR                  Periosteal elevator, reusable
EJB                  Dental wedge, single-use
DZM                  Dental irrigation/aspiration syringe
DZM                  Dental material application tool, single-use
JEX                  Orthodontic metal band pusher
ELA                  Manual dental scaler, reusable
EKF                  Dental matrix band, single-use
EIF                  Gingival retraction cord, non-medicated
MUH                  Digital imaging cassette/storage phosphor screen, dental
EHK                  Dental power tool converter attachment, rotary
EIF                  Suture scissors
EFK                  Dental dressing forceps, reusable
EHP                  Dental crown/bridge resin, temporary
EKY                  Dental delivery system instrument unit, electric
EKN                  Synthetic gutta-percha
EFB                  High-density lipoprotein (HDL) cholesterol IVD, calibrator
EFB                  Dental polishing cup, reusable
EKF                  Dental matrix band kit
EKP                  Root canal post kit
EIY                  Dental restorative material dispenser
JEX                  Wire cutter
ECQ                  Self-ligating orthodontic bracket tool
ECR                  Orthodontic ligature director
EGN                  Surgical soft-tissue manipulation forceps, scissors-like, reusable
EJZ                  Margin finishing dental file/rasp, reusable
EIY                  Endodontic filling material condenser
EJB                  Dental examination kit
EMJ                  Periotome, reusable
EIF                  Sterilizer/disinfector rack
KIF                  Calcium hydroxide suspension
EGD                  Dental cusp, temporary
{DYH, EBF}           Dental composite resin
{DYH, EBF, KLE}      {Dentine bonding agent/set, Orthodontic bracket adhesive, Dental etching solution}
{EBF, KLE, DYH}      {Orthodontic bracket adhesive, Dental etching solution, Dentine bonding agent/set}
{KLE, DYH}           {Orthodontic bracket adhesive, Dental etching solution}
EMB                  Temporary dental filling material
{EBF, DYH}           Dental composite resin
{EBF, KLE}           {Dental etching solution, Dental composite resin, Dentine adhesive}
EBF                  Multi-purpose soft contact lens solution
EGM                  Dental anaesthesia syringe, reusable
EFC                  Gel warmer
EIG                  Surgical retractor/retraction system blade, reusable
EMI                  Orthopaedic bone pin sharpener
EMK                  Manual dental scaler, reusable
EMN                  Tooth extraction forceps
DZN                  Periodontal hoe
EMH                  Periodontal curette
EIG                  Externally-anchored laparoscopic retractor
EMK                  Dental rongeur
KCR                  Orthodontic face bow
DZC                  Orthodontic spring
ECI                  Tooth separator
DYT                  Orthodontic retainer
ECN                  Orthodontic spring
EJF                  Orthodontic appliance system, adjustable
DYT                  Orthodontic appliance system, adjustable
ECI                  Orthodontic space maintainer
ECS                  Orthodontic positioner seater
ECI                  Orthodontic archwire
ECP                  Self-ligating orthodontic bracket tool
EHM                  Dental abrasive strip, reusable
DZN                  Orthodontic archwire
EMN                  Dental explorer
EMN                  Orthodontic metal band pusher
ECI                  Orthodontic separator
JEX                  Self-ligating orthodontic bracket tool
DZN                  Orthodontic elastomeric appliance pusher
ECN                  Orthodontic archwire
EJF                  Orthodontic power arm/lock
EJF                  Orthodontic wire
EHP                  Orthodontic clasp, metal, preformed
{EJF, DYW}           Orthodontic bracket, plastic, single-use
{DYW, EJF}           Orthodontic bracket, plastic, single-use
EME                  Skin-coring punch, reusable
EMA                  Home-use dental cement
EMB                  Home-use dental cement

#>




<#

Count Name
----- ----
    1 Surgical bulldog clamp, reusable
    1 Borna disease virus immunoglobulin G (IgG) antibody IVD, reagent
    1 Dental implant/syringe connector
    1 Dental articulator
    1 Bone cutter
    1 Suction cannula, reusable
    1 Gingiva-coring punch, single-use
    1 Skin marking pen, reusable
    1 Orthopaedic implantable-device cutter
    1 Optical medical device procedural cover
    1 Intracardiac electrode
    1 Automatic-inflation electronic sphygmomanometer, portable, finger
    1 Surgical video camera
    1 Diagnostic x-ray system generator, mobile
    1 Tungsten-weighted oesophageal dilator
    1 Mobile extraoral dental x-ray system, analogue
    1 Dental implant debridement brush
    1 Toluidine blue O solution IVD
    1 Dental/maxillofacial surgical procedure kit, medicated, reusable
    1 Intravenous pole
    1 Rectal scissors
    1 Rubber dam kit
    1 Rechargeable battery-powered surgical power tool system motor
    1 Rigid endoscopic sponge/swab forceps
    1 Sialendoscope
    1 Rigid endoscope telescope
    1 Wrist restraint
    1 Bone approximation clamp
    1 Endodontic enlarger, reusable
    1 Orthopaedic cement, non-medicated
    1 Dental surgical microscope
    1 Surgical respirator
    1 Daptomycin susceptibility testing disc IVD
    1 Dental chair, electric
    1 Surgical irrigation tubing set, reusable
    1 Sawing power tool attachment, sagittal
    1 Cable/lead/sensor/probe cover, non-sterile
    1 Gynaecological biopsy forceps, reusable
    1 Vertebral body prosthesis, sterile
    1 Woven gauze roll, sterile
    1 Nasal file/rasp
    1 Intrauterine curette, manual
    1 Dressing/utility forceps, tweezers-like, single-use
    1 Ultrasonic surgical system adaptor, reusable
    1 Orthopaedic implant/instrument adaptor, reusable
    1 Arterial/central venous catheterization support/maintenance kit
    1 Sleep apnoea palate implant, non-bioabsorbable
    1 Dental prosthesis thermal detacher tip
    1 Stationary x-ray grid
    1 Surgical power tool maintenance adaptor
    1 Electrosurgical handpiece/electrode holder, reusable
    1 Root canal post thread cutter
    1 Dental amalgam trap
    1 Needle recapping device, single-use
    1 Red-light phototherapy unit, line-powered
    1 Orthopaedic knife
    1 Tracheal suction catheter
    1 Plastic surgery file/rasp
    1 ESDP endoscope
    1 Dental restorative gold
    1 Transabdominal amnioscope
    1 Material-handling lift
    1 Endoscopic light source, line-powered
    1 Body aspiration needle, single-use
    1 Tactile orientation material
    1 Medicine bottle
    1 In-exsufflator
    1 Mechanical pipette
    1 Dental material mixing nozzle, sterile
    1 Total haemoglobin (totHb) IVD, control
    1 Quetiapine IVD, reagent
    1 Ultraviolet view box
    1 Rechargeable battery pack
    1 Woven surgical sponge
    1 Chisel/osteotome blade handle
    1 Denture base resin kit, heat-cured
    1 Organic solvent metabolite IVD, kit, liquid chromatography
    1 Root canal filling-removal solution
    1 Mandible-repositioning/palate-lifting sleep-disordered breathing orthosis
    1 Multi-purpose soft contact lens solution
    1 Test tube rack
    1 Vascular scissors
    1 Airway tube forceps, reusable
    1 Surgical power tool system control unit, line-powered
    1 Radiographic image marker, manual
    1 Surgical instrument guard, reusable
    1 HIV1 antibody IVD, kit, immunochromatographic test (ICT), rapid
    1 ENT powder applicator
    1 Dressing/utility forceps, scissors-like, reusable
    1 Manual surgical rotary handpiece
    1 Needle holder, reusable
    1 Endodontic file retrieval loop
    1 Externally-anchored laparoscopic retractor
    1 Dental cavity varnish solvent
    1 Surgical retractor/retraction system blade, reusable
    1 Dental anaesthesia syringe cartridge
    1 Laparoscopic wound closure thread
    1 Physician-practice-management information system application software
    1 Mobile specimen x-ray system, analogue
    1 High-density lipoprotein (HDL) cholesterol IVD, calibrator
    1 Suture scissors
    1 Endodontic broach, serrated, reusable
    1 Orthodontic appliance positioning mould, basic
    1 General-purpose surgical spatula
    1 Cardiac ablation system irrigation tubing set
    1 Stool cover
    1 Nasal speculum, reusable
    1 Dental examination kit
    2 Fibreoptic dental light
    2 Dental implant abutment impression cap
    2 Wheelchair, attendant/occupant-driven, rear-wheels-operated, collapsible
    2 Haemoglobin B2 (HbB2) IVD, kit, electrophoresis
    2 Dappen dish, single-use
    2 Jaw physiology evaluation system
    2 Dental impression material kit, single-use
    2 Denture repair kit, home-use
    2 Saliva pH IVD, kit, colorimetric dipstick, rapid
    2 Diagnostic x-ray system generator, portable
    2 Dental composite adhesive kit
    2 Stationary panoramic/tomographic dental x-ray system, analogue
    2 Dental scaling solution
    2 Oral lavage system
    2 Orthodontic vibrator
    2 Dental mirror, single-use
    2 Dental treatment application software
    2 Bone raspatory
    2 Dappen dish, reusable
    2 Dental matrix band kit
    2 Intraoral camera
    2 Complete upper denture
    2 Bedding set
    2 Dental photo-activated disinfection system handpiece light guide
    2 Dental implant stability measurement control unit
    2 Haematological concentrate system
    2 Polymeric dental bur
    2 General-purpose bowl, reusable
    2 Denture cleaning brush
    2 LED dental light, battery-powered
    2 Composite bone graft
    2 Headrest cover
    2 Line-powered surgical power tool system motor
    2 Diagnostic x-ray digital imaging system workstation application software
    2 Surgical power tool maintenance unit
    2 Orthopaedic bur, single-use
    2 Remotely-driven surgical drilling system motor
    2 Orthodontic space maintainer
    2 Cranioplasty plate, alterable
    2 Surgical tamp, reusable
    2 Sagittal surgical saw blade, reusable
    2 Dental coating, bond-reduction
    2 Medical device light source controller
    2 Orthopaedic fixation plate bending insert, reusable
    2 Medical equipment handle cover, single-use, non-sterile
    2 Fluoride gel
    2 X-ray tube housing assembly, diagnostic
    2 Absorbent tipped applicator, non-sterile
    2 Enteral feeding/medication connector, non-sterile
    2 Arthroscopic probe
    2 Dental restorative material dispenser
    2 Dental prosthesis fabrication material, polymer
    2 Medicine chamber spacer, reusable
    2 Surgical power tool hand-switch
    2 Electromechanical device/system transport trolley
    2 Baby care kit
    2 Surgical soft-tissue manipulation forceps, tweezers-like, single-use
    2 Surgical screwdriver, single-use, non-sterile
    2 Head-worn light, line-powered
    2 Water jet flosser
    2 Audiometer testing system
    2 Wire/ligature passer, reusable
    2 Hydrogel dental regeneration membrane
    2 Finger protector, reusable
    2 Tonsil scissors
    3 Dental computer assisted anaesthesia injection unit
    3 Electrosurgical handpiece, reusable
    3 Gel warmer
    3 Orthodontic elastomeric appliance pusher
    3 Dental suction system cannula, reusable
    3 Orthopaedic graft inserter
    3 Bone graft delivery kit
    3 Injectate temperature probe
    3 Dental restorative unfilled resin kit, standard
    3 Dental amalgam well
    3 Craniofacial bone distractor extension
    3 Woven gauze roll, non-sterile
    3 Dressing/utility forceps, tweezers-like, reusable
    3 Surgical irrigation/aspiration tubing set
    3 Reciprocating surgical saw blade, reusable
    3 Sawing power tool attachment, reciprocating
    3 Ertapenem susceptibility testing disc IVD
    3 Dissection sponge
    3 Sleep apnoea pillow
    3 Electrical-only medical device connection cable, reusable
    3 Craniofacial alignment rod
    3 Denture cushion
    3 Bandage scissors, reusable
    3 Bone fixation plate pliers
    3 Ultrasonic osteosynthesis system handpiece
    3 Stationary panoramic dental x-ray system, analogue
    3 Dental polishing brush
    3 Enterovirus total antibody neutralization (serotypes 68-71) IVD, calibrator
    3 Silicophosphate dental cement
    3 Surgical instrument/endoscope cleaning brush/tool, reusable
    3 Internal orthopaedic fixation system, plate/screw, non-bioabsorbable, sterile
    3 Dental-professional prophylaxis brush, reusable
    3 Digital imaging cassette/storage phosphor screen, dental
    3 Anaesthesia Luer syringe, non-sterile
    3 Dental material mixing surface, reusable
    3 Dental power tool converter attachment, rotary
    3 Pneumatic surgical power tool system motor
    3 Spinal bone screw, bioabsorbable
    3 Dental etching solution syringe
    3 Dental unfilled resin sealant
    4 Orthopaedic joint/limb rongeur
    4 Dental restoration fixation cleaning solution
    4 Dental precision attachment simulator/analog, single-use
    4 Dental laboratory drilling system motor
    4 Cranioplasty sheet
    4 Dental amalgam capsule
    4 Sawing power tool attachment, oscillating
    4 Cranial bur, reusable
    4 Tongue scraper, single-use
    4 Home-use dental cement
    4 Portable basic diagnostic x-ray system, digital
    4 Dental occlusal splint, preformed
    4 Dental impression material kit, reusable
    4 Dental wedge, reusable
    4 Stationary extraoral dental x-ray system, analogue
    4 Bone tack inserter, basic
    4 Denture reliner, soft, home-use
    4 Ultrasonic surgical system torque wrench, reusable
    4 Dental abrasive air jet system control unit
    4 Dental prosthesis thermal detacher
    4 Root canal post, custom-made
    4 Orthodontic chin cap
    4 Orthopaedic surgical procedure kit, non-medicated, reusable
    4 Two-component dental material applicator, electric
    4 Light-cured dental restorative composite resin kit, standard
    4 Surgical power tool system handpiece, sawing, pneumatic
    4 Two-component dental material applicator, pneumatic
    4 Surgical instrument/implant rack
    4 Haemoglobin E (HbE) IVD, calibrator
    4 Cannulated surgical drill guiding pin
    4 Medical device cleaning agent
    4 Medical device USB cable
    4 Bone grafting cannula
    4 Surgical instrument seal/seal maintenance set
    4 Dental impression material mixer
    5 Orthodontic appliance remover
    5 Dental implant suprastructure, permanent, custom-made
    5 Surgical drill guide, single-use, non-sterile
    5 Surgical countersink, single-use
    5 Rubber dam punch
    5 Interproximal/occlusal dental gauge, single-use
    5 Bite registration rim wax, plate
    5 Bone holding forceps
    5 Orthopaedic fixation implant alignment tool
    5 Medical device air compressor
    5 Orthodontic positioner seater
    5 Orthopaedic fixation plate bending insert, single-use
    5 General/plastic surgery bur
    5 Screw extractor, single-use
    5 Gingival retraction kit
    5 Fibreoptic retractor handle
    5 Dental caries removal solution
    5 Irrigation syringe
    5 Electrosurgical return electrode, reusable
    5 Basket endosteal dental implant, one-piece
    5 Mandibular condyle prosthesis
    5 Suction system canister liner
    5 Orthopaedic bone pin sharpener
    5 Surgical flat-nosed pliers
    5 Periodontal hoe
    5 Orthopaedic bone wire
    5 Dental anaesthesia syringe, intraligamentary
    5 Dental anaesthesia injection kit
    5 Dental dry field kit
    6 Bone matrix implant, animal-derived, non-bioabsorbable
    6 Orthodontic appliance dimension gauge
    6 Bone-coring punch, reusable
    6 Orthodontic aligner auxiliary attachment kit
    6 Tongue-retaining sleep-disordered breathing orthosis
    6 Rubber dam clamp forceps
    6 Gingival retraction cord, medicated
    6 Saliva absorbent
    6 Sleep apnoea tongue implant, non-bioabsorbable
    6 Basic electric toothbrush, battery-powered
    6 Self-cured dental restorative composite resin kit, standard
    6 Orthopaedic trocar blade, reusable
    6 Multi-purpose digital medical camera
    6 Needleless medication/vaccine injector, mechanical
    6 Paranasal sinus curette
    6 Manual dental instrument handle
    6 Remotely-driven surgical/dental system drive cable
    6 Surgical depth gauge, reusable
    6 Orthopaedic implant/instrument depth limiter
    6 Endodontic dressing
    6 Oscillating surgical saw blade, reusable
    6 Orthodontic separator
    7 Endodontic reaming aid material
    7 Manual orthopaedic bender, reusable
    7 Anaesthesia warmer
    7 Craniofacial bone tack, non-bioabsorbable
    7 Dental abrasive point, single-use
    7 Dental material application tool, reusable
    7 Orthopaedic implant driver
    7 Dental precision attachment fitting/adjustment tool
    7 Orthopaedic surgical procedure kit, non-medicated, single-use
    7 Orthopaedic bone pin, non-bioabsorbable
    7 Dental implantation drilling template retention pin
    7 Periodontal file/rasp
    7 Self-retaining surgical retractor, reusable
    7 Tongue depressor, surgical
    8 Endodontic broach, serrated, single-use
    8 Temporary maxillomandibular fixation set
    8 Zinc sulfate dental cement
    8 Endodontic filling material carrier
    8 General-purpose suction system, line-powered
    8 Dental amalgam carver, reusable
    8 Polyolefin suture, monofilament
    8 Facebow
    8 Surgical torque wrench, reusable
    8 Dental abrasive strip, reusable
    8 Transmandibular implant
    8 Radiography digital imaging scanner
    9 Dental root surface conditioner
    9 Dental crown, polymer
    9 Periodontal root surface regeneration material
    9 Self-ligating orthodontic bracket tool
    9 Mouthguard, reusable
    9 Ultrasonic osteosynthesis system sonotrode tip
    9 Pliable-polymer dental regeneration membrane, bioabsorbable, tacked
    9 Multi-purpose surgical mesh, synthetic polymer, bioabsorbable
    9 Digital imaging cassette/storage phosphor screen
    9 Titanium dental bur
    9 Rubber dam frame
    9 Custom-made organ/bone anatomy model/surgical guide kit
    9 Dental bridge, metal-polymer
   10 Dental cheek retractor, professional, single-use
   10 Line-powered dental drilling system
   10 Bite registration rim wax
   10 Polyethylene craniofacial tissue reconstructive material
   10 Surgical mallet
   10 Surgical/emergency suction cannula, non-illuminating, single-use
   10 Dental bleaching agent
   10 Orthopaedic implantation sleeve, reusable
   10 Dental material mixing surface, single-use
   10 Dental prosthesis remover
   10 Mobile intraoral dental x-ray system, digital
   10 Wire cutter
   10 Drilling power tool attachment, basic
   10 Bone trephine
   10 Dental matrix band, reusable
   10 Dental impression material syringe, single-use
   11 Dental pick, massaging
   11 Skin/tissue hook
   11 Ultrasonic osteosynthesis system
   11 General-purpose dental x-ray system application software
   11 Skin-coring punch, reusable
   11 Diagnostic-imaging photographic film, self-developing
   11 Tooth separator
   11 Pharmaceutical fluid-dispensing system
   11 Gingival retraction cord, non-medicated
   11 Custom-made orthopaedic surgical guide, non-sterile
   11 Nasal dilator
   11 Orthopaedic prosthesis implantation instrument, reusable
   11 Dental mandrel
   11 Cone beam computed tomography system, head/neck
   11 Stationary cephalometric x-ray system, digital
   12 Multi-purpose surgical mesh, collagen, bioabsorbable
   12 Calcium hydroxide suspension
   12 Dental matrix band tensioner
   12 Tongue-training sleep-disordered breathing orthosis
   12 Flexible video stomatoscope
   12 Dental implant extractor
   12 Sterilizer/disinfector rack
   12 Diagnostic x-ray system generator, hand-held
   12 Nasal chisel
   12 Biopsy punch, reusable
   12 Surgical instrument maintenance lubricant
   12 Pneumatic dental scaling/debridement system
   12 Dental laboratory mandrel
   13 Dental amalgam mixer
   13 Dental impression material syringe, reusable
   13 Line-powered dental drilling/sawing system handpiece
   13 Ethoxy benzoic acid dental cement
   13 General-purpose curette
   13 Fluoride gel tray
   13 Orthodontic power arm/lock
   13 Hygroscopic dental cement
   13 Ultrasonic dental scaling/debridement system generator
   13 Interproximal dental gauge, reusable
   14 Dental restorative material varnish
   14 Intraoral optical scanning system
   14 Dental ultrasonic surgical system handpiece
   14 Dental cotton roll
   14 Dental soft-tissue matrix implant, animal-derived
   14 Rhinoscopic mirror
   14 Subperiosteal dental implant material
   14 General-purpose syringe, single-use
   14 Membrane fixation tack, non-bioabsorbable
   14 Zinc oxide eugenol dental cement
   14 Open-surgery electrosurgical electrode, monopolar, reusable
   14 General-purpose endoscopic needle, single-use
   15 Laryngeal mirror, reusable
   15 Oral lesion examination light
   15 Periocular/lacrimal retractor, hand-held, reusable
   15 Dental articulation paper
   15 Dental guided surgery reference plate
   15 Dental mould
   16 Dental osteotome set
   16 Dental handpiece maintenance unit
   16 Surgical irrigation tubing set, single-use
   16 Dental laboratory drilling system handpiece
   16 Surgical torque wrench adaptor
   16 Scalpel handle, reusable
   16 Basic manual toothbrush
   16 External orthopaedic fixation system, reusable
   17 Root canal obturating point
   17 Dental power tool system handpiece, battery-powered
   17 Denture cleanser
   17 Syringe-loaded injector, manual, professional
   17 General-purpose surgical scissors, reusable
   18 Clinical periodontal dressing
   18 Sliding dental precision attachment
   19 Dental impression spacer
   19 Diamond dental laboratory bur
   19 Dental bone matrix implant, metallic
   19 Dental x-ray system collimator
   19 Orthodontic clasp, metal, preformed
   19 Stationary extraoral dental x-ray system, digital
   19 Calcium hydroxide dental cement
   20 Dental collar/crown scissors
   20 Dental matrix band retainer
   20 Dental acrylic resin
   20 Margin finishing dental file/rasp, reusable
   20 Electrosurgical system generator
   21 Temporary mandibular condyle prosthesis
   21 Craniofacial bone wire/bar
   21 Dental/maxillofacial surgical procedure kit, medicated, single-use
   21 External orthopaedic fixation system, single-use, non-sterile
   21 Dental cavity liner
   21 Pliable-polymer dental regeneration membrane, bioabsorbable, ligated
   21 Dental caries detecting stain
   21 Dental burnisher
   22 Dental shaded pontic kit
   22 Cryogenic spray, dental
   22 Surgical countersink, reusable
   22 General oral wound dressing, animal-derived
   23 Bone file
   23 Temporary dental filling material
   23 Manual endodontic spreader
   23 Dental impression adhesive
   24 Internal orthopaedic fixation system, plate/screw, non-bioabsorbable, non-sterile
   24 Dental bib
   24 Rubber dam, non-latex
   24 Dental laboratory power tool system
   24 Pneumatic dental scaling/debridement system handpiece tip, periodontal
   24 Craniofacial bone screw, bioabsorbable
   24 Rotary dental scaler
   24 Magnetic dental precision attachment
   25 Dental caries detector, optical induced fluorescence
   25 Orthopaedic implant/trial-implant holder, reusable
   25 Two-component dental material applicator, manual
   25 Orthopaedic implant impactor
   26 Dental delivery system
   27 Orthopaedic bone screw, bioabsorbable
   27 Mouth gag, adjustable, reusable
   27 General surgical procedure kit, medicated
   27 Orthodontic appliance relief material
   27 Dental guided surgery reference pin
   28 Orthopaedic osteotome blade, reusable
   28 Dental power tool system, line-powered
   28 Stationary intraoral dental x-ray system, analogue
   28 Dental stereotactic surgery system
   28 Denture reliner, elastic, long-term
   28 Orthopaedic chisel
   29 Orthopaedic fixation plate, non-bioabsorbable, sterile
   29 Dental tooth-cleaning solution
   29 Foot-switch, electrical
   29 Hand-held intraoral dental x-ray system, digital
   29 Surgical implant template, single-use
   30 Dental computed radiography digital imaging scanner
   30 Dental bone matrix implant, human-derived
   30 Bone curette, reusable
   30 Pneumatic dental scaling/debridement system handpiece
   31 Dental pulp-capping material
   31 Craniofacial bone tack, bioabsorbable
   31 Dental delivery system irrigation handpiece
   31 Periotome, reusable
   31 Dental sinus lift elevator
   32 Dental computer assisted anaesthesia injection handpiece
   32 Endodontic reamer
   32 Composite dental impression material
   32 Dental casting wax
   33 Custom-made mouthguard
   33 Warm-bonded endodontic obturation system obturator
   33 Personal care kit
   33 Dental wedge, single-use
   33 Suction/irrigation tubing, single-use
   34 Surgical instrument handle, non-torque-limiting
   34 Dental syringe needle, single-use
   34 Cranial bone prosthesis, custom-made
   34 Dental articulation paper forceps
   34 Dental polishing cup, reusable
   36 Orthodontic ligature director
   36 Bone-screw internal spinal fixation system, non-sterile
   36 Endodontic stopper
   36 Endodontic obturation system
   36 Dental repair kit, ceramic
   36 Dental prosthesis priming agent
   37 Dental pulp analysis system
   37 Bone matrix implant, synthetic
   38 Dental anchor
   38 Total temporomandibular joint prosthesis
   38 Pneumatic dental handpiece coupler
   38 Dental amalgam carrier
   39 Bone hook
   39 Stationary panoramic dental x-ray system, digital
   39 Dental/maxillofacial surgical procedure kit, non-medicated, reusable
   39 Mouth gag, non-adjustable
   40 Dental drill bit extension
   41 Periodontal knife
   42 Self-cured dental restorative composite resin
   42 Warm-bonded endodontic obturation system
   42 Denture repair kit, professional
   42 Breathing mouthpiece, reusable
   42 Bone matrix implant, human-derived
   42 Orthodontic anchor plate
   43 Dental occlusal splint, custom-made
   43 Dental prosthesis/implant abutment screw analog, single-use
   44 Intramucosal dental implant
   45 Teething device, fluid-filled
   46 Natural gutta-percha
   46 Surgical implant template, reusable
   47 Neurosurgical procedure kit, non-medicated, single-use
   47 Patient examination/treatment drape, single-use
   47 ENT elevator
   48 Manual bone mill
   48 Surgical staple remover, reusable
   49 Instrument/equipment drape, single-use, non-sterile
   50 Polysulfide dental impression material
   50 Dental abrasive powder
   50 Dental material injection cannula, reusable
   52 Wax dental impression material
   52 Dental base plate
   52 Dental suction system
   53 Dental cheek retractor, professional, reusable
   53 Orthodontic metal band pusher
   54 Dental laboratory curing unit
   54 Surgical planning/navigation-enhancement system
   55 Medical equipment drape, single-use, non-sterile
   55 Orthopaedic retractor
   57 Bone tap, single-use, sterile
   57 Reflective dental light
   58 Bone lever/elevator
   59 Gingiva-coring punch, reusable
   59 Dental implant prosthetic teeth bar
   60 Dental cement trial
   60 Dental material application tool, single-use
   61 Dental soldering alloy
   61 Remotely-driven dental drilling system motor
   61 Dental irrigation/aspiration syringe
   62 Ultrasonic dental scaling/debridement system handpiece
   63 Bone tap, single-use, non-sterile
   64 LED dental light, line-powered
   65 Dental power tool system, pneumatic
   65 Stationary panoramic/tomographic dental x-ray system, digital
   65 Dental restoration retention pin
   66 Zinc polycarboxylate dental cement
   66 Dental curette, basic
   66 Manual dental burnisher, reusable
   67 Root canal post kit
   67 Surgical drill guide, single-use
   69 Sterilization/disinfection container
   70 Instrument tray
   71 Dental composite resin kit
   76 Dental ultrasonic surgical system
   76 Diagnostic-imaging multiformat camera
   77 Dental material injection cannula, single-use
   77 Dental polishing cup, single-use
   79 Dental rongeur
   79 Surgical soft-tissue manipulation forceps, scissors-like, reusable
   80 Bone file/rasp, manual
   83 Orthodontic retainer
   83 Dental dressing forceps, reusable
   83 Dental cusp, temporary
   85 Surgical drill guide, reusable
   85 Dental impression tray material
   86 Fluted surgical drill bit, single-use, sterile
   86 Rubber dam, Hevea-latex
   86 Dental prosthesis bite verification device
   87 Dental delivery system instrument unit, electric
   88 Plastic surgery osteotome
   88 Oral care kit, single-use
   89 Zinc phosphate dental cement
   90 Syringe tip cap
   91 Dental anaesthesia syringe, reusable
   91 Rubber dam clamp
   92 Bite registration rim
   92 Mandibular fossa prosthesis
   93 Dental drilling system attachment
   94 Resilient dental precision attachment
   94 Dental brazing alloy
   96 Custom-made dental composite resin kit
   99 Dental spatula, reusable
  102 Dental x-ray film holder
  103 CAD/CAM software
  105 Dental reinforcing fibre
  105 Dental suction system cannula, single-use
  105 Dental abrasive air jet system
  107 Dental unfilled resin sealant/coating
  107 Craniofacial fixation plate, bioabsorbable
  108 Orthopaedic fixation plate, bioabsorbable
  109 Fluted surgical drill bit, single-use, non-sterile
  110 Dental floss
  111 Dental amalgam condenser, reusable
  111 Hand-held surgical retractor, reusable
  114 Craniofacial fixation plate kit, non-bioabsorbable
  117 Dental implant suprastructure, temporary, custom-made
  117 Dental abrasive disk, reusable
  117 Endodontic paper point
  120 Dental abrasive strip, single-use
  123 Denture base resin, heat-cured
  123 Dental excavator, reusable
  125 Endodontic filling material condenser
  125 Denture clasp, metal, custom-made
  128 Dental surgical scissors
  128 Endodontic plugger
  129 Dental prosthesis/implant abutment screw analog, reusable
  131 Surgical gouge
  134 Periodontal probe, reusable
  137 Dental veneer, custom-made
  137 Dental bone matrix implant, synthetic
  140 Dental impression tray, single-use
  140 Dental implantation depth/angle gauge, reusable
  141 Dental abrasive air jet system handpiece
  142 Dentine adhesive
  143 Dental matrix band, single-use
  150 Dental wax carver
  155 Orthodontic spring
  157 Electrosurgical system
  158 Pliable-polymer dental regeneration membrane, non-bioabsorbable
  158 Fatty acid dental cement
  158 Dental implant x-ray template
  158 Pin/post dental drill bit
  161 Rotary/reciprocating endodontic file/rasp, reusable
  162 Dental material mixing nozzle, non-sterile
  169 Synthetic gutta-percha
  169 Dental bridge, metal-ceramic
  170 Multi-purpose surgical mesh, metallic
  172 Orthodontic lock
  181 Dental explorer
  182 Dental plastic restoration carver
  185 Dental power tool system handpiece, line-powered
  185 Dental CAD/CAM system, chairside
  187 Denture base resin kit
  191 Dental crown, ceramic
  194 Endodontic filling/sealing material
  199 Bar dental precision attachment
  203 Dental crown, metal/ceramic
  203 Dental amalgam alloy
  206 Denture reliner, soft, professional
  208 Steel dental bur
  209 Dental cavity varnish
  211 Rotary/reciprocating endodontic file/rasp, single-use, non-sterile
  215 Dental impression tray, reusable
  216 Bone tap, reusable
  224 Dental articulation paste/solution
  225 Orthodontic face bow
  226 Dental power tool system handpiece, remotely-driven
  226 Dental implant abutment analog, laboratory
  230 Periodontal curette
  233 Resin dental inlay
  236 Hand-held dental retractor
  241 Diamond dental bur, single-use
  241 Dental CAD/CAM system, laboratory
  241 Orthodontic appliance system, progressive
  242 Synthetic bone graft
  244 Dental osteotome
  244 Dental torque wrench
  244 Denture reliner, hard
  245 Polyether dental impression material
  251 Collagen dental regeneration membrane
  251 Denture reliner, elastic, short-term
  260 Mandible-repositioning sleep-disordered breathing orthosis
  265 Dentifrice
  281 Orthodontic inter-arch elastic band
  283 Dental implant suprastructure, temporary, preformed, reusable
  283 Dental/maxillofacial surgical procedure kit, non-medicated, single-use
  283 Dental prosthesis dye
  287 Orthodontic teeth positioner, preformed
  288 Dental mirror, reusable
  301 Orthopaedic osteotome
  305 Carbide dental bur, single-use
  307 Cranioplasty plate screw
  308 Surgical soft-tissue manipulation forceps, tweezers-like, reusable
  310 Preformed dental crown, permanent
  324 Manual dental scaler, reusable
  351 Dental pit/fissure sealant
  364 Dental implant abutment analog, scanning
  367 Stationary intraoral dental x-ray system, digital
  369 Alginate dental impression material
  378 Dental root elevator
  379 Dental amalgam
  379 Dental abrasive point, reusable
  380 Transgingival implant
  383 Dental ultrasonic surgical system handpiece tip
  388 Dental/surgical polymerization lamp
  403 Root canal post, preformed
  405 Fixture/appliance dental drill bit, single-use
  421 Dental implant suprastructure kit
  423 Periosteal elevator, reusable
  424 Dental power tool system handpiece, pneumatic
  433 Fluted surgical drill bit, reusable
  445 Dental etching solution
  451 Orthodontic inter-bracket elastic chain
  452 General/plastic surgical procedure kit, non-medicated, single-use
  458 Orthodontic bracket adhesive
  471 Dental digital imaging sensor, intraoral
  476 Dental bone matrix implant, animal-derived
  491 Ultrasonic dental scaling/debridement system handpiece tip, endodontic
  506 Dental prosthesis restorative material, unfilled resin
  516 Dental coating, tooth-desensitizing
  548 Dental prosthesis veneer resin
  553 Polymer-based dental model material
  558 Self-ligating orthodontic bracket
  586 Preformed dental crown, temporary
  596 Dentine bonding agent/set
  603 Orthodontic extraoral headgear
  619 Orthodontic pliers
  621 Dental implant analog
  641 Manual endodontic file/rasp, single-use
  670 Tooth extraction forceps
  701 Manual endodontic file/rasp, reusable
  737 Orthodontic appliance system, adjustable
  744 Partial denture
  751 Dental prosthesis/implant abutment screw
  755 Glass ionomer dental cement
  759 Orthodontic archwire/bracket ligature
  867 Surgical screwdriver, reusable
  891 Ultrasonic dental scaling/debridement system handpiece tip, periodontal
  896 Dental casting noble alloy
  936 Dental appliance fabrication material, thermoplastic
  963 Ultrasonic dental scaling/debridement system
 1033 General internal orthopaedic fixation system implantation kit
 1045 Dental porcelain/ceramic restoration kit
 1048 Dental bridge, ceramic
 1053 Orthopaedic bone screw, non-bioabsorbable, non-sterile
 1067 Diamond dental bur, reusable
 1074 Dental casting non-noble alloy
 1094 Implantable craniofacial bone distractor
 1133 Orthodontic bracket, plastic, single-use
 1232 Orthodontic anchoring screw
 1240 Dental crown/bridge resin, temporary
 1445 Craniofacial bone screw, non-bioabsorbable, non-sterile
 1550 Light-cured dental restorative composite resin
 1574 Pneumatic dental scaling/debridement system Dental drilling system attachment Dental power tool system, pneuma...
 1663 Basket endosteal dental implant, two-piece
 1714 Craniofacial bone screw, non-bioabsorbable, sterile
 1846 Dental bridge, polymer
 1871 Dental implant/prosthesis surgical procedure kit
 2082 Screw endosteal dental implant, one-piece
 2182 Fixture/appliance dental drill bit, reusable
 2228 Carbide dental bur, reusable
 2340 Silicone dental impression material
 2786 Dental appliance fabrication material, cured
 2856 Ceramic artificial teeth
 3322 Orthodontic archwire
 4343 Preformed complete denture
 4552 Dental crown/bridge, temporary
 4749 Orthodontic wire
 5498 Dental implant suprastructure, temporary, preformed, single-use
 6032 Craniofacial fixation plate, non-bioabsorbable
 6417 Dental composite resin
 6472 Orthodontic tube
 7988 Orthodontic bracket, ceramic
 9384 Dental implant system
12961 Orthodontic metal band
15748 Screw endosteal dental implant, two-piece
23358 Orthodontic bracket, metal
30788 Dental implant suprastructure, permanent, preformed
40383 Dental appliance fabrication material, ceramic
63946 Resin artificial teeth

#>

<#

Hersteller: 688, mit insgesamt 336427 Produkten

Name
----
ZIRKONZAHN SRL
Hager & Meisinger Gesellschaft mit beschränkter Haftung
Musculoskeletal Transplant Foundation, Inc.
bredent GmbH & Co. KG
TOP QUALITY MANUFACTURING, INC.
INTRA-LOCK INTERNATIONAL, INC.
LANG DENTAL MANUFACTURING CO., INC.
OPA DENTAL LLC
PARK DENTAL RESEARCH CORP
CMP INDUSTRIES LLC
STRADIS MEDICAL, LLC
Nexus Cmf, LLC
GSOURCE LLC
DENTAL TECHNOLOGIES, INC.
PEARSON DENTAL SUPPLIES, INC.
SAFCO DENTAL SUPPLY CO.
TALLADIUM, INC.
TULSA DENTAL PRODUCTS LLC
Dentsply Implants Manufacturing GmbH
Merz Dental GmbH
IVOCLAR VIVADENT, INC.
ARDENT, INC.
DENTALEZ, INC.
PULPDENT CORPORATION
PREMIER DENTAL PRODUCTS COMPANY
DENTSPLY INTERNATIONAL INC.
Sultan Healthcare Inc
WATER PIK, INC.
KEYSTONE DENTAL, INC.
CROSSTEX INTERNATIONAL, INC.
AIR TECHNIQUES, INC.
COLTENE/WHALEDENT INC
PATTERSON DENTAL SUPPLY, INC.
DENTRONIX INC
Gc America Inc.
Tenco
HAGER WORLDWIDE, INC.
NATIONAL DISTRIBUTION & CONTRACTING, INC.
ALTATEC GmbH
RIBBOND, INC
WHIP-MIX CORPORATION
DMG AMERICA, LLC
Preventech
ORTHOPLI CORP.
Dentsply De Trey GmbH
Dentsply Professional
NU RADIANCE INC
FRICKE INTERNATIONAL, INC.
Zephyr Sleep Technologies Inc
TOMY INTERNATIONAL, INC.
TRADEMARK MEDICAL, L.L.C.
CPAC EQUIPMENT, INC.
PHOENIX DENTAL, INC.
Aligned Medical Solutions
TMJ SOLUTIONS INC
Cendres+Métaux SA
AALBA DENT INC.
The Myerson Company Limited
GROUP PRACTICE SOLUTIONS INC.
YOUNG MYDENT, LLC
Synca Marketing Inc
CARESTREAM HEALTH, INC.
Coopersurgical, Inc.
CARESTREAM DENTAL LLC
3M COMPANY
BIOCOMPOSITES LTD
MAM USA CORPORATION
curasan AG
Cardinal Health, Inc.
PREAT CORPORATION
SKLAR CORPORATION
Stryker Leibinger GmbH & Co. KG
Stryker Trauma SA
NANOVA BIO MATERIALS INC
Avanos Medical, Inc.
TELEFLEX INCORPORATED
DARBY DENTAL SUPPLY, LLC
SYNTHES (U.S.A.) LP
Conmed Corporation
Vista Dental
NEOCIS INC
AMERICAN SURGICAL COMPANY, LLC
AMD Medicom Inc
DCI MANAGEMENT LLC
TRICOR SYSTEMS, INC.
MEDTRONIC SOFAMOR DANEK, INC.
MCKESSON MEDICAL-SURGICAL INC.
HENRY SCHEIN, INC.
YOUNG DENTAL MANUFACTURING I, LLC
DIO Corporation
J. MORITA U.S.A., INC
LASCOD SPA
Zendo Direct AG
Nobel Biocare AB
Directa AB
Nanning Baolai medical instrument Co.,Ltd
NAKANISHI INC.
SUN MEDICAL CO.,LTD.
MEDICAL PRODUCTS LABORATORIES, INC.
Kinamed, Inc.
ORMCO CORPORATION
HU-FRIEDY MFG. CO., LLC
MEDLINE INDUSTRIES, INC.
Ototronix, LLC
Innovasis, Inc.
Cardinal Health 200, LLC
KLS-Martin L.P.
CAREFUSION 2200, INC
PILLAR PALATAL, LLC
SONENDO, INC.
ELEVATE ORAL CARE, LLC
DPM USA CORP
The Atlanta Dental Supply Company
MIDWAY DENTAL SUPPLY, LLC
Kerr Corporation
IMPLANT DIRECT SYBRON MANUFACTURING LLC
PARKELL, INC.
AirAvant Medical
COOK BIOTECH INCORPORATED
T.A.G MEDICAL PRODUCTS AGRICULTURAL COOPERATIVE ASSOCIATION
ORTHOQUEST, INC.
ASEPTICO, INC.
PAC-DENT INTERNATIONAL INC
BURKHART DENTAL SUPPLY CO., THE
COLLAGEN MATRIX, INC.
BICON, LLC
VISIONARE, LLC
MEDICAL ACTION INDUSTRIES INC.
PRACTICON, INC.
DEPUY SPINE, LLC
Oculo-Plastik Inc
CETYLITE INDUSTRIES INC
MPowRx Health and Wellness Products 2012
INTEGRA YORK PA, INC.
Integra Lifesciences Corporation
SEPTODONT, INC
G & H WIRE COMPANY, INC.
RHONDIUM LIMITED
OVENTUS MANUFACTURING PTY LTD
edelweiss dentistry products gmbh
SKANRAY TECHNOLOGIES PRIVATE LIMITED
HEANY INDUSTRIES, INC.
AURIDENT INC
KJMEDITECH.CO.,LTD
GENOSS CO., Ltd.
Dentium Co., Ltd.
DMAX Co.,Ltd.
VERICOM CO., LTD.
CHIYEWON.LTD
Neobiotech. co., ltd
EBI Inc.
Cowellmedi Co.,Ltd
3D Imaging & Simulations Corp.
Dmetec.Co., Ltd.
Shinhung MST Co., Ltd.
ORTHOLUTION CO.,LTD.
Jeil Medical Corporation
Spident Co., Ltd.
Saeshin Precision Co., Ltd.
Genoray Co., Ltd.
SOPRO
Bioplate, Inc
Inion Oy
W & H Dentalwerk Bürmoos GmbH
Vita - Zahnfabrik H. Rauter Gesellschaft mit beschränkter Haftung & Co Kommanditgesellschaft
Hans Biomed Corp.
Nibec Co., Ltd.
MEDIMECCA Co.,Ltd.
Megagen Implant Co. Ltd
Meta Biomed Co., Ltd.
DiaDent Group International
DENTIS CO., LTD.
DENTOS Inc.
Re-medi Co.,LTD
CRUXELL Corp
DENTALMAX CO.,LTD
sewon medix Inc.
Surgident Co.,Ltd.
Poskom Co., Ltd.
InnoBioSurg Co.,Ltd(IBS implant Co.,Ltd)
PURGO BIOLOGICS Inc.
Biotem Co., ltd
BioMTA
Medit Corp.
NEOSIL Co., Ltd
GOOD DOCTORS CO., LTD.
Achimhai Medical Corporation
Sherpakorea
HT Co., Ltd.
DigiMed Co., Ltd.
B& L Biotech, inc.
Rayence Co., Ltd.
DXM CO., LTD
VATECH CO., LTD.
HDX WILL CORP.
Ray Co., Ltd
Osstem Implant Co., Ltd.
Osstem Implant Co., Ltd._Gasan Branch
DEXCOWIN CO., LTD.
NightBalance Holding B.V.
Vertex-Dental B.V.
Discus Dental, LLC
ADM, a.s.
Avalon Biomed Inc.
TALLADIUM ESPAÑA SL
CERAROOT SL.
AVINENT IMPLANT SYSTEM SLU
BIOTECHNOLOGY INSTITUTE SL
UNION DENTAL SA
STERNGOLD DENTAL LLC
VILLA SISTEMI MEDICALI SPA
H.D.C. SRL
MAJOR PRODOTTI DENTARI SPA
BIOLOREN SRL
SILFRADENT SRL
J DENTAL CARE SRL
DENTAL XRAY COMPANY SRL
BIOSAF IN SRL
PIERREL PHARMA SRL
MESA DI SALA GIACOMO & C. SNC
CEFLA SOCIETA' COOPERATIVA
VANNINI DENTAL INDUSTRY SRL
LEONE SPA
Neoortho Produtos Ortopédicos S/A.
JJGC Indústria e Comércio de Materiais Dentários S/A.
Dentscare Ltda
Vipi Indústria, Comércio, Exportação e Importação de Produtos Odontológicos Ltda.
Angelus Industria de Produtos Odontologicos S A
PRODUCTORA Y COMERCIALIZADORA ODONTOLOGICA NEW STETIC S A
Institut Straumann AG
Biodenta Swiss AG
Z SYSTEMS USA INCORPORATED
SUNSTAR AMERICAS, INC.
EDELWEISS DR ag
Dentalpoint AG
Produits dentaires S.A.
Thommen Medical AG
TRI Dental Implants Int. AG
E.M.S. Electro Medical Systems S.A.
STRYKER CORPORATION
Geistlich Pharma AG
Claronav Inc
Panthera Dental Inc
LED Dental Inc
Scican Ltd
CLINICIAN'S CHOICE DENTAL PRODUCTS, INC.
DENTSPLY IH, INC.
Dentsply Implants NV
Dentatus AB
Doxa Dental AB
Gestenco International AB
DENTIN IMPLANTS TECHNOLOGIES LTD
ETGAR - MEDICAL INSTRUMENTS LTD
DENTACK IMPLANTS LTD
A.B. DENTAL DEVICES LTD
HI-TEC IMPLANTS LTD.
PERFLEX LTD
BHI IMPLANTS LTD
ADIN DENTAL IMPLANT SYSTEMS LTD
DITRON DENTAL LTD
MIS Implants Technologies Ltd.
NORIS MEDICAL LTD
PALTOP ADVANCED DENTAL SOLUTIONS LTD
GP - IMPLANT LTD
OPTIMET
SILMET LTD
DELDENT LTD.
DATUM DENTAL LTD
AUGMA BIOMATERIALS LTD
MICRO MEGA
Heraeus Kulzer GmbH
DENTAURUM GmbH & Co.KG
Coltène/Whaledent AG
3M Deutschland GmbH
CERTOL INTERNATIONAL, LLC
Kennametal Stellite (Shanghai) Co., Ltd.
Modern Dental Laboratory (DG) Co., Ltd.
DONGGUAN XIANGTONG CO.,LTD
MODERN DENTAL LABORATORY (SHENZHEN)
NANNING VV DENTAL CO., LTD.
Guangdong JINME Medical Technology Co., Ltd.
SHENZHEN MINGHAO DENTURES CO., LTD.
Liaoning Upcera Co.,Ltd.
Prodent Dental Technology (Shenzhen) Co., Ltd.
Shenzhen Xiangtong Photoelectricity Technology Co., Ltd
SHANDONG HUGE DENTAL MATERIAL CORPORATION
Huge Dental Material Co., Ltd.
Beijing Dongbo Dental Handpiece Co.,Ltd.
NISSIN METEC CHINA CO.,LTD.
BIO CONCEPT CO.,LTD
Xiamen New Sound Technology Co., Ltd.
Guilin Woodpecker Medical Instrument Co., Ltd.
ANHUI GREENLAND BIOTECH CO.,LTD
Carl Zeiss Suzhou Co., Ltd.
Electro Optical Systems Finland Oy
PaloDEx Group Oy
Planmeca Oy
SOUTHERN IMPLANTS (PTY) LTD
3shape Trios A/S
3shape A/S
Rønvig Dental Manufacturing A/S
Elos Medtech Pinol A/S
Tita-Link BVBA
Materialise NV
DMP DENTAL INDUSTRY S.A.
SHEFABONE INC
ADVANCED HEALTHCARE LTD.
Neoss Ltd
DB ORTHODONTICS LIMITED
CERAMISYS LTD
RENISHAW P L C
WRIGHT HEALTH GROUP LIMITED
JUVORA LIMITED
TAKARA-BELMONT CO., LTD.
QUEST DENTAL MATERIAL CORPORATION
DENTMATE TECHNOLOGY CO., LTD.
BOMEI CO., LTD.
BONART CO., LTD.
HUNG CHUN BIO-S CO., LTD.
ROLENCE ENTERPRISE INC.
NORTH EOS INDUSTRIES INC.
MONITEX INDUSTRIAL CO., LTD.
COHO BIOMEDICAL TECHNOLOGY CO., LTD.
YAMAHACHI DENTAL MFG.,CO.
OSADA ELECTRIC CO.,LTD.
OLYMPUS TERUMO BIOMATERIALS CORP.
NEO DENTAL CHEMICAL PRODUCTS CO.,LTD.
J.MORITA MFG.CORP.
TOKUYAMA DENTAL CORPORATION
YOSHIDA DENTAL MFG. CO., LTD., THE
PSM Medical Solutions
smart optics Sensortechnik GmbH
exocad GmbH
botiss biomaterials GmbH
Tomed GmbH
Biovision GmbH Entwicklung, Herstellung und Vertrieb von Biomaterialien
S & S Scheftner GmbH
Pritidenta GmbH
Matricel GmbH
Hermann Medizintechnik GmbH
DFS - DIAMON GmbH
MK-Dent GmbH
Karl Storz GmbH & Co. KG
Aesculap AG
Medicon eG. Chirurgiemechaniker-Genossenschaft
Tutogen Medical GmbH
Henke-Sass, Wolf GmbH
Indenco Dental Products Inc
Keystone Industries
Harry J Bosworth Company
STRAUSS & CO - INDUSTRIAL DIAMONDS LTD
ZHERMACK SPA
Yeti Dentalprodukte GmbH
WOHLWEND AG DENTAL MANUFAKTUR
TRINON TITANIUM GMBH
steco-System-Technik GmbH & Co KG
SRL Dental GmbH
SIC invent AG
Schütz Dental GmbH
Storz am Mark GmbH
Ritter Implants GmbH & Co. KG
R-Dental Dentalerzeugnisse GmbH
OT medical GmbH
NT-Trading GmbH & Co. KG
Nouvag AG
MEDENTiKA GmbH
MICERIUM SPA
DMG Chemisch-Pharmazeutische Fabrik GmbH
KURARAY NORITAKE DENTAL INC.
Kaltenbach & Voigt GmbH
GENDEX CORP.
DEXIS LLC
ARIBEX, INC.
Imaging Sciences International
JUVAPLUS SA
Harvard Dental International GmbH
Gebdi Dental-Products GmbH
Forestadent Bernhard Förster GmbH
RESMED SA
OWANDY RADIOLOGY
ITENA CLINICAL
PRODUITS DENTAIRES PIERRE ROLLAN
BIOM' UP
TEKNIMED
SEPTODONT SAS SPECIALITES SEPTODONT
EUROTEKNIKA
BIOMATLANTE
ETABLISSEMENTS ANTHOGYR
SATELEC
BIOMET 3I, LLC
BEUTLICH PHARMACEUTICALS, LLC
Zest Anchors, LLC
SWEDEN & MARTINA SPA
ALLESEE AOA-PRO
ZIMMER DENTAL INC.
Zimmer, Inc.
Encore Medical, L.P.
Peter Brasseler Holdings, LLC
RMO, INC.
Eisenbacher Dentalwaren ED GmbH
DOCERAM medical ceramics GmbH
DETAX GmbH & Co. KG
Dental Direkt GmbH
DeguDent GmbH
Adentatec GmbH Competence in Dental
KLEMA Dentalprodukte GmbH
bisico Bielefelder Dentalsilicone GmbH & Co. KG
BEGO Bremer Goldschlägerei Wilh. Herbst GmbH & Co.KG
AlgOss Biotechnologies GmbH
Argon Medical Productions & Vertriebs Gesellschaft mbH & Co. KG
Gc Orthodontics America Inc.
Amann Girrbach AG
Wieland Dental + Technik GmbH & Co. KG
MECTRON SPA
FONA SRL
EURONDA SPA
Polydentia SA
SIRONA Dental Systems GmbH
DÜRR DENTAL SE
Cavex Holland B.V.
Innovation MediTech GmbH
Dreve Dentamid GmbH
SHOFU DENTAL CORPORATION
VOCO GmbH
ULTRADENT PRODUCTS, INC.
SURGISTAR, INC.
Greater Goods
CAO GROUP, INC.
ORTHODONTIC SUPPLY & EQUIPMENT COMPANY INC
XZEAL TECHNOLOGIES, INC.
PROVENT SLEEP THERAPY, LLC
JAZZ IMAGING LLC
A.M.A. PLASTICS
CROWN DELTA CORPORATION
AMERICAN DENTAL PRODUCTS INC
ORTHOACCEL TECHNOLOGIES, INC.
GuidePro3D
3D IMAGING AND SIMULATION CORP. AMERICAS
REALCLOUD IMAGING, INC.
OTC DENTAL CORPORATION
2Z Medical
PROSOMNUS SLEEP TECHNOLOGIES
EDLEN IMAGING, LLC
NUSMILE, LTD.
JOHNSON-PROMIDENT
YOUNG PS ACQUISITION, LLC
Siesta Medical
APNEA SCIENCES CORPORATION
KELLER LABORATORIES, INC.
ECOTEC MANUFACTURING, INC.
FORMLABS OHIO INC.
TRUE FUNCTION LABORATORY
VOODOO MANUFACTURING, INC.
STRAIGHT SMILE LLC
ADVANTAGE DENTAL PRODUCTS INC
CONTOUR HEALER, LLC
SOUTH EAST INSTRUMENTS LLC
D4D TECHNOLOGIES, LLC
DENTAL EVOLUTIONS, INC
VYNACRON DENTAL RESINS INC
AMERICAN MEDICAL & HOSPITAL SUPPLY CO., INC.
SLEEPING WELL, LLC
DENTERPRISE INTERNATIONAL, INC.
DENTAMERICA, INC.
DENTCA, INC.
CYTOPHIL, INC.
ORAMETRIX, INC.
TITAN IMPLANT SYSTEMS, LLC
FOUNDATION FOR COMMUNITY BLOOD CENTER/COMMUNITY TISSUE SERVICES, THE
Impladent, Ltd.
ZUGA MEDICAL, INC.
Rti Surgical, Inc.
Macan Manufacturing
Wykle Research, Inc
PROPEL ORTHODONTICS LLC
Bio-Dent, Inc.
PERMA LABORATORIES LLC
APNICURE, INC.
SIGMAGRAFT, INC.
RESPIRE MEDICAL HOLDINGS LLC
SOMNOMED, INC.
SLEEP SCIENCE PARTNERS, INC.
JACE MEDICAL, LLC
ADVANCED BRAIN MONITORING, INC.
AIRWAY TECHNOLOGIES, LLC
SUNI MEDICAL IMAGING, INC.
HOME AIDE DIAGNOSTICS, INC.
EVOLVE DENTAL TECHNOLOGIES, INC.
ASI MEDICAL, INC.
SOLVAY SPECIALTY POLYMERS USA, L.L.C.
HO DENTAL COMPANY LLC
APEX DENTAL MATERIALS INCORPORATED
I3 IMPLANT LLC
ACCESS DENTAL LAB, LLC
CANDID CARE CO.
DENTAL ENGINEERING LABORATORIES, LLC
LYNCH BIOLOGICS, LLC
Precision Dental Instruments
BIOHORIZONS IMPLANT SYSTEMS, INC
Pioneer Surgical Technology, Inc.
OSTEOMED LLC
YOUNG INNOVATIONS HOLDINGS LLC
KARL SCHUMACHER DENTAL INSTRUMENT CO., INC.
ORTHO SPECIALTIES
TITAN IMPLANT INC
SAGEMAX BIOCERAMICS, INC
MIDMARK CORPORATION
A. TITAN INSTRUMENTS, INC.
Ellman International
Cynosure, Inc.
Salvin Dental Specialties, Inc.
BIOMET MICROFIXATION, INC
Kettenbach GmbH & Co. KG
Dr. Jean Bausch GmbH & Co. KG
Candulor AG
Coltène/Whaledent GmbH + Co. KG
IVOCLAR VIVADENT AKTIENGESELLSCHAFT
Osteogenics Biomedical Inc
SDI LIMITED
FUSION DENTAL IMPLANTS LLC
ALPINE DENTAL INC.
Digital Orthodontic Care
BIOFUNCTIONAL MATERIALS LLC
ODONTIT S.A.
ORTHOSOURCE
DIAMODENT INC
SODIUM SYSTEMS LLC
AMERICAN DENTAL IMPLANT CORPORATION
E DENTAL PRODUCTS
SPIRALTECH SUPERIOR DENTAL IMPLANTS, INC.
Radiotecnología Industrial, S.A. de C.V.
ALMORE INTERNATIONAL INC
MASTERLINK LLC
MASTERDENT LTDA
MARIE REIKO INC
ADDENT, INC.
Xemax Surgical Products Inc
Clearcorrect Operating, LLC
Ortosim, S.A. de C.V.
OPEN IMPLANTS, LLC
DISTRIBUDENT, LLC
TPC ADVANCE TECHNOLOGY, INC.
EDGE ENDO LLC
SELANE PRODUCTS, INC.
JBC and Company
JEREMIAH WALDON SALES PROFESSIONAL, INC.
UHLER DENTAL SUPPLY, INC.
Denplus Inc
GLASSPAN INC
GLOBAL DENTAL SCIENCE LLC
CFS DENTAL INC
Dyna Flex of Missouri, L.P.
Dental Wings Inc
Premium Plus International Limited
Taub Products
DENT ZAR, INC.
ImageWorks
PRIMOTEC LLC
FIVE STAR ORTHODONTIC LABORATORY & SUPPLY INC
MTI Precision Products, LLC
QUANTUM BIOENGINEERING LTD.
SURGIKOR, LLC
TIGER SUPPLY, INC.
USA THINK INC.
RHEIN 83 SRL
DENALI CORPORATION
SPECIALTY APPLIANCE WORKS, INC.
ARGEN CORPORATION, THE
ALL DENTAL PRODX
AMERICAN EAGLE INSTRUMENTS, INC.
Zoll-Dental
Gyrus Acmi, Inc.
VIVE HEALTH LLC
EMERY ENTERPRISES INC
Six Month Smiles
GOOD FIT TECHNOLOGIES, LLC
LANCER ORTHODONTICS, INC.
J & J INSTRUMENTS INC
GROMAN INC.
PRIME DENTAL
XNAV TECHNOLOGIES LLC
JENSEN INDUSTRIES INC.
3D DENTAL DESIGNS AND DEVELOPMENT, LLC
CENTRIX, INC.
DANVILLE MATERIALS, LLC
IQ DENTAL SUPPLY LLC
OSSEOLINK USA LLC
OBTURA SPARTAN ENDODONTICS
RODO MEDICAL, INC.
ALIGN TECHNOLOGY, INC.
Biolux Research Limited
EXACTA DENTAL PRODUCTS INC
BOUND TREE MEDICAL, LLC
MADA MEDICAL PRODUCTS, INC
BLUE SKY BIO LLC
HIOSSEN, INC.
NOVABONE PRODUCTS, LLC
ADA PRODUCTS CO, INC
DSM BIOMEDICAL, INC.
Envoy Medical Corporation
HANDPIECE PARTS & REPAIRS, INC.
VULCAN CUSTOM DENTAL, INC
ZYRIS, INC.
BIOPRO, INC.
Little Implant Co.
UROCARE PRODUCTS, INC.
ESSENTIAL DENTAL SYSTEMS, INC.
MEDTRONIC XOMED, INC.
MUNCHKIN, INC.
I PLAY. INC.
BIRD-X, INC.
LUV N' CARE, LTD.
WAL-MART STORES, INC.
3M UNITEK CORPORATION
3m do Brasil Ltda.
PUBLIX SUPER MARKETS, INC.
BIOLASE, INC.
PROTECH PROFESSIONAL PRODUCTS INC
DEN-MAT HOLDINGS, LLC
Rainbow Specialty & Health Products Inc
ASTRON DENTAL CORPORATION
ROYDENT DENTAL PRODUCTS INC
GAC INTERNATIONAL LLC
GAC
THERMOPLASTIC COMFORT SYS
DE GOTZEN SRL
AB Ardent
SCIENTIFIC PHARMACEUTICALS, INC.
HEALTHDENT'L, LLC
RELIANCE ORTHODONTIC PRODUCTS INC
CARGUS INTERNATIONAL, INC
Glustich Inc
GARRECO, LLC
MYOTRONICS NOROMED, INC
CYBER MEDICAL IMAGING, INC.
BUCKEYE MEDICAL TECHNOLOGIES, LLC
OCO BIOMEDICAL INC
Simpler Implant Solutions Inc
COSMEDENT, INC.
SCOTT'S DENTAL SUPPLY L.L.C.
I.Q. IMPLANTS LTD
SiCAT GmbH & Co. KG
GREAT LAKES ORTHODONTICS, LTD.
BENCO DENTAL SUPPLY CO.
Dental Health Products Inc
AMERICAN TOOTH INDUSTRIES
ICP, INC.
UNICARE BIOMEDICAL INC.
Smarthealth, Inc.
SIRONA DENTAL, INC.
Implant Logistics, Inc.
BISCO INC.
DENTIUM USA
James R. Glidewell, Dental Ceramics, Inc.
DIRECT CROWN PRODUCTS
AIDI BIOMEDICAL LLC
RAINTREE ESSIX INC.
ENGLER ENGINEERING CORPORATION
Beyes Dental Canada Inc
Karlin Dental Distributors Inc
Moving Islands Transit Inc
RESMED MOTOR TECHNOLOGIES INC.
SAGE PRODUCTS, LLC
BAYER MEDICAL CARE INC.
METREX RESEARCH, LLC
JOHNSON & JOHNSON CONSUMER INC.
DHARMA RESEARCH, INC.
PASCAL COMPANY, INC.
PHARMACEUTICAL INNOVATIONS INC
SONTEC INSTRUMENTS, INC.
TP ORTHODONTICS INC
AVALIGN TECHNOLOGIES, INC.
AMERICAN ORTHODONTICS CORPORATION
ORTHO TECHNOLOGY, INC.
ORTHO ORGANIZERS, INC.
Regent Baby Products Corp.
Suncoast Dental, Inc
TOM'S OF MAINE, INC.
KIDS II, INC.
MAXILL, INC.
COLGATE ORAL PHARMACEUTICALS, INC.
PROCTER & GAMBLE MANUFACTURING COMPANY, THE
COLGATE-PALMOLIVE COMPANY
Exel International
MAJESTIC DRUG CO. INC.




Count Name
----- ----
  387 NOF
40798 NHA
23953 DZE
   72 NUN
65092 ELM
 9714 EBF
 5216 EBI
 6284 EBG
  584 EIA
 5487 MPI LZD
   70 LZD
  143 EFL
  244 EMH
  105 EIC
 9031 NDP
   90 OFY
   13 NYE
  104 EKX
  122 EBW
   19 EFA
  213 EGS
 1036 DZA
   58 EKF
  164 EGN
 3014 ELW
 3982 DYH
  926 KLE
  186 KIF
  660 LBH
  258 EBC
 1806 EMA
  532 EJJ
 2668 ELC
 2633 ELL
  126 EJK
   24 EMB
42844 EIH
   33 LFC
  409 EBZ
   16 EEG
   80 EAT
  267 EID
  581 LYC
  269 NPL
 4345 EKO
  358 EJS
  676 EJT
 1261 EJH
   18 NXV
  939 EFB
    9 EJE
  291 EMN
  172 EKR
   84 EKK
  156 EKB
  126 EKC
  217 EMS
 1271 DZP
  105 EIE
  299 EJR
    8 EKL
   17 EFT
   35 EFH
  386 MUH
   18 NBL
   15 EGZ
  267 EJQ
 2946 EJL
  775 DZB
  154 EJI
   66 KXR
    1 KXX
  128 EJB
   92 EIF
 7431 NJM
  118 EBL
  200 EKZ
  470 ELR
  534 DZN
 1553 EKS
   91 EEF
  301 EGD
  106 KHR
    9 EJG
  562 JEX
   46 EMD
  171 EHY
   76 DZM
   12 EKQ
  200 EHM
  572 ELZ
  325 EBH
 6390 DZD
 1481 ECI
  236 EBD
   65 NYH
   18 EFD
  120 JES
   19 EFW
   80 KOJ
   10 EFK
   81 EHZ
  245 EKP
  266 EGG
  113 EHP
 8044 DZC
    2 ELE
  243 LRK
   46 KKO
   81 NXZ
  323 OFX
  138 EAP
  494 EHD
   18 EME
   14 LPK
  283 EAX
 9005 JEY
   81 EHO
 2002 DZL
   29 NEI
 1804 MQN
  682 EMM
   16 EIR
   54 EJY
   38 KCQ
  115 EMI
 1031 OAT
  973 DZI
   83 PLV
   27 EFN
   52 NRU
    3 NEA
    1 PWL
  136 KMY
   67 DZJ
   13 EBO
    1 OFW
   95 EML
  565 EIG
  920 EMJ
  789 EMG
  142 EMK
    4 EBA
    3 MDL
   59 DYN
   35 ECB
   55 EHJ
   13 KMT
    9 MZW
  405 NPM
   11 OHP
   34 NSB
    5 ELS
   90 EKH
  162 EIY
  130 EIX
   32 EJZ
  168 EIK
   38 EKI
   55 EKG
   87 EKJ
   25 EIS
  110 EIL
    9 EKW
  286 EKM
   58 JEP
    8 EMQ
   32 ECS
    2 EMP
   13 EMO
   29 EKT
   11 DYX
12357 ECM
21143 EJF
  293 NXC
  108 EHL
    6 JET
  120 EKN
   49 EHK
    5 LCN
 1232 DYW
    7 ELB
   89 NFS
   17 EEA
   62 NPK
  417 KMW
   24 ECT
  238 ECN
  173 ECO
    3 MYB
   74 DYT
   13 EJX
    8 NQA
    1 KOO
    2 PNP
   12 PZY
  660 DYJ
  731 DYO
   62 KCR
    8 EEJ
   40 ECP
   13 ECR
    2 PIP
    5 KLC
    3 EHS
  125 EAZ
    4 PNN
    4 EJP
    9 EGM
    3 DZH
    1 JER
    3 EFS
   11 NPZ
   12 NTK
   31 LQZ
    8 EAY
    8 POW
    2 KOL
    1 KZN
    1 MMD
    2 OYH
  112 NRD
    4 EBP
   12 PLC
    1 ORY
    2 PHR
   55 OZR
    5 JEQ
    2 NYD
    3 EHQ
    4 EFC
    5 PME
   15 EKD
   15 EKE
    1 PLH
   37 EBR
    2 QJC
    5 KZP
    1 NFQ
    1 EBE
   39 ELJ
    3 EAG
   12 EHA
    1 EMR
    2 ELA
    2 EKY
    2 ECQ




MEDICALSPECIALTY PRODUCTCODE DEVICENAME
---------------- ----------- ----------
DE               OZR         Intraoral Pressure Gradient Device
DE               DYH         Adhesive, Bracket And Tooth Conditioner, Resin
DE               DYJ         Retainer, Screw Expansion, Orthodontic
DE               DYN         Mouthpiece, Saliva Ejector
DE               DYO         Band, Material, Orthodontic
DE               DYT         Maintainer, Space Preformed, Orthodontic
DE               DYW         Bracket, Plastic, Orthodontic
DE               DYX         Lock, Wire, And Ligature, Intraoral
DE               DZA         Drill, Dental, Intraoral
DE               DZB         Headgear, Extraoral, Orthodontic
DE               DZC         Wire, Orthodontic
DE               DZD         Tube, Orthodontic
DE               DZE         Implant, Endosseous, Root-Form
DE               DZH         Saw, Bone, Ac-Powered
DE               DZI         Drill, Bone, Powered
DE               DZJ         Driver, Wire, And Bone Drill, Manual
DE               DZL         Screw, Fixation, Intraosseous
DE               DZM         Needle, Dental
DE               DZN         Instruments, Dental Hand
DE               DZP         Instrument, Diamond, Dental
DE               EAT         Tester, Pulp
DE               EAX         Mirror, Mouth
DE               EAY         Light, Fiber Optic, Dental
DE               EAZ         Light, Operating, Dental
DE               EBA         Light, Surgical Headlight
DE               EBC         Sealant, Pit And Fissure, And Conditioner
DE               EBD         Coating, Filling Material, Resin
DE               EBE         Coating, Denture Hydrophilic, Resin
DE               EBF         Material, Tooth Shade, Resin
DE               EBG         Crown And Bridge, Temporary, Resin
DE               EBH         Material, Impression Tray, Resin
DE               EBI         Resin, Denture, Relining, Repairing, Rebasing
DE               EBL         Pin, Retentive And Splinting, And Accessory Instruments
DE               EBO         Denture Repair Kit
DE               EBP         Reliner, Denture, Over The Counter
DE               EBR         Unit, Suction Operatory
DE               EBW         Controller, Foot, Handpiece And Cord
DE               EBZ         Activator, Ultraviolet, For Polymerization
DE               ECB         Unit, Syringe, Air And/Or Water
DE               ECI         Band, Elastic, Orthodontic
DE               ECM         Band, Preformed, Orthodontic
DE               ECN         Clamp, Wire, Orthodontic
DE               ECO         Spring, Orthodontic
DE               ECP         Instrument, Ligature Tucking, Orthodontic
DE               ECQ         Aligner, Bracket, Orthodontic
DE               ECR         Setter, Band, Orthodontic
DE               ECS         Pusher, Band, Orthodontic
DE               ECT         Driver, Band, Orthodontic
DE               EEA         Plate, Base, Shellac
DE               EEF         Clamp, Rubber Dam
DE               EEG         Heat Source For Bleaching Teeth
DE               EEJ         Guard, Disk
DE               EFA         Handpiece, Belt And/Or Gear Driven, Dental
DE               EFB         Handpiece, Air-Powered, Dental
DE               EFC         Warmer, Anesthetic Tube
DE               EFD         Amalgamator, Dental, Ac-Powered
DE               EFH         Paper, Articulation
DE               EFK         Forceps, Articulation Paper
DE               EFL         Forceps, Dressing, Dental
DE               EFN         Cotton, Roll
DE               EFS         Unit, Oral Irrigation
DE               EFT         Cleanser, Denture, Over The Counter
DE               EFW         Toothbrush, Manual
DE               EGD         Wax, Dental, Intraoral
DE               EGG         Attachment, Precision, All
DE               EGM         Injector, Jet, Mechanical-Powered
DE               EGN         Scissors, Surgical Tissue, Dental
DE               EGS         Handpiece, Contra- And Right-Angle Attachment, Dental
DE               EGZ         Holder, Film, X-Ray
DE               EHA         Aligner, Beam, X-Ray
DE               EHJ         Disk, Abrasive
DE               EHK         Cup, Prophylaxis
DE               EHL         Point, Abrasive
DE               EHM         Strip, Polishing Agent
DE               EHO         Bar, Preformed
DE               EHP         Clasp, Preformed
DE               EHQ         Cusp, Preformed
DE               EHS         Cushion, Denture, Over The Counter
DE               EHY         Tray, Impression, Preformed
DE               EHZ         Evacuator, Oral Cavity
DE               EIA         Unit, Operative Dental
DE               EIC         Syringe, Periodontic, Endodontic, Irrigating
DE               EID         Syringe, Restorative And Impression Material
DE               EIE         Dam, Rubber
DE               EIF         Accessories, Retractor, Dental
DE               EIG         Retractor, All Types
DE               EIH         Powder, Porcelain
DE               EIK         Carver, Wax, Dental
DE               EIL         Gauge, Depth, Instrument, Dental
DE               EIR         Scissors, Collar And Crown
DE               EIS         Remover, Crown
DE               EIX         Probe, Periodontic
DE               EIY         Instrument, Filling, Plastic, Dental
DE               EJB         Handle, Instrument, Dental
DE               EJE         Frame, Rubber Dam
DE               EJF         Bracket, Metal, Orthodontic
DE               EJG         Forceps, Rubber Dam Clamp
DE               EJH         Alloy, Metal, Base
DE               EJI         Syringe, Cartridge
DE               EJJ         Alloy, Amalgam
DE               EJK         Liner, Cavity, Calcium Hydroxide
DE               EJL         Bur, Dental
DE               EJP         Articulators
DE               EJQ         Wheel, Polishing Agent
DE               EJR         Agent, Polishing, Abrasive, Oral Cavity
DE               EJS         Alloy, Other Noble Metal
DE               EJT         Alloy, Gold-Based Noble Metal
DE               EJX         Anchor, Preformed
DE               EJY         Pliers, Operative
DE               EJZ         Knife, Margin Finishing, Operative
DE               EKB         Explorer, Operative
DE               EKC         Excavator, Dental, Operative
DE               EKD         Instrument, Cutting, Operative
DE               EKE         Curette, Operative
DE               EKF         Instrument, Contouring, Matrix, Operative
DE               EKG         Condenser, Amalgam And Foil, Operative
DE               EKH         Carver, Dental Amalgam, Operative
DE               EKI         Carrier, Amalgam, Operative
DE               EKJ         Burnisher, Operative
DE               EKK         Spreader, Pulp Canal Filling Material, Endodontic
DE               EKL         Point, Silver, Endodontic
DE               EKM         Gutta-Percha
DE               EKN         Point, Paper, Endodontic
DE               EKO         Denture Preformed (Partially Prefabricated Denture)
DE               EKP         Reamer, Pulp Canal, Endodontic
DE               EKQ         Preparer, Root Canal Endodontic
DE               EKR         Plugger, Root Canal, Endodontic
DE               EKS         File, Pulp Canal, Endodontic
DE               EKT         Curette, Endodontic
DE               EKW         Broach, Endodontic
DE               EKX         Handpiece, Direct Drive, Ac-Powered
DE               EKY         Handpiece, Water-Powered
DE               EKZ         Unit, Electrosurgical, And Accessories, Dental
DE               ELA         Instrument, Hand, Calculus Removal
DE               ELB         Scaler, Rotary
DE               ELC         Scaler, Ultrasonic
DE               ELE         Implant, Subperiosteal
DE               ELJ         Teeth, Artificial, Posterior With Metal Insert
DE               ELL         Teeth, Porcelain
DE               ELM         Denture, Plastic, Teeth
DE               ELR         Post, Root Canal
DE               ELS         Splint, Endodontic Stabilizing
DE               ELW         Material, Impression
DE               ELZ         Crown, Preformed
DE               EMA         Cement, Dental
DE               EMB         Zinc Oxide Eugenol
DE               EMD         Hemostat, Surgical
DE               EME         Punch, Biopsy, Surgical
DE               EMG         Forceps, Tooth Extractor, Surgical
DE               EMH         Forceps, Rongeur, Surgical
DE               EMI         File, Bone, Surgical
DE               EMJ         Elevator, Surgical, Dental
DE               EMK         Curette, Surgical, Dental
DE               EML         Chisel, Bone, Surgical
DE               EMM         Chisel, Osteotome, Surgical
DE               EMN         Scaler, Periodontic
DE               EMO         Knife, Periodontic
DE               EMP         Marker, Periodontic
DE               EMQ         Hoe, Periodontic
DE               EMR         File, Periodontic
DE               EMS         Curette, Periodontic
DE               JEP         Retainer, Matrix
DE               JEQ         Toothbrush, Powered
DE               JER         Cleaner, Denture, Mechanical
DE               JES         Floss, Dental
DE               JET         Pick, Massaging
DE               JEX         Plier, Orthodontic
DE               JEY         Plate, Bone
DE               KCQ         Tube Impression And Matrix
DE               KCR         Facebow
DE               KHR         Absorber, Saliva, Paper
DE               KIF         Resin, Root Canal Filling
DE               KKO         Ring, Teething, Fluid-Filled
DE               KLC         Chair, Dental, With Operative Unit
DE               KLE         Agent, Tooth Bonding, Resin
DE               KMT         Tray, Fluoride, Disposable
DE               KMW         Handpiece, Rotary Bone Cutting
DE               KMY         Positioner, Tooth, Preformed
DE               KOJ         Airbrush
DE               KOL         Adhesive, Denture, Carboxymethylcellulose Sodium (32%) And Ethylene-Oxide Homopolymer
DE               KOO         Adhesive, Denture, Polyvinyl Methylether Maleic Acid Calcium-Sodium Double Salt
DE               KXR         Applicator, Resin
DE               KXX         Adhesive, Denture, Karaya And Ethylene-Oxide Homopolymer
DE               KZN         Scanner, Color
DE               KZP         Solution, Cement Dissolving
DE               LBH         Varnish, Cavity
DE               LCN         Scraper, Tongue
DE               LFC         Device, Caries Detection
DE               LPK         Bone Grafting Material, For Dental Bone Repair
DE               LQZ         Device, Jaw Repositioning
DE               LRK         Device, Anti-Snoring
DE               LYC         Bone Grafting Material, Synthetic
DE               LZD         Joint, Temporomandibular, Implant
DE               MDL         Implant, Transmandibular
DE               MMD         Toothbrush, Ionic, Battery-Powered
DE               MPI         Glenoid Fossa Prosthesis
DE               MQN         External Mandibular Fixator And/Or Distractor
DE               MZW         Dental Cement W/Out Zinc-Oxide Eugenol As An Ulcer Covering For Pain Relief
DE               NBL         Laser, Fluorescence Caries Detection
DE               NDP         Accessories, Implant, Dental, Endosseous
DE               NEI         Prosthesis, Condyle, Mandibular, Temporary
DE               NFQ         Device, Dental Sonography, For Monitoring Jaw Sounds
DE               NFS         Device, Jaw Tracking, For Monitoring Jaw Positions
DE               NHA         Abutment, Implant, Dental, Endosseous
DE               NJM         Bracket, Ceramic, Orthodontic
DE               NOF         System, Optical Impression, Computer Assisted Design And Manufacturing (Cad/Cam) Of Den...
DE               NPK         Barrier, Synthetic, Intraoral
DE               NPL         Barrier, Animal Source, Intraoral
DE               NPM         Bone Grafting Material, Animal Source
DE               NPZ         Bone Grafting Material, Dental, With Biologic Component
DE               NQA         Biologic Material, Dental
DE               NRD         Unit, Operative Dental, Accessories
DE               NRU         Chair, Dental, Without Operative Unit
DE               NTK         Caries Detector, Laser Light, Transmission
DE               NUN         Bone Grafting Material, Human Source
DE               NXC         Aligner, Sequential
DE               NXV         Diagnostic Light, Soft Tissue Detector
DE               NXZ         Dental Hygiene Kit
DE               NYD         Endodontic Kit
DE               NYE         Fixture Mount Kit
DE               NYH         Plaque Disclosing Kit
DE               OAT         Implant, Endosseous, Orthodontic
DE               OFW         Restorative Instrument And Component Tray
DE               OFX         General Purpose Dental Tray
DE               OFY         Dental Implant Surgical Tray
DE               OHP         Expiratory Resistance Valve, Intranasal, For Obstructive Sleep Apnea
DE               OIV         Dental Amalgam
DE               ORY         Prelude Tongue Suspension System
DE               OYH         Orthodontic Vibratory Accessory
DE               PHR         Diammine Silver Fluoride Dental Hypersensitivity Varnish
DE               PIP         Prophy Powder, Airbrush Accessory
DE               PLC         Sleep Appliances With Patient Monitoring
DE               PLH         Orthodontic Led Accessory
DE               PLV         Dental Stereotaxic Instrument
DE               PME         External Cleaning Solution
DE               PNN         Orthodontic Software
DE               PNP         Dental Abutment Design Software For Dental Laboratory
DE               POW         Crown And Bridge, Long-Term Temporary, Resin
DE               PWL         Oral Surgery Tray
DE               PZY         Additively Manufactured, Preformed, Resin Denture Tooth
DE               QJC         Plaque Disclosing Agent
DE               MYB         Pillow, Cervical (For Mild Sleep Apnea)
DE               NEA         Cement, Ear, Nose And Throat
DE               NSB         Patient Personal Hygiene Kit
DE               EAG         Cephalometer
DE               EAP         Unit, X-Ray, Intraoral
DE               EHD         Unit, X-Ray, Extraoral With Timer
DE               MUH         System, X-Ray, Extraoral Source, Digital



#>
