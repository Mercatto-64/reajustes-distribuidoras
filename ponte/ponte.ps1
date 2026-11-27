<#
  Ponte semanal: baixa os dados PÚBLICOS da ANEEL e do IBGE aqui no Brasil e envia ao GitHub.

  Por que existe: o site de dados abertos da ANEEL não responde a conexões de fora do Brasil,
  e os servidores do GitHub ficam fora. Então um computador daqui só faz o download e repassa.

  O que ela faz (e só isso):
    1. baixa o CSV de tarifas da ANEEL e guarda só as linhas "Tarifa de Aplicação", A4, Verde;
    2. baixa a série do IPCA (IBGE/SIDRA, tabela 1737);
    3. envia esses dois arquivos para a pasta dados/ do repositório, num único commit.
  O GitHub então monta e publica a página sozinho.

  Ela NÃO lê nenhuma pasta da Mercatto e não abre nenhuma porta: só faz downloads públicos
  e um envio para o GitHub, usando uma chave que só pode alterar este repositório.

  Uso:
    .\ponte.ps1             # baixa e envia
    .\ponte.ps1 -SemEnviar  # só baixa e filtra (para testar), grava em .\trabalho\dados
  A chave fica em chave.txt, criptografada pelo Windows para o usuário que rodou guardar_chave.ps1.
#>
param(
    [switch]$SemEnviar,
    [string]$Repo = 'Mercatto-64/reajustes-distribuidoras',
    [int]$AnosHistorico = 10,
    [hashtable]$Extras = @{}   # arquivos a mais no mesmo commit: @{ 'caminho/no/repo' = 'C:\arquivo\local' }
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$aqui = $PSScriptRoot
$log = Join-Path $aqui 'ponte.log'
$trab = Join-Path $aqui 'trabalho'
$pastaDados = Join-Path $trab 'dados'
New-Item -ItemType Directory -Force $pastaDados | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)

$urlAneel = 'https://dadosabertos.aneel.gov.br/dataset/5a583f3e-1646-4f67-bf0f-69db4203e89e/resource/fcf2906c-7c32-4b9b-a637-054e7a5234f4/download/tarifas-homologadas-distribuidoras-energia-eletrica.csv'
$urlIpca = 'https://apisidra.ibge.gov.br/values/t/1737/n1/all/v/2266/p/last%20120?formato=json'

function Registrar([string]$t) {
    $l = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $t
    Write-Host $l
    Add-Content -LiteralPath $log -Value $l -Encoding UTF8
}
function Tentar([scriptblock]$acao, [string]$oque) {
    for ($i = 1; $i -le 3; $i++) {
        try { return & $acao }
        catch {
            if ($i -eq 3) { throw "Falhou ao $oque depois de 3 tentativas: $($_.Exception.Message)" }
            Registrar "Tentativa $i de $oque falhou ($($_.Exception.Message)); nova tentativa em 2 min."
            Start-Sleep -Seconds 120
        }
    }
}

try {
    # ---------- 1. ANEEL ----------
    $bruto = Join-Path $trab 'tarifas-aneel.csv'
    Registrar 'Baixando CSV da ANEEL...'
    Tentar { Invoke-WebRequest -UseBasicParsing -TimeoutSec 900 -Uri $urlAneel -OutFile $bruto } 'baixar o CSV da ANEEL' | Out-Null
    $corte = (Get-Date).AddYears(-$AnosHistorico).ToString('yyyy-MM-dd')
    $arqAneel = Join-Path $pastaDados 'aneel_a4verde.csv'
    $sr = New-Object IO.StreamReader($bruto, [Text.Encoding]::UTF8)
    $sw = New-Object IO.StreamWriter($arqAneel, $false, $utf8)
    $sw.NewLine = "`n"
    $sw.WriteLine($sr.ReadLine())
    $n = 0
    while ($null -ne ($l = $sr.ReadLine())) {
        if ($l.IndexOf('"A4";"Verde"') -lt 0 -or $l.IndexOf('"Tarifa de Aplica') -lt 0) { continue }
        $c = $l.Substring(1, $l.Length - 2) -split '";"'
        if ($c.Count -ge 6 -and $c[5] -and $c[5] -lt $corte) { continue }   # vigência terminou há mais de $AnosHistorico anos
        $sw.WriteLine($l); $n++
    }
    $sr.Close(); $sw.Close()
    Remove-Item -LiteralPath $bruto -Force
    if ($n -lt 1000) { throw "Só $n linhas A4 verde no CSV da ANEEL. O formato do arquivo pode ter mudado; nada foi enviado." }
    Registrar "ANEEL: $n linhas A4 verde."

    # ---------- 2. IPCA ----------
    $arqIpca = Join-Path $pastaDados 'ipca.json'
    Tentar { Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 -Uri $urlIpca -OutFile $arqIpca } 'baixar o IPCA do IBGE' | Out-Null
    $jIpca = [IO.File]::ReadAllText($arqIpca, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $meses = ($jIpca | Measure-Object).Count - 1
    if ($meses -lt 60) { throw "IPCA com só $meses meses; nada foi enviado." }
    Registrar "IPCA: $meses meses."

    $arqColeta = Join-Path $pastaDados 'coleta.txt'
    [IO.File]::WriteAllText($arqColeta, (Get-Date).ToString('yyyy-MM-dd HH:mm'), $utf8)

    if ($SemEnviar) { Registrar "Teste: arquivos em $pastaDados (nada enviado)."; return }

    # ---------- 3. Envio ao GitHub (um commit) ----------
    $arqChave = Join-Path $aqui 'chave.txt'
    if (-not (Test-Path -LiteralPath $arqChave)) { throw 'Chave do GitHub não encontrada (rode guardar_chave.ps1).' }
    $seg = Get-Content -LiteralPath $arqChave | ConvertTo-SecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seg)
    try { $tok = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $cab = @{ Authorization = "Bearer $tok"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    $api = "https://api.github.com/repos/$Repo"
    function Api([string]$metodo, [string]$caminho, $corpo) {
        $p = @{ Method = $metodo; Uri = "$api/$caminho"; Headers = $cab; UseBasicParsing = $true; TimeoutSec = 120 }
        if ($null -ne $corpo) { $p.Body = [Text.Encoding]::UTF8.GetBytes(($corpo | ConvertTo-Json -Depth 6 -Compress)); $p.ContentType = 'application/json; charset=utf-8' }
        Invoke-RestMethod @p
    }
    $arquivos = [ordered]@{ 'dados/aneel_a4verde.csv' = $arqAneel; 'dados/ipca.json' = $arqIpca; 'dados/coleta.txt' = $arqColeta }
    foreach ($k in $Extras.Keys) { $arquivos[$k] = $Extras[$k] }
    $pai = (Api GET 'git/ref/heads/main' $null).object.sha
    $arvoreBase = (Api GET "git/commits/$pai" $null).tree.sha
    $itens = @()
    foreach ($k in $arquivos.Keys) {
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($arquivos[$k]))
        $blob = Api POST 'git/blobs' @{ content = $b64; encoding = 'base64' }
        $itens += @{ path = $k; mode = '100644'; type = 'blob'; sha = $blob.sha }
    }
    $arvore = Api POST 'git/trees' @{ base_tree = $arvoreBase; tree = $itens }
    $commit = Api POST 'git/commits' @{ message = ('Dados ANEEL e IPCA de {0:dd/MM/yyyy}' -f (Get-Date)); tree = $arvore.sha; parents = @($pai) }
    Api PATCH 'git/refs/heads/main' @{ sha = $commit.sha } | Out-Null
    Registrar "Enviado ao GitHub (commit $($commit.sha.Substring(0, 7))). A página é republicada em poucos minutos."
}
catch {
    Registrar "ERRO: $($_.Exception.Message)"
    exit 1
}
