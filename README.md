# Reajustes das distribuidoras

Página pública com os reajustes da TUSD e da TE (A4 verde) de todas as distribuidoras nos últimos 5 anos, comparados ao IPCA. Os dados vêm direto da ANEEL e do IBGE. A página não tem nenhum dado de cliente.

## Como se atualiza

O site de dados abertos da ANEEL não responde a conexões de fora do Brasil, e os servidores do GitHub ficam fora. Por isso:

1. **Toda segunda às 7h**, a *ponte* (`ponte/ponte.ps1`, agendada no Windows de um computador no Brasil) baixa os dados públicos da ANEEL e do IBGE e envia para a pasta `dados/`. Ela não lê nenhuma pasta da empresa; só baixa dados públicos e envia ao GitHub com uma chave que só altera este repositório.
2. Assim que os dados chegam, o GitHub monta a página (`gerar.ps1`) e publica.
3. **Toda terça**, o GitHub confere se chegaram dados novos. Se a ponte não enviou, a conferência falha e o GitHub manda um e-mail. A página antiga continua no ar.

## O que tem aqui

| Arquivo | Para que serve |
|---|---|
| `dados/` | Dados da semana enviados pela ponte: tarifas A4 verde da ANEEL, IPCA e data da coleta |
| `gerar.ps1` | Aplica as regras do Power BI aos dados e monta a página |
| `modelo.html` | O visual da página (gráficos, PDF, PowerPoint) |
| `distribuidoras.csv` | Nome mais conhecido, UF e "principal" de cada distribuidora, pelo CNPJ |
| `assets/` | Logos e imagens da Mercatto usados na página e nas exportações |
| `ponte/` | O script da ponte e o que guarda a chave (cópia de referência; o que roda fica no computador da ponte) |
| `.github/workflows/atualizar.yml` | Monta e publica quando chegam dados; confere a ponte às terças |

## Como corrigir um nome ou uma UF

Abra o `distribuidoras.csv` aqui no GitHub, clique no lápis (Edit) e altere a linha:

- **nome** em branco: a página usa a sigla da ANEEL (`sigla_aneel`).
- **uf**: controla o filtro de região.
- **principal**: `sim` coloca a distribuidora no grupo "Principais" da lista.

Depois clique em **Commit changes**. A página é republicada em 1 a 2 minutos.

Se a ANEEL incluir uma distribuidora nova, ela entra sozinha com a sigla da ANEEL e a UF consultada pelo CNPJ. O resumo da execução, na aba Actions, mostra quais são novas para você ajustar o nome se quiser.

## Para atualizar na hora

- **Com dados novos:** no computador da ponte, rode `ponte.ps1` (ou, no Agendador de Tarefas do Windows, clique com o botão direito em *Reajustes - ponte ANEEL* → Executar).
- **Só remontar a página** (depois de mudar o visual ou um nome): aba **Actions** → **Atualizar página** → **Run workflow**. Salvar qualquer arquivo aqui também remonta.

## Se der erro

- A ponte grava tudo o que faz em `ponte.log`, na pasta dela. Se a ANEEL ou o IBGE estiverem fora do ar, ou os dados vierem estranhos, ela não envia nada.
- O gerador também não publica se o resultado sair estranho (menos de 90 distribuidoras, RGE/Celesc/CEEE faltando, IPCA incompleto). A versão anterior continua no ar e o GitHub manda um e-mail.
- A chave da ponte vence em **26/11/2027**. Para renovar: GitHub → Settings → Developer settings → Fine-grained tokens → *ponte-reajustes* → Regenerate, e rode `guardar_chave.ps1` de novo no computador da ponte.

## Gerar no computador (opcional)

```powershell
.\gerar.ps1                                  # baixa tudo e grava em .\_site
.\gerar.ps1 -Csv C:\temp\tarifas.csv         # usa um CSV da ANEEL já baixado
```
