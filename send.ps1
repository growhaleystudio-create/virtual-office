# Kirim perintah ke office dari terminal. Contoh:
#   .\send.ps1 "Sales ke pantry"
#   .\send.ps1 -Agent Sales -Status "kirim 3 WA ke lead" -Ttl 600
param([string]$Text, [string]$Agent, [string]$Status, [int]$Ttl = 300)
$tok = (Select-String -Path "$PSScriptRoot\bridge.cfg" -Pattern '^token="(.*)"').Matches[0].Groups[1].Value
$h = @{ Authorization = "Bearer $tok" }
if ($Agent) {
  $b = @{ agent = $Agent; text = $Status; ttl = $Ttl } | ConvertTo-Json
  Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8765/status -Headers $h -Body $b -ContentType "application/json"
} else {
  $b = @{ text = $Text } | ConvertTo-Json
  Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8765/command -Headers $h -Body $b -ContentType "application/json"
}
