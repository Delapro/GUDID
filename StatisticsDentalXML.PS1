# StatisticsDentalXML.PS1 - Streaming, namespace-sichere Fassung
# Ersatz für StatisticsDentalXML.PS1: verarbeitet die von Join erstellte XML
# geräteweise statt die gesamte Datei in $x zu laden.
# PowerShell 7 unter Linux / Windows.
$ErrorActionPreference = 'Stop'

$xmlDir = Join-Path $PSScriptRoot 'Dental-xml-Artefakt'
$outDir = Join-Path $PSScriptRoot 'Statistics-Output'
New-Item -Path $outDir -ItemType Directory -Force | Out-Null

"Download FDA FoiClass"
$zipFile = Join-Path $PSScriptRoot 'foiclass.zip'
$foiDir = Join-Path $PSScriptRoot 'foiclass'
Invoke-WebRequest -Uri 'https://www.accessdata.fda.gov/premarket/ftparea/foiclass.zip' -OutFile $zipFile
"Expand FDA FoiClass"
Expand-Archive -LiteralPath $zipFile -DestinationPath $foiDir -Force
$foiPath = Join-Path $foiDir 'foiclass.txt'
if (-not (Test-Path -LiteralPath $foiPath)) { throw "FDA-Datei fehlt: $foiPath" }
$dental = @(Import-Csv -LiteralPath $foiPath -Delimiter '|' | Where-Object medicalspecialty -eq 'DE')

# Alle Dateien in definierter Reihenfolge verarbeiten.
$files = @(Get-ChildItem -LiteralPath $xmlDir -Recurse -File |
    Where-Object { $_.Name -like '*-dental.xml' } |
    Sort-Object Name, FullName)
"Gefundene XML-Dateien: $($files.Count)"
if ($files.Count -eq 0) { throw "Keine *-dental.xml unter $xmlDir gefunden" }

function Get-ChildText {
    param(
        [System.Xml.XmlNode] $Parent,
        [string] $XPath,
        [System.Xml.XmlNamespaceManager] $Namespaces
    )
    $node = $Parent.SelectSingleNode($XPath, $Namespaces)
    if ($null -eq $node) { return '' }
    return $node.InnerText
}

function Test-GS1Checksum {
    param([string] $GTIN)
    if ([string]::IsNullOrWhiteSpace($GTIN) -or $GTIN -cnotmatch '^[0-9]+$') { return $false }
    $sum = 0
    $multiplyByThree = $false
    for ($i = $GTIN.Length - 1; $i -ge 0; $i--) {
        $digit = [int]::Parse($GTIN.Substring($i, 1))
        if ($multiplyByThree) { $sum += 3 * $digit } else { $sum += $digit }
        $multiplyByThree = -not $multiplyByThree
    }
    return ($sum % 10 -eq 0)
}


# Unabhaengige Berechnung der SOLL-Pruefziffer aus dem Datenanteil
# (von rechts im Nutzdatenanteil beginnend: 3, 1, 3, 1, ...).
function Get-GS1ExpectedCheckDigit {
    param([string] $Payload)
    if ([string]::IsNullOrEmpty($Payload) -or $Payload -cnotmatch '^[0-9]+$') { return '' }
    $sum = 0
    $factor = 3
    for ($i = $Payload.Length - 1; $i -ge 0; $i--) {
        $sum += ([int]::Parse($Payload.Substring($i, 1)) * $factor)
        if ($factor -eq 3) { $factor = 1 } else { $factor = 3 }
    }
    return [string]((10 - ($sum % 10)) % 10)
}

# Selbsttest gegen bekannte korrekte und inkorrekte GTINs.
foreach ($sample in @('4006381333931', '07640173184379', '04571269943255')) {
    if (-not (Test-GS1Checksum $sample)) {
        throw "GS1-Selbsttest fehlgeschlagen: $sample wurde als ungueltig erkannt."
    }
    if ((Get-GS1ExpectedCheckDigit ($sample.Substring(0, $sample.Length - 1))) -ne
        $sample.Substring($sample.Length - 1)) {
        throw "GS1-Selbsttest fehlgeschlagen: falsche errechnete Pruefziffer fuer $sample."
    }
}
if (Test-GS1Checksum '4006381333932') {
    throw 'GS1-Selbsttest fehlgeschlagen: falsche Pruefziffer akzeptiert.'
}

function Write-CsvLine {
    param([System.IO.TextWriter] $Writer, [object[]] $Values)
    $columns = foreach ($value in $Values) {
        $s = [string]$value
        '"' + $s.Replace('"', '""') + '"'
    }
    $Writer.WriteLine(($columns -join ','))
}

$stat = [ordered]@{
    Total = 0
    GS1 = 0
    HIBC = 0
    Packaging = 0
    Primary = 0
    GS1LotSerial = 0
    GS1BadChecksumPrimarySingle = 0
    GS1InvalidLengthPrimarySingle = 0
    GS1InvalidCharsPrimarySingle = 0
    BothGS1HIBC = 0
    OnlyGS1 = 0
    OnlyHIBC = 0
    NeitherGS1NorHIBC = 0
    NotCommercial = 0
    More1 = 0
    More2 = 0
    More3 = 0
    More4 = 0
    More5 = 0
    TeethELM = 0
    TeethVITA = 0
}
$manufacturers = @{}                # Hersteller -> Anzahl Geräte
$gs1LotSerialManufacturers = @{}    # Hersteller mit GS1 und Lot und Serial
$codeCompanies = @{}               # FDA-Code -> Hashtable von Herstellern
$gmdnCounts = @{}                  # GMDN-Name -> Anzahl der Zuordnungen
$catalogMatches = [System.Collections.Generic.List[string]]::new()
$straumannIds = [System.Collections.Generic.List[string]]::new()
$startTime = Get-Date

# Größere Ergebnislisten auf Platte schreiben, nicht im RAM sammeln.
$utf8 = [System.Text.UTF8Encoding]::new($true)
$teethWriter = [System.IO.StreamWriter]::new((Join-Path $outDir 'Zaehne-ELM.csv'), $false, $utf8)
$vitaWriter  = [System.IO.StreamWriter]::new((Join-Path $outDir 'Zaehne-VITA.csv'), $false, $utf8)
$gs1Writer = [System.IO.StreamWriter]::new((Join-Path $outDir 'GS1-DI-Auffaelligkeiten.csv'), $false, $utf8)
try {
    Write-CsvLine $teethWriter @('CompanyName','BrandName','DeviceDescription','CatalogNumber')
    Write-CsvLine $vitaWriter  @('CompanyName','BrandName','DeviceDescription','CatalogNumber')
    Write-CsvLine $gs1Writer @(
        'DeviceId','Problem','GTINLength','ExpectedCheckDigit','ActualCheckDigit',
        'CompanyName','BrandName','VersionModelNumber','CatalogNumber',
        'DevicePublishDate','YearsSincePublication','PublicVersionDate',
        'DistributionStatus','DistributionEndDate','DeviceRecordStatus',
        'PublicDeviceRecordKey','FDAProductCodes','InspectionDateUTC'
    )

    foreach ($file in $files) {
        "Auswerten: $($file.Name) ($([math]::Round($file.Length / 1MB)) MB)"
        $settings = [System.Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $reader = [System.Xml.XmlReader]::Create($file.FullName, $settings)
        $fileTotal = 0
        try {
            # Wichtig: ReadOuterXml() rückt selbst zum nächsten XML-Knoten vor.
            # Nicht zusätzlich Reader.Read() am Schleifenende aufrufen,
            # sonst würde jedes zweite <device> übersprungen.
            while (-not $reader.EOF) {
                if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and
                    $reader.LocalName -eq 'device') {
                    $fragment = $reader.ReadOuterXml()
                    $device = ([xml]$fragment).DocumentElement

                    # GUDID verwendet normalerweise den Default-Namespace
                    # http://www.fda.gov/cdrh/gudid. Ein XPath ohne Prefix
                    # findet diese Elemente NICHT.
                    $ns = [System.Xml.XmlNamespaceManager]::new($device.OwnerDocument.NameTable)
                    $prefix = ''
                    if (-not [string]::IsNullOrEmpty($device.NamespaceURI)) {
                        $ns.AddNamespace('g', $device.NamespaceURI)
                        $prefix = 'g:'
                    }

                    $stat.Total++
                    $fileTotal++

                    $company = Get-ChildText $device "./${prefix}companyName" $ns
                    if (-not $manufacturers.ContainsKey($company)) { $manufacturers[$company] = 0 }
                    $manufacturers[$company]++

                    $ids = @($device.SelectNodes("./${prefix}identifiers/${prefix}identifier", $ns))
                    $distributionStatus = Get-ChildText $device "./${prefix}deviceCommDistributionStatus" $ns
                    # Bereits beim ersten Datensatz prüfen, ob die XPath-Ausdrücke
                    # wirklich Inhalte liefern. Sonst wären alle Ergebnisse 0.
                    if ($stat.Total -eq 1) {
                        Write-Host "XML Namespace: '$($device.NamespaceURI)'"
                        Write-Host "Pruefung erstes Geraet: Firma='$company', Identifier=$($ids.Count), Vertrieb='$distributionStatus'"
                        if ([string]::IsNullOrWhiteSpace($company) -or
                            $ids.Count -eq 0 -or
                            [string]::IsNullOrWhiteSpace($distributionStatus)) {
                            throw 'XML-Felder fehlen: Namespace oder XPath-Schema pruefen.'
                        }
                    }

                    $hasGs1 = $false
                    $hasHibc = $false
                    $hasPackage = $false
                    $hasPrimary = $false
                    foreach ($id in $ids) {
                        $agency = Get-ChildText $id "./${prefix}deviceIdIssuingAgency" $ns
                        $type = Get-ChildText $id "./${prefix}deviceIdType" $ns
                        if ($agency -eq 'GS1') { $hasGs1 = $true }
                        if ($agency -eq 'HIBCC') { $hasHibc = $true }
                        if ($type -eq 'Package') { $hasPackage = $true }
                        if ($type -eq 'Primary') { $hasPrimary = $true }
                        if ($ids.Count -eq 1 -and $agency -eq 'GS1' -and $type -eq 'Primary') {
                            $di = Get-ChildText $id "./${prefix}deviceId" $ns
                            $digitsOnly = ($di -cmatch '^[0-9]+$')
                            $lengthOk = ($di.Length -in @(8, 12, 13, 14))
                            $checksumOk = Test-GS1Checksum $di

                            if (-not $checksumOk) { $stat.GS1BadChecksumPrimarySingle++ }
                            if (-not $digitsOnly) { $stat.GS1InvalidCharsPrimarySingle++ }
                            if (-not $lengthOk) { $stat.GS1InvalidLengthPrimarySingle++ }

                            # Schreibe alle auffaelligen DIs auf Platte. Keine GTIN
                            # stillschweigend trimmen oder fuehrende Nullen entfernen.
                            if (-not $checksumOk -or -not $lengthOk) {
                                $problem = if (-not $digitsOnly) { 'NotNumeric' }
                                           elseif (-not $lengthOk -and $checksumOk) { 'UnusualGTINLength' }
                                           elseif (-not $lengthOk) { 'BadChecksumAndLength' }
                                           else { 'BadCheckDigit' }
                                $expected = ''
                                $actual = ''
                                if ($digitsOnly -and $di.Length -ge 2) {
                                    $expected = Get-GS1ExpectedCheckDigit ($di.Substring(0, $di.Length - 1))
                                    $actual = $di.Substring($di.Length - 1)
                                }
                                $pubDate = Get-ChildText $device "./${prefix}devicePublishDate" $ns
                                $ageYears = ''
                                if ($pubDate -match '^\d{4}-\d{2}-\d{2}$') {
                                    try {
                                        $published = [datetime]::ParseExact(
                                            $pubDate, 'yyyy-MM-dd',
                                            [System.Globalization.CultureInfo]::InvariantCulture)
                                        $ageYears = [math]::Round(
                                            ([datetime]::UtcNow.Date - $published).TotalDays / 365.2425, 1)
                                    } catch { $ageYears = '' }
                                }
                                $fdaCodes = @($device.SelectNodes(
                                    "./${prefix}productCodes/${prefix}fdaProductCode/${prefix}productCode", $ns) |
                                    ForEach-Object { $_.InnerText.Trim() }) -join ';'
                                Write-CsvLine $gs1Writer @(
                                    $di, $problem, $di.Length, $expected, $actual,
                                    $company,
                                    (Get-ChildText $device "./${prefix}brandName" $ns),
                                    (Get-ChildText $device "./${prefix}versionModelNumber" $ns),
                                    (Get-ChildText $device "./${prefix}catalogNumber" $ns),
                                    $pubDate, $ageYears,
                                    (Get-ChildText $device "./${prefix}publicVersionDate" $ns),
                                    $distributionStatus,
                                    (Get-ChildText $device "./${prefix}deviceCommDistributionEndDate" $ns),
                                    (Get-ChildText $device "./${prefix}deviceRecordStatus" $ns),
                                    (Get-ChildText $device "./${prefix}publicDeviceRecordKey" $ns),
                                    $fdaCodes, [datetime]::UtcNow.ToString('yyyy-MM-dd')
                                )
                                Write-Host "GS1 DI auffaellig: $di [$problem] Firma='$company'; Vertrieb='$distributionStatus'; Publish='$pubDate'"
                            }
                        }
                        if ($agency -eq 'GS1' -and $company -match 'straumann' -and $straumannIds.Count -lt 5) {
                            $straumannIds.Add((Get-ChildText $id "./${prefix}deviceId" $ns))
                        }
                    }
                    if ($hasGs1) { $stat.GS1++ }
                    if ($hasHibc) { $stat.HIBC++ }
                    if ($hasGs1 -and $hasHibc) { $stat.BothGS1HIBC++ }
                    elseif ($hasGs1) { $stat.OnlyGS1++ }
                    elseif ($hasHibc) { $stat.OnlyHIBC++ }
                    else { $stat.NeitherGS1NorHIBC++ }
                    if ($hasPackage) { $stat.Packaging++ }
                    if ($hasPrimary) { $stat.Primary++ }

                    if ($hasGs1 -and
                        (Get-ChildText $device "./${prefix}lotBatch" $ns) -eq 'true' -and
                        (Get-ChildText $device "./${prefix}serialNumber" $ns) -eq 'true') {
                        $stat.GS1LotSerial++
                        $gs1LotSerialManufacturers[$company] = $true
                    }
                    if ($distributionStatus -ne 'In Commercial Distribution') {
                        $stat.NotCommercial++
                    }
                    if ($ids.Count -gt 1) { $stat.More1++ }
                    if ($ids.Count -gt 2) { $stat.More2++ }
                    if ($ids.Count -gt 3) { $stat.More3++ }
                    if ($ids.Count -gt 4) { $stat.More4++ }
                    if ($ids.Count -gt 5) { $stat.More5++ }

                    $isTooth = $false
                    foreach ($codeNode in $device.SelectNodes("./${prefix}productCodes/${prefix}fdaProductCode/${prefix}productCode", $ns)) {
                        $code = $codeNode.InnerText.Trim()
                        if ($code.Length -eq 0) { continue }
                        if (-not $codeCompanies.ContainsKey($code)) { $codeCompanies[$code] = @{} }
                        $codeCompanies[$code][$company] = $true
                        if ($code -eq 'ELM') { $isTooth = $true }
                    }
                    foreach ($gmdnNode in $device.SelectNodes("./${prefix}gmdnTerms/${prefix}gmdn/${prefix}gmdnPTName", $ns)) {
                        $gmdn = $gmdnNode.InnerText.Trim()
                        if ($gmdn.Length -eq 0) { continue }
                        if (-not $gmdnCounts.ContainsKey($gmdn)) { $gmdnCounts[$gmdn] = 0 }
                        $gmdnCounts[$gmdn]++
                    }

                    if ($isTooth) {
                        $stat.TeethELM++
                        $csvRow = @($company,
                            (Get-ChildText $device "./${prefix}brandName" $ns),
                            (Get-ChildText $device "./${prefix}deviceDescription" $ns),
                            (Get-ChildText $device "./${prefix}catalogNumber" $ns))
                        Write-CsvLine $teethWriter $csvRow
                        if ($company -match 'vita') {
                            $stat.TeethVITA++
                            Write-CsvLine $vitaWriter $csvRow
                        }
                    }
                    if ((Get-ChildText $device "./${prefix}catalogNumber" $ns) -eq '66017316') {
                        $catalogMatches.Add("$company / $(Get-ChildText $device "./${prefix}brandName" $ns) / 66017316")
                    }
                    if (($stat.Total % 100000) -eq 0) {
                        Write-Host "Verarbeitete Geräte: $($stat.Total)"
                    }
                    # Fragment und Dokument werden nach dem Durchlauf freigegeben.
                    continue
                }
                [void]$reader.Read()
            }
        }
        finally { $reader.Dispose() }
        Write-Host "$($file.Name) Anzahl: $fileTotal"
    }
}
finally {
    $teethWriter.Dispose()
    $vitaWriter.Dispose()
    $gs1Writer.Dispose()
}
if ($stat.Total -eq 0) { throw 'Keine <device>-Elemente gefunden!' }

"Verarbeitungszeit: $((Get-Date) - $startTime)"
"Anzahl: $($stat.Total)"
"GS1 Barcodes: $($stat.GS1)"
"GS1-DI mit fehlerhafter Pruefsumme (nur einzeln und Primary): $($stat.GS1BadChecksumPrimarySingle)"
"GS1-DI mit nicht numerischen Zeichen (nur einzeln und Primary): $($stat.GS1InvalidCharsPrimarySingle)"
"GS1-DI mit ungewoehnlicher Laenge (nur einzeln und Primary): $($stat.GS1InvalidLengthPrimarySingle)"
"GS1-DI-Details: Statistics-Output/GS1-DI-Auffaelligkeiten.csv"
"HIBC Barcodes: $($stat.HIBC)"
"GS1 und HIBC (beide): $($stat.BothGS1HIBC)"
"Nur GS1: $($stat.OnlyGS1)"
"Nur HIBC: $($stat.OnlyHIBC)"
"Weder GS1 noch HIBC: $($stat.NeitherGS1NorHIBC)"
"Verpackungen: $($stat.Packaging)"
"Reale Produkte: $($stat.Primary)"
"GS1-Produkte mit Lot und Seriennummer: $($stat.GS1LotSerial)"
"GS1-Hersteller mit Lot und Seriennummer: $($gs1LotSerialManufacturers.Count)"
"Nicht mehr im Vertrieb: $($stat.NotCommercial)"
"Produkte mit mehr 1 Identifier: $($stat.More1)"
"Produkte mit mehr 2 Identifier: $($stat.More2)"
"Produkte mit mehr 3 Identifier: $($stat.More3)"
"Produkte mit mehr 4 Identifier: $($stat.More4)"
"Produkte mit mehr 5 Identifier: $($stat.More5)"
"Hersteller: $($manufacturers.Count), mit insgesamt $($stat.Total) Produkten"
"Hersteller (erste 5 alphabetisch):"
$manufacturers.Keys | Sort-Object | Select-Object -First 5 | ForEach-Object { "$_ : $($manufacturers[$_])" }
"GS1 Straumann Identifier (erste 5):"
$straumannIds
"CatalogNumber 66017316:"
$catalogMatches

"FDA-Dental-Produktcodes aus FoiClass:"
$dental | Where-Object { $codeCompanies.ContainsKey([string]$_.ProductCode) } |
    Select-Object medicalspecialty, ProductCode, devicename | Format-Table -AutoSize | Out-Host

"Welche Firma bedient welchen FDA-Code? -> Statistics-Output/FDA-Code-Hersteller.csv"
$codesWriter = [System.IO.StreamWriter]::new((Join-Path $outDir 'FDA-Code-Hersteller.csv'), $false, $utf8)
try {
    Write-CsvLine $codesWriter @('Code','CompanyName')
    foreach ($code in ($codeCompanies.Keys | Sort-Object)) {
        foreach ($company in ($codeCompanies[$code].Keys | Sort-Object)) {
            Write-CsvLine $codesWriter @($code, $company)
        }
    }
}
finally { $codesWriter.Dispose() }

"Codes, in denen Kulzer, bredent und Candulor vertreten sind:"
foreach ($code in ($codeCompanies.Keys | Sort-Object)) {
    $names = @($codeCompanies[$code].Keys)
    if (@($names | Where-Object { $_ -match 'kulzer' }).Count -gt 0 -and
        @($names | Where-Object { $_ -match 'bredent' }).Count -gt 0 -and
        @($names | Where-Object { $_ -match 'candulor' }).Count -gt 0) {
        $code
    }
}
"Alle Zaehne (ELM): $($stat.TeethELM) -> Statistics-Output/Zaehne-ELM.csv"
"VITA-Zaehne: $($stat.TeethVITA) -> Statistics-Output/Zaehne-VITA.csv"

"GMDN-Verteilung (aufsteigend nach Anzahl):"
$gmdnWriter = [System.IO.StreamWriter]::new((Join-Path $outDir 'GMDN-Verteilung.csv'), $false, $utf8)
try {
    Write-CsvLine $gmdnWriter @('Count','GMDN')
    foreach ($entry in ($gmdnCounts.GetEnumerator() | Sort-Object Value, Key)) {
        Write-CsvLine $gmdnWriter @($entry.Value, $entry.Key)
    }
}
finally { $gmdnWriter.Dispose() }

"Unterschiedliche GMDN-Terme: $($gmdnCounts.Count)"

$gmdnCounts.GetEnumerator() |
    Sort-Object Value, Key |
    Select-Object -First 10 |
    ForEach-Object {
        "$($_.Value) : $($_.Key)"
    }

"Fertig: $outDir"
