# Guarda a chave do GitHub para a ponte, criptografada pelo Windows (só este usuário, neste computador, consegue ler).
# Rode uma vez no PowerShell e cole a chave quando pedir. A chave não aparece na tela.
$arq = Join-Path $PSScriptRoot 'chave.txt'
$seg = Read-Host 'Cole a chave do GitHub (github_pat_...) e tecle Enter' -AsSecureString
if ($seg.Length -lt 20) { Write-Host 'Chave muito curta; nada foi gravado.'; exit 1 }
$seg | ConvertFrom-SecureString | Set-Content -LiteralPath $arq
Write-Host "Chave guardada em $arq (criptografada)."
