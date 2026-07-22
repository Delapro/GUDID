# SQL-Datenbank anlegen
sqlite3 devices.db ".read schema.sql"

# Hilfsroutinen
function Get-BoolInt {
    param($Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    if ($Value -eq 'true') { return 1 }
    if ($Value -eq 'false') { return 0 }
    throw "Ungültiger Boolean-Wert: $Value"
}

function Get-TextOrNull {
    param($Node)
    if ($null -eq $Node) { return $null }

    # xsi:nil="true" behandeln
    $nilAttr = $Node.Attributes['xsi:nil']
    if ($nilAttr -and $nilAttr.Value -eq 'true') { return $null }

    $text = $Node.InnerText
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text
}

function Escape-SqlLiteral {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return 'NULL' }
    return "'" + $Value.Replace("'", "''") + "'"
}

function SqlValue {
    param($Value)

    if ($null -eq $Value) { return 'NULL' }

    switch ($Value.GetType().Name) {
        'Int32'   { return [string]$Value }
        'Int64'   { return [string]$Value }
        'Boolean' { return ($(if ($Value) {1} else {0})) }
        default   { return Escape-SqlLiteral ([string]$Value) }
    }
}

