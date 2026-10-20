# JoinDentalXML_Streaming.ps1
# Fuehrt GUDID-Dental-XML-Dateien speichersparend zusammen.
# Erwartete Struktur je Quelldatei: <devices><device>...</device>...</devices>
# Laeuft mit PowerShell 7 auf ubuntu-latest.

$ErrorActionPreference = 'Stop'

$sourceDir = Join-Path $PSScriptRoot 'Dental-xml-Artefakt'
$outFile = Join-Path $sourceDir 'Gudid-Dental.xml'
$tempFile = "$outFile.tmp"

if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
    throw "Eingabeverzeichnis fehlt: $sourceDir"
}

# Falls Download-Artefakte noch ZIP-Dateien enthalten, erst entpacken.
$zips = @(
    Get-ChildItem -LiteralPath $sourceDir -File -Filter 'Dental-xml*.zip' |
        Sort-Object Name
)
foreach ($zip in $zips) {
    $destination = Join-Path $sourceDir $zip.BaseName
    Write-Host "Entpacke: $($zip.Name) -> $destination"
    Expand-Archive -LiteralPath $zip.FullName -DestinationPath $destination -Force
}

# Alle Quell-XMLs in deterministischer Reihenfolge; das Join-Ergebnis NICHT erneut einlesen.
$files = @(
    Get-ChildItem -LiteralPath $sourceDir -File -Recurse -Filter '*-dental.xml' |
        Where-Object { $_.FullName -ne $outFile } |
        Sort-Object Name, FullName
)
Write-Host "Gefundene Quell-XML-Dateien: $($files.Count)"
if ($files.Count -eq 0) {
    throw "Keine *-dental.xml-Quelldateien unter $sourceDir gefunden."
}

$readSettings = [System.Xml.XmlReaderSettings]::new()
$readSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
$readSettings.XmlResolver = $null

$writeSettings = [System.Xml.XmlWriterSettings]::new()
$writeSettings.Encoding = [System.Text.UTF8Encoding]::new($false)
$writeSettings.Indent = $false
$writeSettings.CloseOutput = $true

[long]$total = 0
$writer = $null
try {
    # Erst temporaer erzeugen, damit ein abgebrochener Run kein unvollstaendiges Artefakt erzeugt.
    $writer = [System.Xml.XmlWriter]::Create($tempFile, $writeSettings)
    $writer.WriteStartDocument()
    $writer.WriteStartElement('devices')

    $index = 0
    foreach ($file in $files) {
        $index++
        [long]$fileCount = 0
        Write-Host "[$index/$($files.Count)] Verarbeite: $($file.Name)"
        $reader = $null
        try {
            $reader = [System.Xml.XmlReader]::Create($file.FullName, $readSettings)
            [void]$reader.MoveToContent()
            if ($reader.NodeType -ne [System.Xml.XmlNodeType]::Element -or
                $reader.LocalName -ne 'devices') {
                throw "Unerwartetes Wurzelelement. Erwartet: <devices>."
            }

            # Nur echte <device>-Elemente uebernehmen, nicht Header oder <devices>-Wurzeln.
            # XmlWriter.WriteNode liest den jeweiligen Unterbaum fortlaufend.
            # WriteNode stellt den Reader bereits auf den naechsten Geschwisterknoten.
            # Deshalb nach WriteNode nicht zusaetzlich ReadToFollowing() aufrufen:
            # Das koennte jedes zweite <device> ueberspringen.
            while (-not $reader.EOF) {
                if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and
                    $reader.LocalName -eq 'device' -and $reader.Depth -eq 1) {
                    $writer.WriteNode($reader, $true)
                    $fileCount++
                    $total++
                    continue
                }
                [void]$reader.Read()
            }
        }
        catch {
            throw "Fehler in Quelldatei '$($file.FullName)': $($_.Exception.Message)"
        }
        finally {
            if ($null -ne $reader) { $reader.Dispose() }
        }
        Write-Host "  Geräte: $fileCount (gesamt: $total)"
    }

    $writer.WriteEndElement() # </devices>
    $writer.WriteEndDocument()
    $writer.Dispose()
    $writer = $null

    if ($total -eq 0) { throw 'Keine <device>-Elemente in Quelldateien gefunden.' }

    # Vollstaendige XML-Pruefung ohne die 3+ GB in den RAM zu laden.
    Write-Host 'Pruefe das zusammengefuehrte XML (Streaming-Validierung) ...'
    [long]$verified = 0
    $checker = [System.Xml.XmlReader]::Create($tempFile, $readSettings)
    try {
        while ($checker.Read()) {
            if ($checker.NodeType -eq [System.Xml.XmlNodeType]::Element -and
                $checker.LocalName -eq 'device') {
                $verified++
            }
        }
    }
    finally { $checker.Dispose() }
    if ($verified -ne $total) {
        throw "Gerätezahl stimmt nicht: geschrieben=$total, gelesen=$verified"
    }

    Move-Item -LiteralPath $tempFile -Destination $outFile -Force
    Write-Host "Fertig: $outFile"
    Write-Host "Verifizierte Geräte: $verified"
    Write-Host "Dateigrösse: $([math]::Round((Get-Item -LiteralPath $outFile).Length / 1MB)) MB"
}
finally {
    if ($null -ne $writer) { $writer.Dispose() }
    if (Test-Path -LiteralPath $tempFile -PathType Leaf) {
        Remove-Item -LiteralPath $tempFile -Force
    }
}
