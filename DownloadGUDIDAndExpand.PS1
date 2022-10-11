# GUDID downloaden
# TODO: aktuellen Link aus RSS-Feed ermitteln https://accessgudid.nlm.nih.gov/download.rss?files=full

# Import-Module BitsTransfer  # geht nur unter Windows!

Invoke-WebRequest https://accessgudid.nlm.nih.gov/release_files/download/gudid_full_release_20221001.zip
Expand-Archive ./gudid_full_release_20221001.zip
