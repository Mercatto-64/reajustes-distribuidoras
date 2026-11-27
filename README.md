# Reajustes das distribuidoras

Página pública com os reajustes da TUSD e da TE (A4 verde) de todas as distribuidoras nos últimos 5 anos, comparados ao IPCA. Os dados vêm direto da ANEEL e do IBGE. A página não tem nenhum dado de cliente.

A página se atualiza sozinha **toda segunda às 7h** (Brasília) pelo GitHub Actions. Não depende de nenhum computador ligado.

## O que tem aqui

| Arquivo | Para que serve |
|---|---|
| `gerar.ps1` | Baixa o CSV da ANEEL e o IPCA, aplica as regras do Power BI e monta a página |
| `modelo.html` | O visual da página (gráficos, PDF, PowerPoint) |
| `distribuidoras.csv` | Nome mais conhecido, UF e "principal" de cada distribuidora, pelo CNPJ |
| `assets/` | Logos e imagens da Mercatto usados na página e nas exportações |
| `.github/workflows/atualizar.yml` | A rotina semanal que gera e publica |

## Como corrigir um nome ou uma UF

Abra o `distribuidoras.csv` aqui no GitHub, clique no lápis (Edit) e altere a linha:

- **nome** em branco: a página usa a sigla da ANEEL (`sigla_aneel`).
- **uf**: controla o filtro de região.
- **principal**: `sim` coloca a distribuidora no grupo "Principais" da lista.

Depois clique em **Commit changes**. A página é republicada em 1 a 2 minutos.

Se a ANEEL incluir uma distribuidora nova, ela entra sozinha com a sigla da ANEEL e a UF consultada pelo CNPJ. O resumo da execução, na aba Actions, mostra quais são novas para você ajustar o nome se quiser.

## Para atualizar na hora

Aba **Actions** → **Atualizar página** → **Run workflow**.

## Se der erro

Se a ANEEL ou o IBGE estiverem fora do ar, ou se os dados vierem estranhos (menos de 90 distribuidoras, RGE/Celesc/CEEE faltando, IPCA incompleto), a página **não** é republicada. A versão anterior continua no ar e o GitHub manda um e-mail avisando. Basta rodar de novo depois.

## Gerar no computador (opcional)

```powershell
.\gerar.ps1                                  # baixa tudo e grava em .\_site
.\gerar.ps1 -Csv C:\temp\tarifas.csv         # usa um CSV da ANEEL já baixado
```
