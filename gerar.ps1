<#
  Gera a página "Reajustes das distribuidoras" (A4 verde, últimos 5 anos x IPCA).

  Fontes (públicas, baixadas a cada execução):
    - ANEEL, Tarifas homologadas das distribuidoras (CSV de dados abertos);
    - IBGE/SIDRA, tabela 1737, variável 2266 (IPCA, número-índice).

  Regras (as mesmas do Power BI "Tarifas Mercatto"):
    - só "Tarifa de Aplicação", subgrupo A4, modalidade Verde, sem classe/subclasse/detalhe/acessante;
    - componentes: energia ponta (MWh), energia fora ponta (MWh) e demanda (kW);
    - tarifa vigente numa data = entre os períodos que valem na data, o de início mais recente;
    - distribuidora cuja última tarifa venceu há mais de 90 dias fica de fora.

  Cada distribuidora é identificada pelo CNPJ. O nome vem da ANEEL; distribuidoras.csv só corrige
  o nome quando a sigla da ANEEL não é a mais conhecida, e informa UF e se é uma das principais.
  Distribuidora nova que não estiver no distribuidoras.csv entra com a sigla da ANEEL e a UF
  consultada pelo CNPJ (BrasilAPI).

  De onde vêm os dados:
    - se existir a pasta dados/ (enviada toda semana pela ponte, ver ponte/ponte.ps1), usa os arquivos
      dela: aneel_a4verde.csv, ipca.json e coleta.txt. A data da coleta vira a data da página.
      É assim que roda no GitHub, porque o site da ANEEL não responde a conexões de fora do Brasil;
    - senão, baixa tudo direto (funciona num computador no Brasil).

  Uso:
    ./gerar.ps1                          # grava a página em ./_site
    ./gerar.ps1 -Csv C:\temp\tarifas.csv # usa um CSV da ANEEL já baixado
#>
param(
    [string]$Csv,
    [string]$Saida,
    [int]$Anos = 5,
    [datetime]$Hoje = (Get-Date).ToUniversalTime().AddHours(-3).Date   # data de Brasília
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$aqui = $PSScriptRoot
$pastaDados = Join-Path $aqui 'dados'
$arqIpca = $null
$coleta = $null
if (-not $Csv -and (Test-Path -LiteralPath (Join-Path $pastaDados 'aneel_a4verde.csv'))) {
    $Csv = Join-Path $pastaDados 'aneel_a4verde.csv'
    $arqIpca = Join-Path $pastaDados 'ipca.json'
    $coleta = [datetime]::ParseExact((Get-Content -LiteralPath (Join-Path $pastaDados 'coleta.txt') -Raw).Trim(), 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    if (-not $PSBoundParameters.ContainsKey('Hoje')) { $Hoje = $coleta.Date }
    Write-Host "Usando os dados enviados pela ponte em $($coleta.ToString('dd/MM/yyyy HH:mm'))."
}
if (-not $Saida) { $Saida = Join-Path $aqui '_site' }
New-Item -ItemType Directory -Force $Saida | Out-Null
$inv = [Globalization.CultureInfo]::InvariantCulture
$utf8 = New-Object Text.UTF8Encoding($false)
$urlAneel = 'https://dadosabertos.aneel.gov.br/dataset/5a583f3e-1646-4f67-bf0f-69db4203e89e/resource/fcf2906c-7c32-4b9b-a637-054e7a5234f4/download/tarifas-homologadas-distribuidoras-energia-eletrica.csv'
$urlIpca = 'https://apisidra.ibge.gov.br/values/t/1737/n1/all/v/2266/p/last%20{0}?formato=json' -f ($Anos * 12 + 30)

function Tentar([scriptblock]$acao, [string]$oque) {
    for ($i = 1; $i -le 3; $i++) {
        try { return & $acao }
        catch {
            if ($i -eq 3) { throw "Falhou ao $oque depois de 3 tentativas: $($_.Exception.Message)" }
            Write-Host "Tentativa $i de $oque falhou ($($_.Exception.Message)); tentando de novo em 60 s..."
            Start-Sleep -Seconds 60
        }
    }
}

# ---------- Cadastro das distribuidoras ----------
$cad = @{}
foreach ($r in (Import-Csv -LiteralPath (Join-Path $aqui 'distribuidoras.csv') -Delimiter ';' -Encoding UTF8)) { $cad[$r.cnpj] = $r }
$regiaoDaUf = @{
    'AC'='Norte';'AM'='Norte';'AP'='Norte';'PA'='Norte';'RO'='Norte';'RR'='Norte';'TO'='Norte'
    'AL'='Nordeste';'BA'='Nordeste';'CE'='Nordeste';'MA'='Nordeste';'PB'='Nordeste';'PE'='Nordeste';'PI'='Nordeste';'RN'='Nordeste';'SE'='Nordeste'
    'DF'='Centro-Oeste';'GO'='Centro-Oeste';'MS'='Centro-Oeste';'MT'='Centro-Oeste'
    'ES'='Sudeste';'MG'='Sudeste';'RJ'='Sudeste';'SP'='Sudeste'
    'PR'='Sul';'RS'='Sul';'SC'='Sul'
}

# ---------- CSV da ANEEL ----------
if (-not $Csv) {
    $Csv = Join-Path ([IO.Path]::GetTempPath()) 'tarifas-aneel-reajustes.csv'
    Write-Host 'Baixando CSV da ANEEL...'
    Tentar { Invoke-WebRequest -UseBasicParsing -TimeoutSec 900 -Uri $urlAneel -OutFile $Csv } 'baixar o CSV da ANEEL' | Out-Null
}

function Num([string]$t) {
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    if ($t.Contains(',')) { $t = $t.Replace('.', '').Replace(',', '.') }
    $v = 0.0
    if ([double]::TryParse($t, [Globalization.NumberStyles]::Float, $inv, [ref]$v)) { return $v } else { return $null }
}
$cacheReh = @{}
function Curta([string]$t) {
    if ($cacheReh.ContainsKey($t)) { return $cacheReh[$t] }
    $u = $t.ToUpperInvariant()
    $tipo = if ($u.StartsWith('DESPACHO')) { 'Despacho' } else { 'REH' }
    $n = [regex]::Match($u, 'N[º°O]\s*([\d\.]+)').Groups[1].Value
    $anosReh = @([regex]::Matches($u, '\b(\d{4})\b') | ForEach-Object { $_.Groups[1].Value })
    $r = if ($n -and $anosReh.Count -gt 0) { "$tipo $n/$($anosReh[-1])" } else { $t }
    $cacheReh[$t] = $r
    $r
}

$inicioJanela = $Hoje.AddYears(-$Anos)
$corte = $inicioJanela.AddYears(-3)   # lê um pouco antes para achar a tarifa vigente no início da janela
$na = 'Não se aplica'
$linhas = New-Object System.Collections.Generic.List[object]
$geracao = $null
$sr = New-Object IO.StreamReader($Csv, [Text.Encoding]::UTF8)
[void]$sr.ReadLine()
while ($null -ne ($l = $sr.ReadLine())) {
    if ($l.IndexOf('"Tarifa de Aplicação"') -lt 0 -or $l.IndexOf('"A4";"Verde"') -lt 0) { continue }
    $c = $l.Substring(1, $l.Length - 2) -split '";"'
    if ($c.Count -lt 17) { continue }
    if ($c[6] -ne 'Tarifa de Aplicação' -or $c[7] -ne 'A4' -or $c[8] -ne 'Verde') { continue }
    if ($c[9] -ne $na -or $c[10] -ne $na -or $c[11] -ne $na) { continue }
    if ($c[14] -ne '' -and $c[14] -ne $na) { continue }
    $comp = if ($c[12] -eq 'Ponta' -and $c[13] -eq 'MWh') { 'p' } elseif ($c[12] -eq 'Fora ponta' -and $c[13] -eq 'MWh') { 'fp' } elseif ($c[12] -eq $na -and $c[13] -eq 'kW') { 'd' } else { $null }
    if (-not $comp) { continue }
    $ini = [datetime]::ParseExact($c[4].Substring(0, 10), 'yyyy-MM-dd', $inv)
    $fim = if ($c[5]) { [datetime]::ParseExact($c[5].Substring(0, 10), 'yyyy-MM-dd', $inv) } else { [datetime]::MaxValue }
    if ($fim -lt $corte -or $ini -gt $Hoje) { continue }
    if (-not $geracao) { $geracao = $c[0] }
    $chave = if ($c[3]) { $c[3] } else { 'sem-cnpj:' + $c[2] }
    $linhas.Add([pscustomobject]@{ Chave = $chave; Agente = $c[2]; Reh = (Curta $c[1]); Ini = $ini; Fim = $fim; Comp = $comp; TUSD = (Num $c[15]); TE = (Num $c[16]) })
}
$sr.Close()
Write-Host ("Linhas A4 verde lidas: {0:N0}" -f $linhas.Count)
if ($linhas.Count -lt 1000) { throw "Poucas linhas A4 verde no CSV da ANEEL ($($linhas.Count)). O formato do arquivo pode ter mudado." }

# ---------- Tarifa vigente numa data ----------
function Vigente($rows, [datetime]$data) {
    $valem = @($rows | Where-Object { $_.Ini -le $data -and $_.Fim -ge $data })
    if ($valem.Count -eq 0) { return $null }
    $ini = ($valem | Measure-Object -Property Ini -Maximum).Maximum
    $sel = @($valem | Where-Object { $_.Ini -eq $ini })
    $r = [ordered]@{ ini = $ini; reh = ($sel | Select-Object -First 1).Reh }
    foreach ($k in 'd', 'p', 'fp') {
        $x = @($sel | Where-Object { $_.Comp -eq $k })
        if ($x.Count -eq 0) { return $null }
        $r["${k}_tusd"] = [math]::Round((($x | Where-Object { $null -ne $_.TUSD } | Measure-Object TUSD -Average).Average), 4)
        $r["${k}_te"]   = [math]::Round((($x | Where-Object { $null -ne $_.TE }   | Measure-Object TE -Average).Average), 4)
    }
    [pscustomobject]$r
}

function UfPeloCnpj([string]$cnpj) {
    try { (Invoke-RestMethod -TimeoutSec 30 -Uri "https://brasilapi.com.br/api/cnpj/v1/$cnpj").uf } catch { $null }
}

$saidaDist = @()
$novas = @()
foreach ($g in ($linhas | Group-Object Chave)) {
    $rows = $g.Group
    # A última tarifa publicada precisa estar valendo ou ter vencido há no máximo 90 dias
    $ultIni = ($rows | Measure-Object Ini -Maximum).Maximum
    $ultFim = ($rows | Where-Object { $_.Ini -eq $ultIni } | Measure-Object Fim -Maximum).Maximum
    if ($ultFim -lt $Hoje.AddDays(-90)) { continue }
    $datas = @($inicioJanela) + @($rows | Where-Object { $_.Ini -gt $inicioJanela -and $_.Ini -le $Hoje } | ForEach-Object { $_.Ini }) | Sort-Object -Unique
    $passos = @()
    $ultimo = $null
    foreach ($dt in $datas) {
        $v = Vigente $rows $dt
        if (-not $v) { continue }
        $assin = "$($v.d_tusd)|$($v.d_te)|$($v.p_tusd)|$($v.p_te)|$($v.fp_tusd)|$($v.fp_te)"
        if ($assin -eq $ultimo) { continue }
        $ultimo = $assin
        $passos += [ordered]@{ d = $dt.ToString('yyyy-MM-dd'); vig = $v.ini.ToString('yyyy-MM-dd'); reh = $v.reh
            v = @($v.d_tusd, $v.d_te, $v.p_tusd, $v.p_te, $v.fp_tusd, $v.fp_te) }
    }
    if ($passos.Count -eq 0) { continue }
    $cnpj = if ($g.Name.StartsWith('sem-cnpj:')) { '' } else { $g.Name }
    $sigla = ($rows | Sort-Object Ini -Descending | Select-Object -First 1).Agente
    $info = $cad[$cnpj]
    if ($info) {
        $nome = if ($info.nome) { $info.nome } else { $sigla }
        $uf = $info.uf
        $principal = ($info.principal -eq 'sim')
    } else {
        $nome = $sigla
        $uf = if ($cnpj) { UfPeloCnpj $cnpj } else { $null }
        $principal = $false
        $novas += "$sigla (CNPJ $cnpj, UF $uf)"
    }
    $saidaDist += [ordered]@{
        nome = $nome
        agentes = @($rows | ForEach-Object { $_.Agente } | Sort-Object -Unique)
        cnpj = $cnpj
        grupo = if ($principal) { 'Principais' } else { 'Demais' }
        uf = $uf
        regiao = if ($uf -and $regiaoDaUf.ContainsKey($uf.Split('/')[0])) { $regiaoDaUf[$uf.Split('/')[0]] } else { 'Sem região' }
        completa = ($passos[0].d -eq $inicioJanela.ToString('yyyy-MM-dd'))
        passos = $passos
    }
}
Write-Host ("Distribuidoras na página: {0}" -f $saidaDist.Count)

# ---------- IPCA ----------
$ipca = if ($arqIpca) { [IO.File]::ReadAllText($arqIpca, [Text.Encoding]::UTF8) | ConvertFrom-Json }
        else { Tentar { Invoke-RestMethod -TimeoutSec 120 -Uri $urlIpca } 'baixar o IPCA do IBGE' }
$serie = @($ipca | Select-Object -Skip 1 | ForEach-Object { ,@(('{0}-{1}' -f $_.D3C.Substring(0, 4), $_.D3C.Substring(4, 2)), [math]::Round([double]::Parse($_.V, $inv), 2)) })

# ---------- Conferências antes de publicar ----------
$erros = @()
if ($saidaDist.Count -lt 90 -or $saidaDist.Count -gt 120) { $erros += "Número de distribuidoras fora do esperado: $($saidaDist.Count) (esperado de 90 a 120)." }
foreach ($ref in @(@('02016440000162', 'RGE'), @('08336783000190', 'Celesc-DIS'), @('08467115000100', 'Equatorial CEEE'))) {
    if (-not ($saidaDist | Where-Object { $_.cnpj -eq $ref[0] })) { $erros += "$($ref[1]) não apareceu nos dados." }
}
if ($serie.Count -lt $Anos * 12) { $erros += "IPCA incompleto: $($serie.Count) meses." }
if ($erros.Count) { throw ("Página NÃO publicada:`n - " + ($erros -join "`n - ")) }

$agora = if ($coleta) { $coleta } else { (Get-Date).ToUniversalTime().AddHours(-3) }
$dados = [ordered]@{
    gerado = $agora.ToString('yyyy-MM-dd HH:mm')
    baseAneel = $geracao
    inicio = $inicioJanela.ToString('yyyy-MM-dd')
    fim = $Hoje.ToString('yyyy-MM-dd')
    anos = $Anos
    componentes = @('Demanda TUSD (R$/kW)', 'Demanda TE', 'Ponta TUSD (R$/MWh)', 'Ponta TE (R$/MWh)', 'Fora ponta TUSD (R$/MWh)', 'Fora ponta TE (R$/MWh)')
    ipca = $serie
    distribuidoras = @($saidaDist | Sort-Object { $_.nome })
}
$json = $dados | ConvertTo-Json -Depth 8 -Compress
[IO.File]::WriteAllText((Join-Path $Saida 'dados.json'), $json, $utf8)

# Página: o modelo com os dados embutidos, mais as imagens
$pagina = [IO.File]::ReadAllText((Join-Path $aqui 'modelo.html'), [Text.Encoding]::UTF8)
if (-not $pagina.Contains('__DADOS__')) { throw 'modelo.html sem o marcador __DADOS__.' }
$pagina = $pagina.Replace('__DADOS__', $json.Replace('<', '\u003c'))
[IO.File]::WriteAllText((Join-Path $Saida 'index.html'), $pagina, $utf8)
Copy-Item -Recurse -Force (Join-Path $aqui 'assets') $Saida
Write-Host "Página gravada em $Saida"

# Resumo (aparece na tela da execução no GitHub)
$resumo = @("### Página atualizada", '', "- Distribuidoras: $($saidaDist.Count)", "- Base ANEEL de: $geracao",
    "- IPCA até: $($serie[-1][0])", "- Janela: $($inicioJanela.ToString('dd/MM/yyyy')) a $($Hoje.ToString('dd/MM/yyyy'))")
if ($coleta) { $resumo += "- Dados coletados pela ponte em: $($coleta.ToString('dd/MM/yyyy HH:mm'))" }
if ($novas.Count) {
    $resumo += '', '**Distribuidoras novas (não estão no distribuidoras.csv; entraram com a sigla da ANEEL):**'
    $resumo += $novas | ForEach-Object { "- $_" }
}
$resumo | ForEach-Object { Write-Host $_ }
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($resumo -join "`n") -Encoding utf8 }
