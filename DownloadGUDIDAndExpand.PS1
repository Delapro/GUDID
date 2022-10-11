# GUDID downloaden
# TODO: aktuellen Link aus RSS-Feed ermitteln https://accessgudid.nlm.nih.gov/download.rss?files=full

# Import-Module BitsTransfer  # geht nur unter Windows!

# Baut Install-StartBitsTransfer in der einfachsten Variante nach, diese Funktion kann bei Powershell Core
# benutzt werden oder wenn es Rechteprobleme wegen der Fehlermeldung 0x800704DD bzw. -2147023651 gibt.
# Start-BitsTransfer -Source
# liefert
# $e=$Error[0]
# $e.Exception.ErrorCode -eq -2147023651
# Falls man nach Aufruf von Install-StartBitsTransfer doch die Originalvariante aufrufen möchte, muss man
# Bitstransfer\Start-BitsTransfer verwenden!
Function Install-StartBitsTransfer {

	# damit die Function verfügbar wird, muss sie mittels & ausgeführt werden und mit dem Scope global: versehen werden
	&{
		Function global:Start-BitsTransfer {
			[CmdletBinding()]
			Param(
				$Source, $Destination

			)

			If (-Not $Destination) {
				$Destination = $PWD
			}
			If (Test-Path -Type Container $Destination) {
				$Destination = Join-Path -Path $Destination -ChildPath ([System.IO.Path]::GetFilename($Source))
			}

			$wc = New-Object System.Net.WebClient

			$job1 = Register-ObjectEvent -InputObject $wc -EventName DownloadProgressChanged -SourceIdentifier WebClient.DownloadProgressChanged -MessageData $Source -Action {Write-Progress "Downloading: $($EventArgs.ProgressPercentage)% Completed" -Status $event.MessageData -PercentComplete $EventArgs.ProgressPercentage; }
			$job2 = Register-ObjectEvent -InputObject $wc -EventName DownloadFileCompleted -SourceIdentifier WebClient.DownloadFileComplete -MessageData $Destination -Action {Write-Host "Download Complete - $($event.MessageData)"; Unregister-Event -SourceIdentifier WebClient.DownloadProgressChanged; Unregister-Event -SourceIdentifier WebClient.DownloadFileComplete; }

			try {
			  $wc.DownloadFileAsync($Source, $Destination)
			} catch [System.Net.WebException] {
			  Write-Host "Cannot download $Source"
			} finally {
			  $wc.Dispose()
			}
			[console]::TreatControlCAsInput = $true
			while ($job1.state -ne "Stopped" -and $job2.state -ne "Stopped") {
				if ([console]::KeyAvailable)
				{
					$key = [system.console]::readkey($true)
					if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C"))
					{
						Write-Host "Try Terminating..."
						# klappt aber noch nicht
						break
					}
				}
				Start-Sleep -Milliseconds 100
			}
			[console]::TreatControlCAsInput = $false

			# wissenwertes zum Thema: https://blog.ironmansoftware.com/powershell-async-method/
			# ohne Progressbar: https://gist.github.com/SidShetye/3d0570d8514f4388346d8af9f314920c
			# noch weitere Informationen:
			# https://stackoverflow.com/questions/4926060/powershell-runspace-problem-with-downloadfileasync
			# https://stackoverflow.com/questions/73474912/powershell-100-ensure-idisposable-is-disposed-with-async-operations

			Remove-Job $job1, $Job2 -Force

		}
	}
}

Install-StartBitsTransfer

Start-BitsTransfer https://accessgudid.nlm.nih.gov/release_files/download/gudid_full_release_20221001.zip
Expand-Archive gudid_full_release_20221001.zip
