# SettleFlow Learning Journal

Este journal documenta a história do repositório até o commit `de31647`, que era o `HEAD` imediatamente anterior a esta edição. Esta atualização amplia o valor pedagógico do texto e também avança a cronologia para cobrir o fechamento residual do audit e a última leva de refinamentos documentais.

## Como este journal usa evidências

- Base primária:
  `git log`, `git show --stat`, arquivos atuais do projeto, ADRs, testes e o journal de remediação em `docs/architecture/public-release-remediation-journal.md`.

- Quando este texto diz "foi feito para X":
  a afirmação só aparece quando o conjunto `mensagem do commit + arquivos tocados + testes/docs adicionados` sustenta essa leitura.

- Quando o git não prova ordem interna dentro de um commit:
  o journal diz isso explicitamente, em vez de fingir um ciclo exato.

- Quando uma afirmação depende de leitura do código atual:
  o journal aponta arquivos concretos, por exemplo `app/services/ledger/journal_poster.rb`, `lib/database/consistency_verifier.rb` ou `lib/database/consistency_checks/*`.

- Escopo:
  commits já gravados até `de31647`. Esta edição ainda não cria um novo fato histórico; ela melhora a clareza do journal sobre o histórico já existente. Se outro commit for criado depois desta edição, o journal precisa ser avançado junto.

## O que o histórico não prova

- O histórico não prova a ordem interna exata de red, green e refactor dentro de um commit atômico.
  Quando isso não aparece separado em commits diferentes ou em testes adicionados antes/depois, o journal assume só o que o diff permite afirmar.

- O histórico não prova quais alternativas foram de fato debatidas em conversa privada.
  Só ADRs, mensagens de commit ou docs explícitas sustentam "alternativa rejeitada historicamente".
  Fora disso, este texto trata alternativas como plausíveis ou como inferência comparativa.

- O histórico não prova incidentes reais de produção.
  Concorrência, replay, privacidade e operabilidade aparecem aqui como riscos modelados e como lacunas fechadas pelo código, não como postmortem de ambiente real.

- O histórico não prova que a árvore de trabalho atual seja o mesmo estado analisado.
  Nesta passagem existiam mudanças não commitadas fora do journal; elas foram excluídas das afirmações históricas.

- O histórico não prova intenção psicológica individual.
  O máximo confiável é a combinação `commit + diff + testes + docs/ADR`.

## 1. Objetivo do projeto

O objetivo do projeto, pelo que `README.md`, `app/services/ledger/journal_poster.rb`, `app/services/outbox_events/emit.rb` e `db/structure.sql` deixam explícito, é ensinar em um repositório Rails pequeno o bastante para ser estudado de ponta a ponta como modelar um core financeiro sem esconder as partes difíceis atrás de um CRUD de carteira. O fluxo central é: dinheiro entra por comandos idempotentes, vira lançamento contábil imutável, atualiza projeções derivadas e publica evidência assíncrona sem perder rastreabilidade.

Em outras palavras: o material do repositório aponta para uma combinação de contabilidade de dupla entrada, isolamento por tenant, outbox transacional, governança operacional e verificações de banco em um único monólito Rails. README e ADRs não apresentam isso como arquitetura definitiva; apresentam como uma primeira versão deliberadamente simples, explícita e auditável para esse tipo de problema.

Ao terminar este journal, o leitor deve ser capaz de:

- explicar por que o ledger é a verdade e `BalanceProjection` é só leitura derivada;
- seguir um comando financeiro real do HTTP até `JournalEntry` e `OutboxEvent`;
- apontar quais invariantes vivem no Ruby e quais foram empurrados para o banco;
- dizer quais testes provam concorrência, replay, redaction e contrato público;
- descrever o que este repositório ensina bem e o que ele deliberadamente ainda não prova.

## 2. Como ler o repositório primeiro, em ordem de aprendizado

1. Comece pelo `README.md`.
   Ele define o contrato mental: ledger é a verdade, `BalanceProjection` é leitura derivada, `/v1` é API de máquina e `/ops` é superfície operacional humana.

2. Leia `config/routes.rb`.
   O arquivo expõe os dois eixos do produto: integrações externas em `v1/*` e operação humana em `ops/*`.

3. Leia o boundary HTTP antes do domínio:
   `app/controllers/api_controller.rb`
   `app/controllers/v1/base_controller.rb`
   Aqui ficam autenticação, correlação, envelope de erro e idempotência.

4. Leia a convenção mínima de service antes de abrir dezenas de comandos:
   `app/services/application_service.rb`
   Depois disso, os `*.call` dos services ficam mais fáceis de ler como boundary uniforme e não como macro escondida.

5. Siga um fluxo simples de criação de dinheiro:
   `app/controllers/v1/fundings_controller.rb`
   `app/services/fundings/create.rb`
   `app/services/ledger/journal_poster.rb`
   `app/services/outbox_events/emit.rb`
   Esse caminho deixa visível o padrão arquitetural que quase todo comando financeiro repete.

6. Leia os modelos que carregam invariantes, não todos de uma vez:
   `app/models/wallet.rb`
   `app/models/journal_entry.rb`
   `app/models/ledger_line.rb`
   `app/models/outbox_event.rb`
   `app/models/idempotency_key.rb`
   `app/models/operator_approval.rb`

7. Só depois leia as extensões de domínio:
   `app/services/pix_payments/create.rb`
   `app/services/pix_payments/settle.rb`
   `app/services/payouts/create.rb`
   `app/services/refunds/create.rb`
   `app/services/med_cases/accept.rb`

8. Antes de sair abrindo todos os commands multi-wallet, leia o boundary de lock:
   `app/services/wallets/projection_locker.rb`
   Ele existe porque transfer e split passaram a tratar ordem de lock como decisão explícita, não implícita.

9. Entenda a superfície operacional:
   `app/controllers/ops/*`
   `app/views/ops/*`
   `app/policies/ops/capability_policy.rb`
   Aqui aparece a decisão de manter o backoffice no mesmo monólito.

10. Só então desça para o banco:
   `db/migrate/20260529102000_create_financial_core.rb`
   `db/migrate/20260602090000_add_financial_core_database_guards.rb`
   `db/migrate/20260602204500_add_financial_journal_evidence_guards.rb`
   `db/structure.sql`
   A segunda metade da história do projeto está nos constraints e triggers, não só no Ruby.

11. Feche com os verificadores e a documentação arquitetural:
   `lib/database/consistency_verifier.rb`
   `lib/database/consistency_checks/*`
   `lib/tasks/database_engineering.rake`
   `docs/adr/*.md`
   `docs/database/*.md`

12. Use os testes como mapa de confiança:
   `test/requests/idempotency_test.rb`
   `test/services/ledger_journal_poster_test.rb`
   `test/jobs/outbox_publish_job_test.rb`
   `test/services/financial_concurrency_test.rb`
   `test/models/database_financial_invariants_test.rb`
   `test/services/database_consistency_verifier_test.rb`

### O que ignorar na primeira passada

- Não comece por `db/structure.sql`.
  Leia primeiro os services e os testes que dão nome aos invariantes; volte ao SQL só depois que os conceitos já estiverem claros.

- Não trate `lib/database/*` como domínio principal logo de início.
  Esse diretório é importante, mas ele ensina readiness e enforcement operacional, não o fluxo base do dinheiro.

- Não tente estudar todos os fluxos financeiros em paralelo na primeira leitura.
  Funding e transfer bastam para entender o esqueleto antes de entrar em Pix, payout, refund, split e MED.

- Não use o system test como mapa completo da governança.
  A UI existe para provar a superfície humana; a maior parte das decisões críticas ficou melhor localizada em request e service tests.

## 3. História cronológica da implementação

### Fase 1: fundação e API financeira inicial (`79b48ec` a `e19d834`, 2026-05-29)

- O repositório começou criando base documental e o esqueleto Rails (`README.md`, `docs/engineering-baseline.md`, `config/application.rb`, `Gemfile`).
- Em seguida veio o primeiro corte de domínio financeiro em `app/services/fundings/create.rb`, `app/services/transfers/create.rb`, `app/services/pix_payments/create.rb`, `app/services/reconciliation/run.rb`, com `Ledger::JournalPoster` como coração da escrita.
- A primeira cobertura veio depois do core, não antes: `9035824` adicionou testes e mostrou que o começo do projeto foi mais "implementar e depois cercar" do que TDD estrito.
- Ainda no mesmo dia o projeto registrou as decisões essenciais em ADRs e em `openapi.yaml`.
- Base usada:
  commits `79b48ec`, `8dd8782`, `70a8841`, `9035824`, `e19d834`; `README.md`, `app/services/ledger/journal_poster.rb`, `config/routes.rb`, `openapi.yaml`, testes centrais de request/service/job adicionados em `9035824`.

### Fase 2: o monólito deixa de ser só API (`05c2bcb`, 2026-05-30)

- O commit `05c2bcb` foi uma das maiores viradas conceituais do histórico.
- Ele introduziu autenticação humana (`app/models/user.rb`, `app/models/session.rb`, `app/controllers/sessions_controller.rb`), controllers `ops/*`, views `ops/*`, system tests e os ADRs que justificam o monólito híbrido.
- O repositório deixou de ser "API com alguns modelos" e passou a demonstrar operação financeira real.
- Base usada:
  commit `05c2bcb`, `config/routes.rb`, `app/controllers/ops/*`, `app/views/ops/*`, `app/models/user.rb`, `app/models/session.rb`, `docs/adr/0004-hybrid-hotwire-monolith.md`, `test/system/ops_console_test.rb`.

### Fase 3: estabilização e hardening inicial (`56ec94c` a `34be4c7`, 2026-05-31)

- Seis commits seguidos mexeram em `test/system/ops_console_test.rb`.
- Esse trecho sugere um padrão importante: colocar UI operacional num monólito é barato para começar, mas cobra disciplina de testes de navegação.
- Na mesma data entraram correções de concorrência e integridade: revalidação de Pix sob lock (`593ebd2`), claim do outbox antes de publicar (`9b17f12`) e append-only do ledger (`d692a31`).
- Base usada:
  commits `56ec94c` a `34be4c7`; `test/system/ops_console_test.rb`, `app/services/pix_payments/settle.rb`, `app/services/pix_payments/reverse.rb`, `app/jobs/outbox_publish_job.rb`, `app/services/outbox/publisher.rb`, `app/models/journal_entry.rb`.

### Fase 4: governança, extensões financeiras e trilha de auditoria (`205da77` a `8764018`, 2026-06-01)

- O banco começou a ganhar guards explícitos.
- Entraram maker-checker, hash chain de auditoria, payout, refund, split e MED.
- O domínio deixou de ser só "movimentar dinheiro" e passou a incluir quem pode aprovar, reverter e auditar.
- Base usada:
  commits `205da77` a `8764018`; `app/services/ops/maker_checker.rb`, `app/models/audit_log.rb`, `app/services/payouts/*`, `app/services/refunds/create.rb`, `app/services/split_payments/create.rb`, `app/services/med_cases/*`, `test/requests/financial_extensions_api_test.rb`, `test/services/refund_and_med_lifecycle_test.rb`.

### Fase 5: banco como contrato executável (`132b5e8` a `d13051a`, 2026-06-02)

- Este é o trecho mais denso da história.
- O projeto adicionou snapshots, processed events, sync com ClickHouse, benchmarks, tarefas de engenharia de banco, backup/restore drill, partition planning e uma longa sequência de constraints/triggers.
- A concentração de migrations, verificadores e testes de invariantes sugere a virada desta fase: validação só em Ruby já não bastava para o que o projeto queria garantir.
- `test/models/database_financial_invariants_test.rb`, `test/services/database_consistency_verifier_test.rb` e `db/structure.sql` viraram tão importantes quanto os services.
- Base usada:
  commits `132b5e8` a `d13051a`; `db/structure.sql`, `app/services/balance_snapshots/capture.rb`, `app/services/analytics/click_house_sync.rb`, `lib/tasks/database_engineering.rake`, `lib/database/consistency_verifier.rb`, `test/models/database_financial_invariants_test.rb`, `test/services/database_consistency_verifier_test.rb`.

### Fase 6: consolidação de contratos (`577d2ad`, 2026-06-06)

- `app/services/financial_contracts.rb` centralizou nomes de evento, chaves de idempotência e listas de triggers esperados.
- Isso reduziu duplicação espalhada entre models, services, verificadores e testes.
- Base usada:
  commit `577d2ad`, `app/services/financial_contracts.rb`, usos em services financeiros, `lib/database/consistency_verifier.rb`, `test/services/financial_concurrency_test.rb`.

### Fase 7: revisão de release, remediações e ajuste de learnability (`df0b0ea` a `a8d1171`, 2026-06-11)

- `df0b0ea` abriu uma trilha explícita de remediação em `docs/architecture/public-release-remediation-spec.md` e `docs/architecture/public-release-remediation-journal.md`.
- `22cf3c1` corrigiu uma lacuna real: carteiras e clientes tinham estados (`active`, `blocked`, `closed`), mas vários fluxos ainda não respeitavam isso. O conserto entrou em `app/services/financial_lifecycle/status_guard.rb` e nos serviços que criam/movem dinheiro.
- `9397a1a` fechou o bypass de chaves legadas de organização fora de `development`/`test`, sem quebrar o seed local.
- `cffccbe` parou de registrar parâmetros sensíveis crus e centralizou o logging de request em `AuditLogs::RequestLogger`.
- `81a86c2` foi o ajuste de learnability desta revisão: `test/services/database_consistency_verifier_test.rb` foi reorganizado para localizar melhor qual garantia falha quando a consistência quebra.
- `178c4e4` adicionou um sweep recorrente para `OutboxEvent.publishable`, em vez de depender só de jobs disparados pontualmente.
- `e5afdab` alinhou `docs/events` ao envelope real publicado pelo outbox, removendo o contrato público imaginário.
- `2315d41` parou de expor `pending_cents` e `blocked_cents` como se o produto já sustentasse essas semânticas de forma completa.
- `b0fe05e` finalmente alinhou `openapi.yaml` ao runtime real para idempotência, `403` públicos e o comportamento proibido de MED fora do fluxo ops.
- `70eb0f3` introduziu redaction padrão de PII em serializers, responses idempotentes e telas ops.
- `515b79c` corrigiu o caminho de consistência em que rebuild e snapshot podiam usar leitura velha antes do lock.
- `539cf6a` corrigiu um bloqueante encontrado só na validação final: a camada de masking passou a usar `::Privacy::Redactor` explicitamente e o system test de ops foi alinhado ao comportamento mascarado.
- `a8d1171` fechou a superfície de leitura global do ops para admins e tornou `/ready` menos verboso em caso de falha.
- Base usada:
  commits `df0b0ea` a `a8d1171`; `docs/architecture/public-release-remediation-spec.md`, `app/services/financial_lifecycle/status_guard.rb`, `app/services/audit_logs/request_logger.rb`, `app/jobs/outbox_sweep_job.rb`, `openapi.yaml`, `app/services/privacy/redactor.rb`, `test/requests/privacy_redaction_test.rb`, `test/requests/operability_test.rb`.

### Fase 8: aperto de concorrência, superfície pública e limpeza estrutural (`23879e6` a `9df9e43`, 2026-06-11)

- Depois da primeira leva de remediações, o histórico continuou num segundo movimento mais fino: menos endpoints públicos, menos repetição estrutural e menos ambiguidade de boundary.
- `63618c2` e `0f83617` atacam dois custos do caminho quente de escrita: ordem determinística de lock em comandos multi-wallet e atualização de projeções em lote dentro do `Ledger::JournalPoster`.
- `97a34fd` reduz a superfície pública removendo `/v1/outbox_events`; a partir daí outbox vira evidência operacional, não contrato de cliente externo.
- `d2355a6` e `76d9c2a` limpam a forma do código sem trocar comportamento: tooling operacional de banco sai de `app/services` para `lib/database`, e o padrão `.call` deixa de ser repetido em dezenas de classes.
- `4584b85`, `8f72783`, `b4b14bf` e `d035016` são menos sobre feature e mais sobre honestidade documental: remover autoavaliação, alinhar docs de segurança, explicar reconciliação como snapshot operacional e ajustar regras de lint para a spec atual.
- `9df9e43` transforma o achado de branch coverage dos caminhos de dinheiro em gate executável: cria testes de falha para branches financeiros e adiciona `bin/critical_money_branch_coverage` ao CI.
- Base usada:
  commits `63618c2`, `0f83617`, `97a34fd`, `d2355a6`, `76d9c2a`, `4584b85`, `8f72783`, `b4b14bf`, `d035016`, `9df9e43`; `app/services/wallets/projection_locker.rb`, `app/services/ledger/journal_poster.rb`, `config/routes.rb`, `lib/database/*`, `redocly.yaml`, `bin/critical_money_branch_coverage`, `test/services/financial_branch_coverage_test.rb`.

### Fase 9: o journal vira artefato versionado de engenharia (`ef36175` a `325d4f2`, 2026-06-11)

- Depois que o core funcional e os gates principais ficaram fechados, o histórico continuou com uma sequência explicitamente documental.
- `ef36175` reapresenta o journal após a remediação; `2bc5f07` endurece a disciplina de evidência; `ad23cb2` aprofunda a cobertura de decisões; `c3eab77` quebra agrupamentos grandes em detalhe por commit ou família curta; `325d4f2` adiciona a seção sobre o que o histórico não prova, trata features inteiras como unidades e registra a revisão adversarial do próprio texto.
- Esta fase não cria feature de domínio nova, mas muda o valor pedagógico do repositório: o journal deixa de ser resumo narrativo e passa a operar como artefato técnico auditável contra `git log`.
- Base usada:
  commits `ef36175`, `2bc5f07`, `ad23cb2`, `c3eab77`, `325d4f2`; diffs sucessivos de `docs/learning-journal.md`, validação automática da timeline, releitura dos arquivos reais citados no journal e a seção 13 desta própria documentação.

### Fase 10: fechamento residual do audit e último aperto pedagógico (`9011170` a `de31647`, 2026-06-11)

- Depois da remediação principal e do endurecimento documental anterior, o histórico registra um fechamento mais fino: apagar duplicações que sobraram do audit, deixar decisões técnicas explícitas e avançar o próprio journal até o `HEAD` então vigente.
- `9011170` remove callbacks Rails redundantes de reconciliação e deixa o banco como fonte única da imutabilidade por evidência; `e837ffc` decompõe `Database::ConsistencyVerifier` em checks menores; `b44efa1`, `261b83c`, `e72a193`, `8a541fb` e `24ae406` limpam callable services, shape interno de split, guard de payout, predicados do outbox e tratamento repetido de erro em controllers ops.
- `14498bb` registra essas decisões no journal de remediação, e `de31647` volta ao learning journal para estender a cronologia e alinhar o texto com o estado real da branch.
- Esta fase não muda o produto visível; ela melhora legibilidade, ownership e valor de ensino do repositório, reduzindo exatamente os resíduos que um review estrutural ainda apontaria.
- Base usada:
  commits `9011170`, `e837ffc`, `b44efa1`, `261b83c`, `e72a193`, `8a541fb`, `24ae406`, `14498bb`, `de31647`; `app/models/reconciliation_run.rb`, `app/models/reconciliation_row.rb`, `lib/database/consistency_verifier.rb`, `lib/database/consistency_checks/*`, `app/services/application_service.rb`, `app/services/split_payments/create.rb`, `app/services/payouts/settle.rb`, `app/models/outbox_event.rb`, `app/controllers/ops/*`, `docs/architecture/public-release-remediation-journal.md`.

## Features importantes como unidades completas

### Pipeline financeiro core: comando idempotente, ledger, projeção e outbox

- Problema que resolve:
  criar dinheiro, mover saldo e liquidar eventos financeiros sem depender de saldo mutável opaco nem de publicação assíncrona desconectada do commit principal.
- Commits da feature:
  `70a8841`, `9035824`, `8a6117b`, `593ebd2`, `9b17f12`, `d692a31`, `63618c2`, `0f83617`.
- Arquivos principais:
  `app/controllers/v1/fundings_controller.rb`, `app/services/idempotency/runner.rb`, `app/services/fundings/create.rb`, `app/services/transfers/create.rb`, `app/services/pix_payments/settle.rb`, `app/services/ledger/journal_poster.rb`, `app/services/outbox/publisher.rb`, `app/jobs/outbox_publish_job.rb`, `app/services/wallets/projection_locker.rb`.
- Por que a solução final tomou essa forma:
  o histórico converge para um caminho síncrono e explícito no mesmo processo Rails: validar o comando, postar o ledger, atualizar projeção derivada e só então publicar evidência assíncrona por outbox.
  Isso combina com `docs/adr/0001-double-entry-ledger.md`, `docs/adr/0002-transactional-outbox-solid-queue.md` e `docs/adr/0006-ledger-and-outbox-before-event-sourcing.md`.
- Alternativa rejeitada historicamente:
  saldo mutável puro e event sourcing puro aparecem explicitamente como alternativas descartadas em `docs/adr/0006-ledger-and-outbox-before-event-sourcing.md`.
- Alternativa plausível:
  publicar direto em broker externo e recalcular projeções fora do caminho de escrita.
  O git não mostra essa rejeição como fato, mas a implementação atual prefere consistência local e replay simples a desacoplamento maior.
- Prós e contras da forma escolhida:
  a favor, o fluxo fica auditável ponta a ponta e o replay continua localizado no próprio banco.
  contra, o caminho de escrita fica mais pesado, depende de locks mais cuidadosos e carrega latência extra para manter coerência local.
- Testes que protegem a feature:
  `test/requests/idempotency_test.rb`, `test/services/funding_create_test.rb`, `test/services/transfer_create_test.rb`, `test/services/pix_payment_lifecycle_test.rb`, `test/services/ledger_journal_poster_test.rb`, `test/jobs/outbox_publish_job_test.rb`, `test/services/financial_concurrency_test.rb`.
- Limites em produção:
  ainda não há broker externo, backpressure distribuído nem isolamento de throughput entre domínio financeiro e publicação de eventos.

### Console ops e governança maker-checker no mesmo monólito

- Problema que resolve:
  mostrar que aprovação humana, reversão e observação operacional fazem parte do problema financeiro e não só da camada de suporte.
- Commits da feature:
  `05c2bcb`, `56ec94c`, `1bd1df9`, `b69e3ba`, `6a40b98`, `65a8e80`, `37e3180`, `3847dcb`, `a8d1171`.
- Arquivos principais:
  `app/controllers/ops/*`, `app/views/ops/*`, `app/models/user.rb`, `app/models/session.rb`, `app/policies/ops/capability_policy.rb`, `app/services/ops/maker_checker.rb`, `test/system/ops_console_test.rb`, `test/requests/ops_console_request_test.rb`.
- Por que a solução final tomou essa forma:
  o projeto preferiu manter UI humana e API sobre o mesmo domínio para reaproveitar modelo, transações e testes.
  Depois, o histórico corrige o excesso inicial de E2E e deixa o browser test mais estreito, com a governança principal protegida por request/service tests.
- Alternativa rejeitada historicamente:
  `docs/adr/0004-hybrid-hotwire-monolith.md` registra a escolha contra separar backoffice em outro app logo no primeiro corte.
- Alternativa plausível:
  usar IAM/policy engine externo e granularidade de permissão mais fina desde o início.
  O histórico atual não prova que isso foi debatido formalmente; a escolha observável foi coarse-grained por simplicidade.
- Prós e contras da forma escolhida:
  a favor, há um único modelo mental para operador e integração.
  contra, o monólito carrega responsabilidades de produto e backoffice no mesmo deploy, e os papéis `viewer/operator/admin` são amplos demais para produção madura.
- Testes que protegem a feature:
  `test/system/ops_console_test.rb`, `test/requests/ops_console_request_test.rb`, `test/controllers/sessions_controller_test.rb`, `test/controllers/passwords_controller_test.rb`.
- Limites em produção:
  não há MFA, SSO, escopo fino por tenant/time/região nem isolamento físico entre console e API pública.

### Extensões de negócio: payout, refund, split e MED como verbos próprios

- Problema que resolve:
  impedir que fluxos com lifecycle e governança diferentes virem apenas flags escondidas em transferência genérica.
- Commits da feature:
  `387e90a`, `48be481`, `929c4f9`, `b693532`, `0d4ca54`, `e51d574`.
- Arquivos principais:
  `app/services/payouts/*`, `app/services/refunds/create.rb`, `app/services/split_payments/create.rb`, `app/services/med_cases/*`, `app/models/payout.rb`, `app/models/refund.rb`, `app/models/split_payment.rb`, `app/models/med_case.rb`.
- Por que a solução final tomou essa forma:
  cada fluxo ganhou seus próprios estados, serializers, controllers e guards de banco.
  Isso reduz ambiguidade na leitura porque cada verbo financeiro expõe seus próprios pré-requisitos e evidências.
- Alternativa plausível:
  um modelo genérico de `financial_operation` ou reuso massivo de `Transfers::Create` com flags.
  O histórico não documenta rejeição formal disso, mas a implementação escolhida foi na direção oposta: objetos e contratos dedicados por fluxo.
- Prós e contras da forma escolhida:
  a favor, regras específicas de payout/MED/refund/split ficam mais localizadas.
  contra, o número de classes, endpoints e testes cresce rápido.
- Testes que protegem a feature:
  `test/requests/financial_extensions_api_test.rb`, `test/services/payout_lifecycle_test.rb`, `test/services/refund_and_med_lifecycle_test.rb`, `test/services/split_payment_create_test.rb`.
- Limites em produção:
  continua faltando uma camada mais madura de AML/fraud, limites operacionais por perfil e processos externos reais de clearing/dispute.

### Reconciliação explicável como snapshot operacional, não como fechamento contábil

- Problema que resolve:
  permitir que a operação entenda de onde vem uma divergência de saldo sem depender de leitura manual do ledger bruto.
- Commits da feature:
  `0eb1911`, `dde2aab`, `b4b14bf`.
- Arquivos principais:
  `app/services/reconciliation/run.rb`, `app/services/reconciliation/ledger_snapshot.rb`, `app/services/reconciliation/rows_builder.rb`, `app/services/wallets/balance_explainer.rb`, `app/models/reconciliation_run.rb`, `app/models/reconciliation_row.rb`, `docs/database/reconciliation-data-model.md`.
- Por que a solução final tomou essa forma:
  o projeto começou com reconciliação mais resumida e depois adicionou rows, explicadores e statement lines para transformar divergência em artefato investigável.
- Alternativa plausível:
  manter só um resumo agregado ou chamar isso de fechamento contábil periódico.
  O commit `b4b14bf` mostra precisamente a correção de linguagem: snapshot operacional e não fechamento.
- Prós e contras da forma escolhida:
  a favor, a operação ganha explicação e drill-down.
  contra, cresce o volume de leitura derivada e ainda não existe cutoff contábil forte por período.
- Testes que protegem a feature:
  `test/services/reconciliation_run_test.rb`, `test/models/reconciliation_row_test.rb`, `test/requests/financial_workflow_test.rb`.
- Limites em produção:
  não resolve fechamento formal de período, lançamentos tardios nem trilha de ajuste contábil entre competências.

### Banco como contrato executável para invariantes e readiness

- Problema que resolve:
  proteger o core financeiro contra bypass de Active Record, drift de evidência e documentação operacional que não falha quando a hipótese deixa de valer.
- Commits da feature:
  `205da77`, `3b10d5e`, `132b5e8`, `ea7b5f9`, `d20ac86`, `ca69cb9`, `60a0f97` até `775fef5`, `d13051a`.
- Arquivos principais:
  `db/migrate/*financial*`, `db/structure.sql`, `lib/database/consistency_verifier.rb`, `lib/database/consistency_checks/*`, `lib/tasks/database_engineering.rake`, `app/services/balance_snapshots/capture.rb`, `app/models/outbox_legacy_command_identity_exception.rb`.
- Por que a solução final tomou essa forma:
  Ruby continua orquestrando o domínio, mas Postgres e os verificadores em `lib/database/*` passaram a carregar a última linha de defesa e parte do readiness operacional.
- Alternativa rejeitada historicamente:
  `docs/adr/0001-double-entry-ledger.md` e `docs/adr/0006-ledger-and-outbox-before-event-sourcing.md` já empurravam a arquitetura para contratos fortes em volta do ledger, não para saldo mutável frouxo.
- Alternativa plausível:
  deixar tudo em validação Ruby ou mover toda a regra para stored procedures.
  O histórico não prova uma discussão formal entre essas duas pontas; o que existe é uma solução intermediária clara.
- Prós e contras da forma escolhida:
  a favor, invariantes críticas sobrevivem a `update_columns`, scripts e integrações externas.
  contra, o custo de ler migrations, triggers e testes de invariantes sobe muito e o onboarding fica mais duro.
- Testes que protegem a feature:
  `test/models/database_financial_invariants_test.rb`, `test/services/database_consistency_verifier_test.rb`, `test/services/database_migration_safety_checker_test.rb`, `test/services/database_partition_feasibility_test.rb`, `test/services/database_pitr_readiness_test.rb`, `test/services/audit_log_worm_readiness_test.rb`.
- Limites em produção:
  o projeto ainda é challenge repo; readiness checks, WORM e PITR continuam simulações/guias locais, não garantia operacional de uma plataforma 24x7.

### Contrato público honesto: autenticação, eventos, OpenAPI e redaction

- Problema que resolve:
  parar de expor superfícies, campos e documentos públicos mais permissivos do que o runtime realmente sustenta.
- Commits da feature:
  `9397a1a`, `cffccbe`, `178c4e4`, `e5afdab`, `2315d41`, `b0fe05e`, `70eb0f3`, `539cf6a`, `97a34fd`, `9df9e43`.
- Arquivos principais:
  `app/controllers/v1/base_controller.rb`, `app/services/audit_logs/request_logger.rb`, `app/services/audit_logs/parameter_sanitizer.rb`, `docs/events/outbox_event.v1.json`, `openapi.yaml`, `app/services/privacy/redactor.rb`, `app/views/ops/pix_payments/*`, `bin/critical_money_branch_coverage`.
- Por que a solução final tomou essa forma:
  a revisão de release mostrou que a maior fragilidade não era só regra de negócio; era também honestidade do boundary público.
  A sequência de commits corta compatibilidades perigosas, alinha contratos ao envelope real, remove campos não sustentados e mascara PII por padrão.
- Alternativa plausível:
  manter documentação aspiracional, endpoint público de outbox para debug e respostas cruas até existir ACL fina por campo.
  O histórico não sustenta essa opção como rejeitada formalmente, mas os commits recentes mostram a decisão contrária.
- Prós e contras da forma escolhida:
  a favor, o cliente externo passa a enxergar menos promessas falsas e menos PII.
  contra, algumas superfícies convenientes de debug somem e certas respostas ficam menos ricas do que poderiam ser num produto mais maduro.
- Testes que protegem a feature:
  `test/requests/api_authentication_test.rb`, `test/requests/api_audit_logging_test.rb`, `test/jobs/outbox_sweep_job_test.rb`, `test/services/outbox_event_contract_test.rb`, `test/services/openapi_contract_test.rb`, `test/requests/privacy_redaction_test.rb`, `test/services/financial_branch_coverage_test.rb`.
- Limites em produção:
  ainda falta ACL fina por campo, rotação mais sofisticada de credenciais e política de versionamento público de eventos além do envelope atual.

### O learning journal como artefato versionado de engenharia

- Problema que resolve:
  o histórico bruto em `git log` prova ordem e diffs, mas não ensina sozinho como reproduzir a arquitetura, nem diferencia com clareza fato histórico, inferência e lacuna de evidência.
- Commits da feature:
  `1794cfe`, `c5f6f0a`, `4dad992`, `23879e6`, `4f3c653`, `ef36175`, `2bc5f07`, `ad23cb2`, `c3eab77`, `325d4f2`, `de31647`.
- Arquivos principais:
  `docs/learning-journal.md`, `docs/architecture/public-release-remediation-spec.md`, `docs/architecture/public-release-remediation-journal.md`.
- Por que a solução final tomou essa forma:
  o primeiro corte do journal nasceu como documentação de apoio e, na sequência, recebeu endurecimento iterativo para virar material de aprendizado sério: timeline validada contra `git log`, decisões quebradas por evidência, features tratadas como unidades completas e revisão adversarial explícita.
- Alternativa plausível:
  deixar o aprendizado distribuído entre `README`, ADRs e `git log`, sem um journal consolidado.
  O histórico mostra que o repositório preferiu pagar o custo de manutenção do journal para aumentar auditabilidade e repetibilidade pedagógica.
- Prós e contras da forma escolhida:
  a favor, o repositório fica muito mais estudável e obriga a documentação a enfrentar os limites do próprio histórico.
  contra, nasce uma nova superfície sujeita a drift e a vários commits meta-documentais para permanecer honesta.
- Testes ou verificações que protegem a feature:
  não há uma suíte automatizada dedicada ao journal.
  A proteção aqui vem de validação automática da timeline contra `git log`, de `git diff --check -- docs/learning-journal.md` e das revisões estrutural, Rails e adversarial registradas na seção 13.
- Limites em produção:
  o journal continua dependendo de manutenção manual disciplinada; se futuros commits deixarem de atualizar esse arquivo com o mesmo rigor, a utilidade pedagógica volta a cair rapidamente.

## 4. Decisão por decisão: o que foi feito, por que foi feito e quais alternativas aparecem no histórico ou como inferência comparativa

- Legenda de leitura:
  quando ADR, doc ou mensagem de commit sustentam descarte explícito, a alternativa é tratada como histórica.
  quando isso não existe, a alternativa abaixo deve ser lida como plausível ou como inferência comparativa a partir da forma atual do código.
  os subtópicos antigos preservam a etiqueta curta `Alternativas rejeitadas:` por continuidade editorial, mas a qualificação histórica ou plausível depende sempre da base citada em cada bloco.

### Rails 8 monolítico com `/v1` e `/ops`

- O que foi feito:
  `05c2bcb` adicionou controllers `ops/*`, views ERB, Turbo/Stimulus e autenticação humana no mesmo app já usado pela API.
- Por que foi feito:
  A operação humana era parte do problema. Sem isso o projeto cobria integração, mas deixava de fora aprovação, revisão e governança explícita.
- Alternativas rejeitadas:
  Um frontend separado consumindo JSON.
  Um segundo app só para backoffice.
  Ambas foram deixadas de lado para não dividir o modelo mental nem o stack de testes.
- Base usada:
  commit `05c2bcb`, `config/routes.rb`, `app/controllers/ops/base_controller.rb`, `app/views/ops/*`, `docs/adr/0004-hybrid-hotwire-monolith.md`, `test/system/ops_console_test.rb`.

### Console ops prova a superfície humana por inspeção, não por E2E maximalista

- O que foi feito:
  os commits `56ec94c`, `1bd1df9`, `b69e3ba`, `6a40b98`, `65a8e80` e `37e3180` estabilizaram `test/system/ops_console_test.rb` e, ao final, reduziram seu escopo para inspeção do console em vez de tentar carregar toda a governança por browser.
- Por que foi feito:
  o histórico registra custo alto de flake em navegação, clique de detalhe e feedback assíncrono; manter ao menos uma prova de superfície humana continuava importante, mas colocar todas as transições críticas no system test estava caro demais.
- Alternativas rejeitadas:
  continuar empurrando aprovação/rejeição completas para o browser test.
  abandonar system tests por completo.
  A forma final deixa a UI coberta por inspeção e desloca a maior parte das decisões de estado para request/service tests.
- Base usada:
  commits `56ec94c`, `1bd1df9`, `b69e3ba`, `6a40b98`, `65a8e80`, `37e3180`; `test/system/ops_console_test.rb`, `test/requests/ops_console_request_test.rb`.

### Ledger de dupla entrada como verdade e projeções como leitura

- O que foi feito:
  `app/services/ledger/journal_poster.rb`, `app/models/journal_entry.rb`, `app/models/ledger_line.rb` e `app/models/balance_projection.rb` separam escrita contábil de leitura rápida.
- Por que foi feito:
  Saldo mutável sozinho não explica causa, compensação nem reconciliação.
- Alternativas rejeitadas:
  `wallet.balance` mutável.
  Event Sourcing puro.
  As ADRs `docs/adr/0001-double-entry-ledger.md` e `docs/adr/0006-ledger-and-outbox-before-event-sourcing.md` indicam a busca por um meio-termo mais simples.
- Base usada:
  `app/services/ledger/journal_poster.rb`, `app/models/journal_entry.rb`, `app/models/ledger_line.rb`, `app/models/balance_projection.rb`, ADRs `0001` e `0006`, `test/services/ledger_journal_poster_test.rb`.

### Outbox transacional antes de broker real

- O que foi feito:
  `app/models/outbox_event.rb`, `app/jobs/outbox_publish_job.rb` e `app/services/outbox/publisher.rb` tornam o evento derivado do commit de banco.
- Por que foi feito:
  O risco principal era publicar sem commit ou commitar sem publicar.
- Alternativas rejeitadas:
  Publicar direto no request.
  Introduzir RabbitMQ/Redpanda cedo demais.
  A decisão foi manter Postgres + job local enquanto o fanout ainda cabe no monólito.
- Base usada:
  `app/models/outbox_event.rb`, `app/jobs/outbox_publish_job.rb`, `app/jobs/outbox_sweep_job.rb`, `app/services/outbox/publisher.rb`, `test/jobs/outbox_publish_job_test.rb`, `test/jobs/outbox_sweep_job_test.rb`, ADR `0002`.

### API key + idempotência como boundary mínimo

- O que foi feito:
  `app/models/api_credential.rb`, `app/models/idempotency_key.rb`, `app/services/idempotency/runner.rb` e `app/controllers/api_controller.rb`.
- Por que foi feito:
  Requisições financeiras são naturalmente repetidas por retry de rede.
- Alternativas rejeitadas:
  JWT/OIDC logo no MVP.
  Tratar replay só em nível de controller ou client.
  A escolha foi um boundary de servidor simples e observável.
- Base usada:
  `app/controllers/api_controller.rb`, `app/controllers/v1/base_controller.rb`, `app/models/api_credential.rb`, `app/models/idempotency_key.rb`, `app/services/idempotency/runner.rb`, `test/requests/idempotency_test.rb`, ADR `0003`.

### Endurecer o boundary antes de expandir o domínio

- O que foi feito:
  `8a6117b`, `a9dbd6a`, `3fbc141` e `34be4c7` endureceram autenticação, idempotência, publisher HTTP, metadata do outbox, sessão humana, métricas/observabilidade e rate limiting local antes da próxima leva de features financeiras.
- Por que foi feito:
  o histórico registra um pequeno intervalo em que o projeto desacelera a expansão de domínio para reduzir frouxidão no boundary externo e no runtime local. `ApiCredential` entra no lugar do acoplamento maior a `Organization`, o publisher passa a devolver metadata mais estruturada e os testes de autenticação, idempotência e delivery ficam mais específicos.
- Alternativas rejeitadas:
  seguir adicionando fluxos de negócio antes de endurecer auth/outbox/runtime.
  tratar publisher, métricas e rate limiting como detalhes de infraestrutura sem contrato de teste.
  O repositório preferiu fechar essas bordas primeiro.
- Detalhe por commit:
  `8a6117b` concentra o primeiro aperto: cria `ApiCredential`, endurece `V1::BaseController`, reforça `Idempotency::Runner`, adiciona metadata de delivery ao outbox e faz `reconciliation_run_test.rb` acompanhar a mudança. O efeito observável é mover o boundary de autenticação e replay para objetos mais explícitos e mais testáveis.
  `a9dbd6a` não mexe em domínio financeiro; ele fecha o publisher HTTP e o runtime local. Os arquivos tocados mostram retry/erro mais controlado em `HttpPublisher` e rate limiting local testado em `rack_attack_test.rb`.
  `3fbc141` endurece segurança de sessão e superfície operacional: `Authentication`, `MetricsController`, `ApplicationJob`, `Session`, `User` e testes de controllers/operability mudam juntos. A leitura segura aqui é que a stack humana e observável estava sendo apertada antes de crescer novamente.
  `34be4c7` não cria regra nova de runtime; ele alinha README, ADRs e docs de segurança/deployment ao boundary endurecido que os três commits anteriores já tinham materializado.
- Base usada:
  commits `8a6117b`, `a9dbd6a`, `3fbc141`, `34be4c7`; `app/models/api_credential.rb`, `app/controllers/v1/base_controller.rb`, `app/controllers/concerns/authentication.rb`, `app/controllers/observability/metrics_controller.rb`, `app/services/outbox/publisher.rb`, `app/services/outbox/publishers/http_publisher.rb`, `config/initializers/rack_attack.rb`, `test/requests/api_authentication_test.rb`, `test/requests/idempotency_test.rb`, `test/jobs/outbox_publish_job_test.rb`, `test/services/outbox_http_publisher_test.rb`, `test/requests/operability_test.rb`.

### Governança operacional coarse-grained

- O que foi feito:
  `app/policies/ops/capability_policy.rb` define `viewer`, `operator` e `admin`, e `app/services/ops/maker_checker.rb` materializa dual control.
- Por que foi feito:
  O repositório quis registrar segregação de deveres sem criar um sistema inteiro de IAM.
- Alternativas rejeitadas:
  Policy engine externo.
  Permissões finíssimas já no primeiro corte.
  O projeto escolheu coarse roles como simplificação deliberada.
- Base usada:
  `app/policies/ops/capability_policy.rb`, `app/services/ops/maker_checker.rb`, `app/controllers/ops/pix_payments_controller.rb`, `test/requests/ops_console_request_test.rb`, ADR `0005`.

### Audit log encadeado

- O que foi feito:
  `app/models/audit_log.rb`, `app/models/audit_log_anchor.rb`, `app/services/audit_logs/hash_chain_anchor.rb`.
- Por que foi feito:
  O projeto queria deixar claro que observabilidade operacional e evidência de auditoria não são a mesma coisa.
- Alternativas rejeitadas:
  Log JSON comum como única trilha.
  WORM/export completo já no MVP.
  Pelo histórico, export/WORM entrou como gate posterior, não como requisito inicial do MVP.
- Base usada:
  `app/models/audit_log.rb`, `app/models/audit_log_anchor.rb`, `app/services/audit_logs/hash_chain_anchor.rb`, `test/services/audit_log_hash_chain_test.rb`, `test/services/audit_log_hash_chain_anchor_test.rb`.

### Domínio cresce por comandos explícitos, não por uma transação genérica

- O que foi feito:
  `387e90a` adicionou modelos, serializers, controllers e services dedicados para payout, refund, split payment e MED, em vez de encaixar tudo como variações implícitas de transferências já existentes.
- Por que foi feito:
  a própria forma do diff indica a escolha: cada fluxo ganhou lifecycle, payloads e testes próprios. Isso registra que payout, refund, split e MED foram tratados como fluxos diferentes o bastante para receber verbos e objetos explícitos.
- Alternativas rejeitadas:
  reaproveitar `Transfers::Create` com flags ou branches internas.
  introduzir um model genérico de "financial_operation" e esconder diferenças no payload.
  O git não traz um ADR formal descartando essas opções, mas a implementação materializada foi na direção oposta: classes e contratos dedicados por fluxo.
- Base usada:
  commit `387e90a`, `app/services/payouts/*`, `app/services/refunds/create.rb`, `app/services/split_payments/create.rb`, `app/services/med_cases/*`, `app/models/payout.rb`, `app/models/refund.rb`, `app/models/split_payment.rb`, `app/models/med_case.rb`, `test/requests/financial_extensions_api_test.rb`, `test/services/payout_lifecycle_test.rb`, `test/services/refund_and_med_lifecycle_test.rb`, `test/services/split_payment_create_test.rb`.

### Reconciliação precisa explicar saldo, não só acusar divergência

- O que foi feito:
  `0eb1911` adicionou `Reconciliation::LedgerSnapshot`, `Wallets::BalanceExplainer` e `Wallets::StatementBuilder`; `dde2aab` acrescentou `ReconciliationRow`, `Reconciliation::RowsBuilder`, serializers, endpoints e tela ops com granularidade itemizada.
- Por que foi feito:
  os commits mostram a reconciliação saindo de um estado mais agregado para um estado explicável. Em vez de só dizer que há divergência, a aplicação passa a carregar linhas e explicações que ligam o saldo derivado aos fatos do ledger.
- Alternativas rejeitadas:
  manter reconciliação apenas como resumo agregado.
  depender de consulta manual ao ledger sempre que fosse preciso explicar diferença.
- Base usada:
  commits `0eb1911`, `dde2aab`, `app/services/reconciliation/ledger_snapshot.rb`, `app/services/reconciliation/rows_builder.rb`, `app/services/wallets/balance_explainer.rb`, `app/models/reconciliation_row.rb`, `app/views/ops/reconciliation_runs/show.html.erb`, `docs/database/reconciliation-data-model.md`, `test/services/reconciliation_run_test.rb`, `test/models/reconciliation_row_test.rb`, `test/requests/financial_workflow_test.rb`.

### Banco como última linha de defesa

- O que foi feito:
  A sequência de migrations de `20260602170000` até `20260602224500` empurrou invariantes para constraints, triggers e funções SQL.
- Por que foi feito:
  Se o core financeiro depende só do caminho feliz dos services, um `update_columns`, `insert!` ou carga fora da app abre brechas demais.
- Alternativas rejeitadas:
  Ficar só em validação Active Record.
  Mover tudo para stored procedures de domínio.
  A solução intermediária foi deixar orquestração em Ruby e invariantes duráveis no banco.
- Base usada:
  sequência de migrations `20260602170000` a `20260602224500`, `db/structure.sql`, `test/models/database_financial_invariants_test.rb`, `lib/database/consistency_verifier.rb`.

### Snapshots e processed events são evidência auxiliar, não fonte de verdade

- O que foi feito:
  `132b5e8` criou `BalanceSnapshot`, `ProcessedEvent`, `BalanceProjections::Rebuilder` e `BalanceSnapshots::Capture` como tabelas e services derivados do ledger/outbox principal.
- Por que foi feito:
  o projeto precisava de checkpoints para rebuild, auditoria e sincronização downstream sem trocar a fonte de verdade principal. A presença simultânea de snapshot, processed events e testes de rebuild mostra uma preocupação com repetibilidade operacional, não com substituição do ledger.
- Alternativas rejeitadas:
  recalcular tudo do ledger toda vez, sem checkpoint algum.
  promover snapshot ou processed event a verdade financeira primária.
- Base usada:
  commit `132b5e8`, `app/models/balance_snapshot.rb`, `app/models/processed_event.rb`, `app/services/balance_projections/rebuilder.rb`, `app/services/balance_snapshots/capture.rb`, `db/structure.sql`, `test/services/balance_snapshot_and_rebuild_test.rb`.

### Analytics assíncrono fora do caminho de dinheiro

- O que foi feito:
  `81f760b` introduziu `app/services/analytics/click_house_sync.rb`, `app/services/analytics/click_house_client.rb`, `app/services/analytics/click_house_event_mapper.rb` e `app/jobs/click_house_sync_job.rb` para replicar eventos publicados do outbox para ClickHouse.
- Por que foi feito:
  O projeto precisava de uma trilha para analytics e consultas operacionais pesadas sem deslocar a verdade financeira para fora do Postgres.
- Alternativas rejeitadas:
  Consultar tudo no Postgres, inclusive workloads analíticos.
  Colocar um broker/stream processor completo no primeiro corte.
  A escolha foi replicação assíncrona best-effort depois da publicação do outbox.
- Base usada:
  commits `81f760b`, `b770d47`; `app/services/analytics/click_house_sync.rb`, `app/services/analytics/click_house_client.rb`, `app/services/analytics/click_house_event_mapper.rb`, `app/jobs/click_house_sync_job.rb`, `docs/database/clickhouse-analytics.md`, `test/services/click_house_sync_test.rb`, `test/services/click_house_client_test.rb`.

### Ferramental operacional executável

- O que foi feito:
  a série `ea7b5f9`, `6003930`, `d20ac86`, `ca69cb9`, `bc06ebf`, `2e2e964`, `cf74bdc`, `f982987` e `549451a` transformou expectativa operacional em código executável: benchmark runner, migration safety, partition planning/readiness/feasibility, backup/restore drill, PITR e WORM readiness, tudo exposto por `lib/tasks/database_engineering.rake` e serviços em `lib/database/*`.
- Por que foi feito:
  depois que o banco passou a carregar parte relevante da confiança do sistema, runbook puro deixou de ser suficiente. O histórico mostra uma sequência deliberada de gates e tarefas verificáveis para checar se o ambiente de banco ainda respeita as suposições do repositório.
- Alternativas rejeitadas:
  Só runbooks em Markdown.
  Só CI genérico sem checks de domínio.
  Depender apenas de tooling externo de plataforma para validar suposições que já estavam explícitas neste código.
- Detalhe por commit:
  `ea7b5f9` introduz o primeiro corte executável de benchmark: `CriticalQueryExplainer`, `LargeSeed`, tasks em `database_engineering.rake` e artefatos de explain. O compromisso aqui é medir queries críticas com cenário reproduzível, não só falar sobre performance.
  `6003930` organiza a base documental do pack de banco. O volume de arquivos em `docs/database/*`, `docs/runbooks/*` e `docs/security/*` indica que a equipe precisou nomear as suposições antes de transformá-las em gates sucessivos.
  `d20ac86` cria `MigrationSafetyChecker` e `PartitionPlan`. Isso separa duas perguntas diferentes: "esta migration é segura?" e "qual topologia de partições o sistema espera?".
  `ca69cb9` adiciona `BenchmarkRunner`, `ConsistencyVerifier`, `RedisTemporaryLock` e expande as tasks. Aqui a documentação deixa de ser só descritiva e passa a ter comandos que falham quando uma hipótese do ambiente deixa de valer.
  `bc06ebf` transforma backup/restore em drill executável por `BackupRestoreDrill`, com integração na task de engenharia.
  `cb44df0` ancora a hash chain em `AuditLogAnchor`, acrescenta `BenchmarkThresholds` e `PartitionReadiness`. O movimento é sair de "rodar benchmark" para "rodar benchmark com critério" e "verificar se o particionamento está pronto".
  `2e2e964` adiciona `PartitionFeasibility`, que não decide só o plano futuro, mas verifica se o estado atual ainda consegue alcançar o plano.
  `cf74bdc` aperta o benchmark com `benchmark volume profile`. Os arquivos tocados mostram que não bastava rodar medições; era preciso saber com que volume e perfil elas foram produzidas.
  `f982987` adiciona `PitrReadiness`. O foco muda de documentação de backup para readiness verificável de point-in-time recovery.
  `549451a` fecha o ciclo com `WormReadiness`, trazendo um gate específico para exportação auditável/WORM em vez de diluir isso em checks genéricos de banco.
- Base usada:
  commits `ea7b5f9`, `6003930`, `d20ac86`, `ca69cb9`, `bc06ebf`, `cb44df0`, `2e2e964`, `cf74bdc`, `f982987`, `549451a`; `lib/tasks/database_engineering.rake`, `lib/database/benchmark_runner.rb`, `lib/database/migration_safety_checker.rb`, `lib/database/partition_plan.rb`, `lib/database/partition_readiness.rb`, `lib/database/partition_feasibility.rb`, `lib/database/pitr_readiness.rb`, `docs/database/partitioning-plan.md`, `docs/database/backup-restore.md`, `test/services/database_benchmark_runner_test.rb`, `test/services/database_migration_safety_checker_test.rb`, `test/services/database_partition_plan_test.rb`, `test/services/database_partition_feasibility_test.rb`, `test/services/database_pitr_readiness_test.rb`, `test/services/audit_log_worm_readiness_test.rb`.

### Coordenação operacional transitória merece boundary próprio

- O que foi feito:
  `20ea392` introduziu `Operational::TemporaryLock`; depois `ca69cb9` acrescentou `Operational::RedisTemporaryLock` e expandiu a cobertura desse boundary.
- Por que foi feito:
  nem toda coordenação entre processos é uma regra financeira durável. Os commits separam bem duas coisas: invariantes do dinheiro ficam no banco/ledger; travas transitórias de operação ficam em um boundary nomeado, sem espalhar chamadas cruas de Redis por services arbitrários.
- Alternativas rejeitadas:
  embutir uso de Redis diretamente nos callers.
  reutilizar locks de banco para qualquer tipo de coordenação temporária.
- Base usada:
  commits `20ea392`, `ca69cb9`; `app/services/operational/temporary_lock.rb`, `app/services/operational/redis_temporary_lock.rb`, `docs/database/redis-usage.md`, `test/services/operational_temporary_lock_test.rb`, `test/services/operational_redis_temporary_lock_test.rb`.

### Contratos financeiros centralizados

- O que foi feito:
  `577d2ad` criou `app/services/financial_contracts.rb`.
- Por que foi feito:
  Os mesmos nomes de eventos e chaves estavam espalhados em vários pontos.
- Alternativas rejeitadas:
  Manter strings soltas em cada service.
  Criar uma camada genérica de "event registry" mais pesada do que o necessário.
- Base usada:
  commit `577d2ad`, `app/services/financial_contracts.rb`, usos em `app/services/pix_payments/settle.rb`, `lib/database/consistency_verifier.rb` e testes de invariantes/concorrência.

### Guards SQL específicos por boundary, não uma trigger genérica opaca

- O que foi feito:
  da sequência `60a0f97` até `775fef5`, o projeto adicionou guards separados para evidência de outbox, estado financeiro, comandos de wallet, replay idempotente, processed events, balances, maker-checker, reconciliation, aggregate identity, journal taxonomy, MED, refund, payout, split e escrita de projeções.
- Por que foi feito:
  a série de commits aponta para uma preferência observável: cada boundary sensível falha por um motivo mais explícito, com testes e verificadores próprios, em vez de depender de uma única camada genérica de "integridade". Isso aumenta o volume de SQL, mas deixa visível qual decisão de negócio cada guard está protegendo.
- Alternativas rejeitadas:
  manter enforcement apenas nos services Ruby.
  condensar tudo em triggers genéricas com menos vocabulário de domínio.
- Detalhe por commit:
  `60a0f97` fecha a evidência do outbox como fato publicável: a migration cria guards para `outbox_events`, `ClickHouseSync` e o mapper/testes downstream são atualizados para refletir esse contrato.
  `68c0f56` endurece evidência de estado financeiro. O vínculo com `pix_payment_reject_test.rb` mostra que a preocupação não era só estrutura SQL, mas transições de estado que precisavam deixar rastro coerente.
  `4ab223a` exige evidência para comandos de wallet. `Funding`, `Transfer`, serializer de funding e `Fundings::Create` entram no diff porque a regra precisava alcançar tanto persistência quanto contrato público mínimo.
  `f4f5b3e` fecha replay idempotente como evidência, não só como comportamento de controller. `IdempotencyKey` e `idempotency_test.rb` mudam junto da migration, o que sustenta essa leitura.
  `8ecee8e` protege `processed_events` e o consumo operacional do outbox. O fato de tocar `OutboxEventsController`, `ProcessedEvent`, `ClickHouseSync` e testes correlatos mostra uma preocupação com afterlife do evento, não só com sua criação.
  `01a1d85` endurece a trilha de balances. `BalanceProjection`, `BalanceSnapshot` e `BalanceSnapshots::Capture` aparecem juntos porque projeção e snapshot passam a precisar de evidência compatível.
  `5a490bf` move maker-checker para o mesmo regime: `OperatorApproval` ganha guards próprios, em vez de depender só da política Rails e do service de aprovação.
  `1f0a4f6` fecha reconciliação como evidência de banco. `ReconciliationRun`, `ReconciliationRow` e seus testes entram juntos porque a reconciliação já não era só cálculo em memória.
  `6df1387` exige evidência de aggregate no outbox. Os testes de publish, mapper e sync mudam juntos, sustentando que o aggregate do evento precisava continuar identificável em toda a cadeia.
  `62bd0e0` previne tampering de aggregates financeiros já gravados. Aqui o foco é menos payload e mais impedir mutação posterior de identidades sensíveis.
  `f850a78` endurece evidência do journal financeiro em si. A combinação de migration, ADR do ledger e testes de invariantes mostra que o lançamento contábil precisava carregar referência e forma mais fechadas.
  `76f5cbf` fecha a taxonomia de eventos do journal. `JournalEntry` e `ledger_journal_poster_test.rb` mudam junto da migration, então a regra sai do campo "convenção" e vira enum/contrato verificável.
  `b693532` exige governança explícita para resolução de MED. O diff toca controllers ops/público, `MedCase`, policies, maker-checker e views, indicando que a decisão atravessa banco, UI e fluxo operacional.
  `0d4ca54` complementa o commit anterior exigindo que o outbox de MED carregue a evidência correta de resolução. A preocupação aqui já não é "quem pode resolver", e sim "o evento emitido prova o que aconteceu?".
  `64deac6` exige idempotency key para os comandos financeiros centrais. O alcance em `Funding`, `Transfer`, `PixPayment`, `Payout`, `Refund`, `SplitPayment` e `MedCase` mostra que a regra foi tratada como contrato transversal de escrita.
  `e5f4e93` amarra identidade de comando no outbox. Os services de `med_cases`, `payouts` e lifecycle de Pix aparecem porque não bastava existir outbox; ele precisava apontar para o comando certo.
  `48be481` coloca um guard específico para limite de refund sobre Pix. Aqui o repositório evita esconder uma regra de produto relevante dentro de uma trigger financeira genérica.
  `929c4f9` governa early settlement de payout. `Payout`, serializer, `Payouts::Settle`, OpenAPI e testes indicam uma decisão que afeta regra de negócio, contrato público e evidência de banco ao mesmo tempo.
  `e51d574` exige unicidade de destinos em split. O fato de tocar arquitetura, indexing strategy e incident response junto da migration mostra que isso foi tratado tanto como regra lógica quanto como custo operacional.
  `775fef5` fecha o write gate de `BalanceProjection`. `WriteGate`, `Ledger::JournalPoster`, rebuild, helper de domínio e invariantes indicam que a projeção derivada deixou de aceitar escrita por caminhos arbitrários.
- Base usada:
  commits `60a0f97`, `68c0f56`, `4ab223a`, `f4f5b3e`, `8ecee8e`, `01a1d85`, `5a490bf`, `1f0a4f6`, `6df1387`, `62bd0e0`, `f850a78`, `76f5cbf`, `b693532`, `0d4ca54`, `64deac6`, `e5f4e93`, `48be481`, `929c4f9`, `e51d574`, `775fef5`; `db/structure.sql`, migrations `20260602170000` a `20260602223500`, `lib/database/consistency_verifier.rb`, `test/models/database_financial_invariants_test.rb`, `test/services/database_consistency_verifier_test.rb`.

### Histórico publicado não é reescrito só para satisfazer regra nova

- O que foi feito:
  `d13051a` criou `OutboxLegacyCommandIdentityException` e um mecanismo explícito de exceção para envelopes legados de outbox cuja identidade de comando já estava publicada.
- Por que foi feito:
  o commit escolhe preservar a imutabilidade do histórico emitido e registrar exceções conhecidas, em vez de "corrigir" retrospectivamente eventos que já tinham sido publicados. Isso combina melhor com a própria narrativa do repositório sobre evidência e auditabilidade.
- Alternativas rejeitadas:
  reescrever o histórico publicado para caber na nova regra.
  ignorar a divergência sem registrá-la em lugar nenhum.
- Base usada:
  commit `d13051a`, `app/models/outbox_legacy_command_identity_exception.rb`, migration `20260602224500_accept_immutable_legacy_outbox_command_identity.rb`, `lib/database/consistency_verifier.rb`, `docs/events/messaging.md`, `test/models/database_financial_invariants_test.rb`, `test/services/database_consistency_verifier_test.rb`.

### Lifecycle explícito de wallet/customer

- O que foi feito:
  `22cf3c1` introduziu `app/services/financial_lifecycle/status_guard.rb` e passou a chamá-lo de `Fundings::Create`, `Transfers::Create`, `PixPayments::Create`, `Payouts::Create`, `Refunds::Create`, `SplitPayments::Create` e `Wallets::Creator`.
- Por que foi feito:
  Os estados existiam no modelo, mas não protegiam os comandos.
- Alternativas rejeitadas:
  Deixar isso só para policy de UI.
  Resolver apenas com validações de model.
  O histórico escolheu proteger os pontos de entrada de domínio.
- Base usada:
  `app/services/financial_lifecycle/status_guard.rb`, `app/services/fundings/create.rb`, `app/services/transfers/create.rb`, `app/services/wallets/creator.rb`, `test/services/wallet_creator_test.rb`, `test/services/transfer_create_test.rb`.

### Chaves legadas só como compatibilidade local

- O que foi feito:
  `9397a1a` passou a condicionar `Organization.authenticate_api_key` a `config.x.api.allow_legacy_organization_api_keys` e moveu o seed para `ApiCredential`.
- Por que foi feito:
  Sem isso, o contrato de `ApiCredential` podia ser contornado por um caminho legado mais fraco.
- Alternativas rejeitadas:
  Remover o caminho legado sem compatibilidade nenhuma.
  Deixar o bypass ativo em produção.
  A escolha foi manter compatibilidade apenas em `development` e `test`.
- Base usada:
  commit `9397a1a`, `app/controllers/v1/base_controller.rb`, `config/application.rb`, `config/environments/development.rb`, `config/environments/test.rb`, `db/seeds.rb`, `test/requests/api_authentication_test.rb`.

### Auditoria sanitizada em vez de logging cru

- O que foi feito:
  `cffccbe` criou `app/services/audit_logs/parameter_sanitizer.rb` e `app/services/audit_logs/request_logger.rb`.
- Por que foi feito:
  O audit log estava perto demais do request bruto e podia duplicar ou vazar informação sensível.
- Alternativas rejeitadas:
  Confiar apenas em `filter_parameter_logging`.
  Auditar tudo cru e tratar masking depois.
  O histórico preferiu um boundary explícito de auditoria.
- Base usada:
  `app/services/audit_logs/parameter_sanitizer.rb`, `app/services/audit_logs/request_logger.rb`, `app/controllers/api_controller.rb`, `app/controllers/v1/base_controller.rb`, `test/requests/api_audit_logging_test.rb`.

### Contrato público deve seguir o envelope emitido

- O que foi feito:
  `e5afdab` removeu vários schemas antigos e deixou `docs/events/outbox_event.v1.json` como fonte pública coerente com `Outbox::Publisher.envelope_for`.
- Por que foi feito:
  Documentação divergente cria uma falsa impressão de robustez.
- Alternativas rejeitadas:
  Manter docs "aspiracionais".
  Criar uma camada de mapeamento pública sem necessidade real.
- Base usada:
  commit `e5afdab`, `docs/events/outbox_event.v1.json`, `docs/events/README.md`, `app/services/outbox/publisher.rb`, `test/services/outbox_event_contract_test.rb`.

### Melhor esconder bucket não implementado do que mentir por contrato

- O que foi feito:
  `2315d41` removeu `pending_cents` e `blocked_cents` de `app/serializers/balance_projection_serializer.rb`, `openapi.yaml` e `app/views/ops/wallets/show.html.erb`.
- Por que foi feito:
  O repositório expunha buckets cujo comportamento ainda não era sustentado ponta a ponta.
- Alternativas rejeitadas:
  Implementar toda a semântica de hold/bloqueio só para preservar shape de resposta.
  Continuar expondo campos enganadores.
- Base usada:
  commit `2315d41`, `app/serializers/balance_projection_serializer.rb`, `app/views/ops/wallets/show.html.erb`, `openapi.yaml`, `test/requests/financial_workflow_test.rb`.

### OpenAPI deve documentar o comportamento real, não o desejado

- O que foi feito:
  `b0fe05e` ajustou `openapi.yaml`, `docs/api/error-format.md` e criou `test/services/openapi_contract_test.rb`.
- Por que foi feito:
  O repositório já exigia `Idempotency-Key` e já bloqueava resolução pública de MED, mas a especificação ainda dava a entender caminhos mais permissivos.
- Alternativas rejeitadas:
  Manter a spec otimista até a feature completa existir.
  Alterar o runtime só para bater com a spec antiga.
  A decisão correta foi fazer a spec seguir o software.
- Base usada:
  commit `b0fe05e`, `openapi.yaml`, `docs/api/error-format.md`, `test/services/openapi_contract_test.rb`, `test/requests/financial_extensions_api_test.rb`.

### Redaction por padrão antes de inventar ACL fina

- O que foi feito:
  `70eb0f3` criou `app/services/privacy/redactor.rb` e passou a usá-lo em serializers, `Idempotency::Runner` e views ops.
- Por que foi feito:
  O projeto não tinha modelo de privilégio por campo; expor PII por default seria um risco desnecessário.
- Alternativas rejeitadas:
  Manter responses cruas enquanto um sistema de escopos não existisse.
  Redigir só logs, mas não responses.
  A escolha foi redigir por padrão e exigir endpoints privilegiados no futuro, se necessário.
- Base usada:
  `app/services/privacy/redactor.rb`, serializers `customer/pix_payment/payout/refund/*`, `app/views/ops/pix_payments/*`, `test/requests/privacy_redaction_test.rb`.

### Consistência deve recalcular depois do lock

- O que foi feito:
  `515b79c` mudou `app/services/balance_projections/rebuilder.rb` e `app/services/balance_snapshots/capture.rb`.
- Por que foi feito:
  Um dry-run anterior ao lock podia ficar velho antes da gravação real.
- Alternativas rejeitadas:
  Confiar que o rebuild offline nunca concorreria com ledger real.
  Tratar drift só com auditoria posterior.
  A solução escolhida foi reavaliar o valor dentro da fronteira transacional.
- Base usada:
  `app/services/balance_projections/rebuilder.rb`, `app/services/balance_snapshots/capture.rb`, `test/services/balance_snapshot_and_rebuild_test.rb`, `docs/database/reconciliation-data-model.md`.

### Superfícies operacionais devem falhar sem vazar detalhes

- O que foi feito:
  `a8d1171` alterou `app/controllers/health/readiness_controller.rb`, `app/controllers/ops/base_controller.rb` e os testes de request correspondentes.
- Por que foi feito:
  `/ready` não precisa entregar stack/detail de banco para o caller, e páginas globais do ops não deveriam ficar abertas para qualquer papel autenticado.
- Alternativas rejeitadas:
  Manter logs e resposta HTTP com o mesmo detalhe.
  Confiar só em capability checks de ação sensível, deixando leitura global aberta.
- Base usada:
  `app/controllers/health/readiness_controller.rb`, `app/controllers/ops/base_controller.rb`, `test/requests/operability_test.rb`, `test/requests/ops_console_request_test.rb`.

### Lock determinístico para comandos multi-wallet

- O que foi feito:
  `63618c2` criou `app/services/wallets/projection_locker.rb` e passou a usá-lo em `Transfers::Create` e `SplitPayments::Create`.
- Por que foi feito:
  O histórico não prova um deadlock concreto anterior, mas sustenta que a equipe passou a tratar transferências inversas concorrentes como cenário de risco real.
- Alternativas rejeitadas:
  Confiar na ordem incidental em que cada command recebe wallets.
  Deixar o banco arbitrar sem convenção explícita na app.
- Base usada:
  commit `63618c2`, `app/services/wallets/projection_locker.rb`, `app/services/transfers/create.rb`, `app/services/split_payments/create.rb`, `test/services/financial_concurrency_test.rb`.

### Atualizar projeções em lote antes de otimizar fora do processo

- O que foi feito:
  `0f83617` mudou `Ledger::JournalPoster` para acumular delta por wallet/moeda antes de aplicar a projeção.
- Por que foi feito:
  O código anterior aplicava a projeção por linha do journal, o que multiplicava leituras/escritas sobre o mesmo wallet quando havia várias linhas líquidas para a mesma conta.
- Alternativas rejeitadas:
  Partir direto para infraestrutura paralela ou fila separada de projeções.
  Aceitar trabalho duplicado no caminho quente por ser "simples".
- Base usada:
  commit `0f83617`, `app/services/ledger/journal_poster.rb`, `app/models/wallet.rb`, `test/services/ledger_journal_poster_test.rb`.

### Endpoint público só entra quando existe boundary externo real

- O que foi feito:
  `97a34fd` removeu `app/controllers/v1/outbox_events_controller.rb`, `app/serializers/outbox_event_serializer.rb` e o path `/v1/outbox_events`.
- Por que foi feito:
  O outbox virou evidência operacional e ferramenta de recuperação interna; o histórico mais recente não sustenta esse recurso como contrato de integração pública.
- Alternativas rejeitadas:
  Manter o endpoint por conveniência de debug.
  Rebatizar o endpoint sem redefinir quem é o consumidor.
- Base usada:
  commit `97a34fd`, `config/routes.rb`, `openapi.yaml`, `docs/architecture/security.md`, `test/services/openapi_contract_test.rb`.

### Reduzir repetição estrutural sem criar abstração pesada

- O que foi feito:
  `76d9c2a` criou `app/services/application_service.rb` e moveu vários services para herdar dele.
- Por que foi feito:
  O padrão `self.call -> new(...).call` estava repetido em muitos arquivos sem carregar semântica diferente.
- Alternativas rejeitadas:
  Manter a repetição indefinidamente.
  Introduzir um framework interno de command bus.
- Base usada:
  commit `76d9c2a`, `app/services/application_service.rb`, diffs em `Fundings::Create`, `Ledger::JournalPoster`, `Reconciliation::Run` e outros services.

### Tooling operacional de banco não pertence ao domínio da aplicação

- O que foi feito:
  `d2355a6` moveu `consistency_verifier`, benchmark runners, PITR checks e ferramentas correlatas de `app/services/database` para `lib/database`.
- Por que foi feito:
  Esses objetos servem à operação e à engenharia de banco, não ao domínio de negócio exposto pela aplicação.
- Alternativas rejeitadas:
  Deixar tudo em `app/services` como se fosse command de produto.
  Empurrar essas ferramentas para scripts soltos sem namespace.
- Base usada:
  commit `d2355a6`, diretório atual `lib/database/*`, `lib/tasks/database_engineering.rake`.

### Documentação precisa seguir a superfície real, não autoavaliação

- O que foi feito:
  `4584b85`, `8f72783`, `b4b14bf` e `d035016` limparam framing e boundary docs: removeram `docs/architecture/senior-tech-lead-validation.md`, alinharam `docs/architecture/security.md`, explicaram reconciliação como snapshot em `docs/database/reconciliation-data-model.md` e ajustaram `redocly.yaml`.
- Por que foi feito:
  O repositório já tinha documentação demais para continuar carregando material autocelebratório ou ambíguo sobre o que realmente é garantido.
- Alternativas rejeitadas:
  Preservar texto de "autoavaliação" por marketing de portfólio.
  Continuar descrevendo reconciliação como se fosse fechamento contábil.
  Forçar o OpenAPI a obedecer regras de lint inadequadas para a superfície escolhida.
- Base usada:
  commits `4584b85`, `8f72783`, `b4b14bf`, `d035016`; arquivos `README.md`, `docs/architecture/security.md`, `docs/database/reconciliation-data-model.md`, `redocly.yaml`.

### Branch coverage crítico precisa de gate, não só número global

- O que foi feito:
  `9df9e43` adicionou `test/services/financial_branch_coverage_test.rb`, criou `bin/critical_money_branch_coverage` e passou a rodar esse guard em `bin/ci`.
- Por que foi feito:
  O branch coverage global ainda mistura views, ops, infra defensiva e caminhos de dinheiro. O audit original apontava risco nos caminhos financeiros; o commit transforma esse subconjunto em contrato explícito de pelo menos 85% de branch coverage.
- Alternativas rejeitadas:
  Fingir que o branch coverage global de ~70% satisfaz o achado.
  Tentar subir o número global com testes de baixo valor em código periférico.
- Base usada:
  commit `9df9e43`, `test/services/financial_branch_coverage_test.rb`, `bin/critical_money_branch_coverage`, `bin/ci`, relatório SimpleCov.

## 5. Prós e contras de cada decisão arquitetural importante

| Decisão | Prós | Contras |
| --- | --- | --- |
| Monólito Rails híbrido | Um deploy, uma base de testes, ops e API compartilham o mesmo modelo | Cresce rápido; controllers, views e jobs disputam espaço conceitual |
| System test do ops focado em inspeção | Mantém alguma prova real de UI sem deixar a suíte browser dominar o custo de manutenção | Parte relevante da governança fica protegida por request/service test, não pelo browser |
| Ledger + projections | Explica dinheiro e ainda entrega leitura rápida | Escrever fica mais caro e exige disciplina transacional |
| Outbox transacional | Evita perda silenciosa entre DB e integração | Introduz estado intermediário, retries e runbooks |
| API key + idempotência | Boundary simples para integrações server-to-server | Ainda é credencial estática; rotação e escopo precisam vigilância |
| Hardening antes de expandir domínio | Reduz risco de crescer em cima de auth/outbox/runtime frouxos | Consome tempo que não aparece como feature nova |
| Maker-checker coarse | Demonstra governança sem explosão de política | Papéis são amplos demais para produção madura |
| Hash chain de auditoria | Evidência forte e verificável | Complexidade operacional maior do que log convencional |
| Comandos financeiros dedicados por fluxo | Regras de payout/refund/split/MED ficam legíveis e testáveis por verbo | Mais classes, serializers e controllers para manter |
| Reconciliação explicável e itemizada | Facilita auditoria operacional e análise de divergência | Cria mais leitura derivada, telas e contratos para sustentar |
| Invariantes no banco | Protege contra bypass acidental e cargas externas | Migrations e `db/structure.sql` ficam mais difíceis de ler e evoluir |
| Snapshots e processed events derivados | Ajudam rebuild, auditoria e sync downstream sem trocar a fonte de verdade | Adicionam estado derivado extra que também precisa ser protegido |
| ClickHouse só para analytics | Mantém Postgres como única verdade financeira | Pipeline é best-effort; não resolve integração pública nem exactly-once |
| Ferramental executável de banco | Torna docs verificáveis | Pode virar showpiece se não acompanhar o código real |
| Lock operacional transitório com boundary nomeado | Separa coordenação temporária de invariantes financeiros permanentes | Introduz mais um tipo de lock que o time precisa entender |
| Contratos centralizados | Reduz drift entre services, testes e verificador | Ainda exige disciplina para atualizar docs/eventos públicos em paralelo |
| Guards SQL por boundary explícito | Falhas ficam mais específicas e auditáveis | A superfície SQL cresce muito e custa onboarding |
| Exceções explícitas para legado publicado | Preserva imutabilidade da evidência já emitida | Carrega um mecanismo permanente para acomodar dívida histórica |
| Lock determinístico de projeções | Reduz risco de deadlock em comandos multi-wallet e torna a ordem de lock auditável no código | Introduz convenção adicional que todo novo command multi-wallet precisa respeitar |
| Atualização em lote de projeções | Remove trabalho repetido no caminho quente sem trocar o modelo contábil | Exige cuidado para não esconder bugs de delta líquido em journals mais complexos |
| Outbox fora da API pública | Reduz superfície externa e deixa claro que outbox é evidência operacional | Tira um endpoint que podia ser usado como ferramenta ad hoc de debug por clientes |
| Tooling de banco em `lib` | Separa operação/engenharia de banco do domínio de produto | Aumenta a distância entre esses objetos e a convenção usual de services Rails |
| Documentação anti-autoavaliação | Diminui marketing interno e aumenta confiança do leitor técnico | O repositório fica menos “impressionista” e mais áspero de vender como vitrine |

## 6. Erros, decisões fracas ou correções feitas durante o processo

- O core inicial chegou antes da cobertura principal.
  Evidência: `70a8841` veio antes de `9035824`.
  Consequência: a arquitetura base não nasceu com TDD estrito.

- O console ops ficou flake logo após nascer.
  Evidência: `56ec94c`, `1bd1df9`, `b69e3ba`, `6a40b98`, `65a8e80`, `37e3180`.
  Aprendizado: backoffice também precisa de disciplina de UX testável; sem isso, system tests viram ruído.

- A primeira tentativa de provar o console pelo browser queria carregar mais governança do que a suíte suportava bem.
  Evidência: a sequência termina em `37e3180`, que restringe o system test a inspeção.
  Aprendizado: mutações críticas do ops ficaram melhores em request/service tests do que em um E2E gigante.

- A concorrência de Pix settlement/reversal estava frouxa.
  Evidência: `593ebd2` mexe em `app/services/pix_payments/reverse.rb` e `app/services/pix_payments/settle.rb`.
  Correção: revalidar estado sob lock, não antes dele.

- O outbox podia disputar publicação entre workers.
  Evidência: `9b17f12`.
  Correção: claim explícito antes de publicar.

- O ledger ainda permitia mutação por caminhos baixos demais.
  Evidência: `d692a31` e depois a suíte de invariantes em `test/models/database_financial_invariants_test.rb`.

- A reconciliação inicialmente dizia menos do que a operação precisava para explicar um saldo.
  Evidência: `0eb1911` e `dde2aab`.
  Correção: introduzir explicadores, statement lines e rows itemizadas em vez de só um resumo agregado.

- A identidade idempotente inicialmente ignorava query string.
  Evidência: `1db67f2`.
  Aprendizado: "mesma rota" não é o mesmo que "mesma intenção", principalmente com filtros/paginação.

- O projeto criou estados de wallet/customer antes de fazê-los valer nos comandos.
  Evidência: `22cf3c1`.
  Isso é um erro clássico: o modelo parecia mais forte do que a aplicação real.

- O boundary de autenticação ainda aceitava atalho legado forte demais.
  Evidência: `9397a1a`.
  Correção: compatibilidade restrita a ambiente local/teste.

- O audit log de API misturava preocupação de logging com request cru.
  Evidência: `cffccbe`.
  Correção: sanitização dedicada e escrita centralizada.

- O outbox tinha retry por evento, mas não tinha um sweep recorrente explícito.
  Evidência: `178c4e4`.
  Aprendizado: confiabilidade operacional não deve depender só de quem criou o evento lembrar de enfileirar tudo.

- Parte da prontidão de banco começou como documentação e convenção antes de virar gate executável.
  Evidência: `ea7b5f9`, `6003930`, `d20ac86`, `ca69cb9`, `cb44df0`, `2e2e964`, `cf74bdc`, `f982987`, `549451a`.
  Correção: transformar benchmark, migration safety, partitioning, PITR e WORM em tarefas/verificadores rodáveis.

- Os contratos em `docs/events/*.v1.json` descreviam uma taxonomia que o app não publicava.
  Evidência: `e5afdab`.
  Correção: alinhar documentação ao envelope real.

- O contrato público de saldo prometia buckets ainda não sustentados.
  Evidência: `2315d41`.
  Correção: esconder campos antes de afirmar uma semântica que o domínio ainda não entrega.

- O OpenAPI também estava mais permissivo do que o runtime.
  Evidência: `b0fe05e`.
  Correção: documentar `Idempotency-Key` obrigatório, `403` públicos e o comportamento real de MED.

- O projeto ainda devolvia PII demais em responses e telas ops.
  Evidência: `70eb0f3`.
  Correção: redaction padrão em serializers, idempotency evidence e views.

- O rebuild de projeções ainda podia gravar cálculo envelhecido.
  Evidência: `515b79c`.
  Correção: recalcular saldo e capturar snapshot dentro do lock transacional.

- Transfer e split ainda deixavam a ordem de lock implícita.
  Evidência: `63618c2` adiciona `Wallets::ProjectionLocker` e o teste `posts inverse transfers concurrently without deadlocking`.
  Correção: ordenar locks por `wallet.id` antes de validar saldo.

- O poster de journal ainda fazia trabalho repetido por linha, não por wallet líquido.
  Evidência: `0f83617` e o novo teste `applies net projection deltas per wallet and currency`.
  Correção: acumular deltas por `(wallet_id, currency)` antes de aplicar projeção.

- O rollout de masking introduziu um bug de lookup de constante e deixou um system test esperando PII crua.
  Evidência: `539cf6a`.
  Correção: qualificar `::Privacy::Redactor` nos pontos de uso e alinhar `test/system/ops_console_test.rb` ao comportamento mascarado.

- As superfícies de leitura global e readiness ainda estavam generosas demais.
  Evidência: `a8d1171`.
  Correção: reduzir detalhe em `/ready` e exigir admin para leitura global do ops.

- O tooling de banco estava dentro de `app/services`, misturando operação e domínio.
  Evidência: `d2355a6`.
  Correção: mover esse conjunto para `lib/database`.

- A API pública ainda carregava o endpoint de outbox sem um consumidor externo bem definido.
  Evidência: `97a34fd`.
  Correção: remover `/v1/outbox_events` do código, da spec e dos testes de contrato.

- A documentação ainda se avaliava e ainda descrevia alguns boundaries de forma otimista.
  Evidência: `4584b85`, `8f72783`, `b4b14bf`, `d035016`.
  Correção: remover framing de autoavaliação, alinhar segurança à superfície real, chamar reconciliação de snapshot operacional e ajustar o lint para a spec realmente adotada.

- O branch coverage dos caminhos críticos de dinheiro ainda era só uma leitura manual do SimpleCov.
  Evidência: `9df9e43`.
  Correção: adicionar testes de branches financeiros e um guard executável de 85% em `bin/critical_money_branch_coverage`.

- A regra nova de identidade de comando no outbox chegou depois de já existir histórico publicado.
  Evidência: `d13051a`.
  Correção: registrar exceções explícitas de legado, em vez de reescrever a evidência já emitida.

- O verificador de consistência tinha cobertura boa, mas falhava mal como material de aprendizado.
  Evidência: antes de `81a86c2`, `test/services/database_consistency_verifier_test.rb` concentrava várias garantias em um único teste.
  Correção: separar asserções por boundary para localizar regressão mais rápido.

## 7. Como o TDD foi usado, incluindo ciclos red-green-refactor reais

O repositório não é um exemplo puro de TDD linear do primeiro ao último commit. O começo registra uma sequência "feature -> testes", não "teste vermelho -> implementação"; isso aparece no intervalo entre `70a8841` e `9035824`.

Dito isso, o histórico posterior registra TDD e teste-dirigido por correção em ciclos reais:

1. Sistema ops
   Os commits `56ec94c` a `37e3180` são praticamente uma série de red-green em torno de `test/system/ops_console_test.rb`.
   O problema era flake de navegação e sincronização; a solução foi estabilizar waits, cliques e escopo da inspeção.

2. Pix sob concorrência
   `593ebd2` atualizou `test/services/pix_payment_lifecycle_test.rb` junto com a correção.
   O ciclo foi: expor que a decisão antes do lock não bastava, falhar o teste, mover a revalidação para dentro do lock.

3. Claim do outbox
   `9b17f12` usa `test/jobs/outbox_publish_job_test.rb` para fixar o comportamento esperado.
   O ciclo foi: reconhecer janela de publicação duplicada, proteger com teste focado, só então alterar o job/model.

4. Identidade idempotente incluindo query string
   `1db67f2` ajustou `test/requests/idempotency_test.rb`.
   O insight foi que replay incorreto também é bug de contrato, não só de persistência.

5. Lifecycle de wallet/customer
   `22cf3c1` adicionou/ajustou `test/services/funding_create_test.rb`, `test/services/transfer_create_test.rb`, `test/services/pix_payment_lifecycle_test.rb`, `test/services/payout_lifecycle_test.rb`, `test/services/split_payment_create_test.rb`, `test/services/refund_and_med_lifecycle_test.rb` e `test/services/wallet_creator_test.rb`.
   O git não prova a ordem interna dentro do commit, mas registra teste e implementação no mesmo pacote atômico em torno do novo guard.

6. Chave legada e contrato de autenticação
   `9397a1a` adicionou `test/requests/api_authentication_test.rb` para registrar que a compatibilidade legada fica restrita.

7. Sanitização de auditoria
   `cffccbe` adicionou `test/requests/api_audit_logging_test.rb`.
   O ciclo foi: explicitar em teste que a auditoria precisa registrar status final e params sanitizados, depois mover essa responsabilidade para um boundary dedicado.

8. Sweep do outbox
   `178c4e4` adicionou `test/jobs/outbox_sweep_job_test.rb`.
   O ciclo foi: transformar um requisito operacional difuso em comportamento repetível e verificável.

9. Contrato público de eventos
   `e5afdab` adicionou `test/services/outbox_event_contract_test.rb`.
   O teste materializa um princípio importante: docs de evento têm de nascer do envelope real ou são dívida, não contrato.

10. OpenAPI como contrato executável
   `b0fe05e` adicionou `test/services/openapi_contract_test.rb`.
   O ciclo foi: transformar drift documental em teste de contrato, em vez de confiar em revisão visual do YAML.

11. Redação de PII e evidence sanitizada
   `70eb0f3` adicionou `test/requests/privacy_redaction_test.rb`.
   O ciclo foi: explicitar em teste que API pública, evidência idempotente e ops HTML não podiam mais devolver PII crua.

12. Rebuild/snapshot sob lock real
   `515b79c` reforçou `test/services/balance_snapshot_and_rebuild_test.rb`.
   O ciclo foi: explicitar em teste que o dry-run antigo podia ficar velho e então mover o recálculo para dentro do lock.

13. Privacy masking validado no caminho real
   `539cf6a` nasceu de uma falha de integração real no `bin/ci`.
   O ciclo foi: o gate final quebrou por `NameError` em serializers/helpers e por uma expectativa antiga no system test; o conserto qualificou o namespace e passou a validar o texto mascarado.

14. Ops/readiness como boundary explícito
   `a8d1171` reforçou `test/requests/operability_test.rb` e `test/requests/ops_console_request_test.rb`.
   O ciclo foi: transformar uma preocupação de exposição excessiva em contrato testável de request.

15. Comandos multi-wallet com ordem explícita de lock
   `63618c2` reforçou `test/services/financial_concurrency_test.rb`.
   O histórico não prova um deadlock anterior, mas registra que a equipe materializou o risco em teste e em código antes de chamar a solução de pronta.

16. Atualização de projeção guiada por delta líquido
   `0f83617` ampliou `test/services/ledger_journal_poster_test.rb`.
   O ciclo foi: explicitar que journals com linhas compensatórias para a mesma wallet não devem gerar trabalho repetido nem resultado divergente.

17. Refactor guiado por cobertura
   `81a86c2` não mudou regra de negócio; ele mudou a forma de falha da suíte.
   Isso é o "refactor" do ciclo: a lógica já estava verde, então a revisão tratou de melhorar a legibilidade e a localização do feedback sem mexer no comportamento.

## 8. Quais testes protegem quais decisões

- Ledger como verdade contábil:
  `test/services/ledger_journal_poster_test.rb`
  `test/models/database_financial_invariants_test.rb`

- Idempotência e replay:
  `test/requests/idempotency_test.rb`
  `test/services/funding_create_test.rb`
  `test/services/transfer_create_test.rb`

- Boundary de autenticação e compatibilidade legada:
  `test/requests/api_authentication_test.rb`

- Hardening de boundary, publisher e runtime local:
  `test/requests/api_authentication_test.rb`
  `test/requests/idempotency_test.rb`
  `test/jobs/outbox_publish_job_test.rb`
  `test/services/outbox_http_publisher_test.rb`
  `test/controllers/passwords_controller_test.rb`
  `test/controllers/sessions_controller_test.rb`
  `test/models/user_test.rb`
  `test/requests/operability_test.rb`

- Auditoria sanitizada de API:
  `test/requests/api_audit_logging_test.rb`

- Redaction de PII em API/ops/idempotência:
  `test/requests/privacy_redaction_test.rb`

- Privacy masking no fluxo humano e em serializers:
  `test/system/ops_console_test.rb`
  `test/requests/pix_payments_api_test.rb`
  `test/requests/idempotency_test.rb`

- Outbox transacional e retry:
  `test/jobs/outbox_publish_job_test.rb`
  `test/jobs/outbox_sweep_job_test.rb`
  `test/services/click_house_sync_test.rb`
  `test/services/outbox_http_publisher_test.rb`

- Contrato público do envelope de eventos:
  `test/services/outbox_event_contract_test.rb`

- Comandos dedicados de payout/refund/split/MED:
  `test/requests/financial_extensions_api_test.rb`
  `test/services/payout_lifecycle_test.rb`
  `test/services/refund_and_med_lifecycle_test.rb`
  `test/services/split_payment_create_test.rb`

- Contrato OpenAPI alinhado ao runtime:
  `test/services/openapi_contract_test.rb`

- Superfície pública sem endpoint operacional de outbox:
  `test/services/openapi_contract_test.rb`

- Pix lifecycle, settlement e reversal:
  `test/services/pix_payment_lifecycle_test.rb`
  `test/services/financial_concurrency_test.rb`

- Governança maker-checker e MED:
  `test/requests/ops_console_request_test.rb`
  `test/services/refund_and_med_lifecycle_test.rb`
  `test/requests/financial_extensions_api_test.rb`

- Reconciliation e explicação de saldo:
  `test/services/reconciliation_run_test.rb`
  `test/models/reconciliation_row_test.rb`
  `test/requests/financial_workflow_test.rb`

- Snapshots, rebuild e processed events:
  `test/services/balance_snapshot_and_rebuild_test.rb`
  `test/models/database_financial_invariants_test.rb`
  `test/services/click_house_sync_test.rb`

- Database-as-contract:
  `test/models/database_financial_invariants_test.rb`
  `test/services/database_consistency_verifier_test.rb`

- Rebuild e snapshot consistentes:
  `test/services/balance_snapshot_and_rebuild_test.rb`

- Ordem de lock e concorrência multi-wallet:
  `test/services/financial_concurrency_test.rb`

- Readiness e superfícies globais do ops:
  `test/requests/operability_test.rb`
  `test/requests/ops_console_request_test.rb`

- Ferramentas operacionais de banco:
  `test/services/database_migration_safety_checker_test.rb`
  `test/services/database_partition_plan_test.rb`
  `test/services/database_partition_feasibility_test.rb`
  `test/services/database_partition_readiness_test.rb`
  `test/services/database_pitr_readiness_test.rb`
  `test/services/database_benchmark_runner_test.rb`
  `test/services/database_benchmark_thresholds_test.rb`

- Locks operacionais transitórios:
  `test/services/operational_temporary_lock_test.rb`
  `test/services/operational_redis_temporary_lock_test.rb`

- Audit trail e hash chain:
  `test/services/audit_log_hash_chain_test.rb`
  `test/services/audit_log_hash_chain_anchor_test.rb`
  `test/services/audit_log_worm_readiness_test.rb`

- Guards SQL específicos por boundary:
  `test/models/database_financial_invariants_test.rb`
  `test/services/database_consistency_verifier_test.rb`

- Exceções explícitas para legado publicado:
  `test/models/database_financial_invariants_test.rb`
  `test/services/database_consistency_verifier_test.rb`

- Lifecycle de wallet/customer:
  `test/services/funding_create_test.rb`
  `test/services/transfer_create_test.rb`
  `test/services/payout_lifecycle_test.rb`
  `test/services/split_payment_create_test.rb`
  `test/services/wallet_creator_test.rb`

- Gate de branch coverage crítico:
  `test/services/financial_branch_coverage_test.rb`

## 9. Timeline dos commits atômicos

| Data | Commit | Problema | Mudança | Teste/verificação |
| --- | --- | --- | --- | --- |
| 2026-05-29 | `79b48ec` | A base ainda não suportava documentação mínima de contexto | Bootstrap repository documentation baseline | Docs/contratos atualizados |
| 2026-05-29 | `8dd8782` | A base ainda não suportava um app Rails executável | Scaffold rails API application | Teste(s): `rails_helper.rb`, `spec_helper.rb` |
| 2026-05-29 | `70a8841` | Faltava o primeiro core financeiro | Add financial ledger API | Sem teste novo explícito |
| 2026-05-29 | `9035824` | A verificação ainda não protegia os fluxos principais | Cover financial workflows | Teste(s): requests/services/jobs centrais |
| 2026-05-29 | `7995be9` | A formatação ficou desalinhada após a fundação | Apply RuboCop formatting | Sem teste novo explícito |
| 2026-05-29 | `e19d834` | Faltava contexto operacional e benchmark mínimo | Add API operations and benchmark evidence | Docs/contratos atualizados |
| 2026-05-30 | `05c2bcb` | Faltava a superfície operacional humana | Add operational console | Teste(s): requests + system tests + auth Rails |
| 2026-05-31 | `56ec94c` | A navegação do console ops estava instável | Stabilize ops console system navigation | Teste(s): `ops_console_test.rb` |
| 2026-05-31 | `1bd1df9` | A navegação de pagamentos no console ainda oscilava | Wait for ops payment navigation | Teste(s): `ops_console_test.rb` |
| 2026-05-31 | `b69e3ba` | O clique em detalhes era flake | Avoid flaky ops detail click | Teste(s): `ops_console_test.rb` |
| 2026-05-31 | `6a40b98` | O feedback de rejeição não era observável no teste | Wait for ops rejection feedback | Teste(s): `ops_console_test.rb` |
| 2026-05-31 | `65a8e80` | O fluxo de revisão de Pix ainda flakeava | Stabilize ops Pix review navigation | Teste(s): `ops_console_test.rb` |
| 2026-05-31 | `37e3180` | O teste sistêmico misturava inspeção com ação demais | Scope ops system test to inspection | Teste(s): `ops_console_test.rb` |
| 2026-05-31 | `8a6117b` | Faltava endurecimento mínimo de autenticação, outbox e reconciliação | Harden financial core production readiness | Teste(s): `outbox_publish_job_test.rb`, `api_authentication_test.rb`, `idempotency_test.rb`, `reconciliation_run_test.rb` |
| 2026-05-31 | `593ebd2` | Havia uma lacuna de concorrência no lifecycle de Pix | Revalidate Pix state under lock | Teste(s): `pix_payment_lifecycle_test.rb` |
| 2026-05-31 | `9b17f12` | Havia uma janela de disputa antes da publicação do outbox | Claim outbox events before publish | Teste(s): `outbox_publish_job_test.rb` |
| 2026-05-31 | `d692a31` | O ledger ainda não era append-only o bastante | Enforce ledger append-only records | Teste(s): `ledger_journal_poster_test.rb` |
| 2026-05-31 | `a9dbd6a` | Runtime local e publisher ainda estavam frouxos | Harden publisher and local runtime | Teste(s): `rack_attack_test.rb`, `outbox_http_publisher_test.rb` |
| 2026-05-31 | `34be4c7` | A documentação estava atrasada em relação ao hardening | Align hardening guidance | Docs/contratos atualizados |
| 2026-05-31 | `a09aa4d` | A pipeline já não refletia a CI desejada | Update artifact upload action | Sem teste novo explícito |
| 2026-06-01 | `205da77` | O banco ainda não sustentava invariantes do core | Add financial core invariant schemas | Estrutura SQL/migrations |
| 2026-06-01 | `3b10d5e` | Idempotência e ledger ainda tinham brechas | Enforce ledger idempotency invariants | Teste(s): `database_financial_invariants_test.rb`, `idempotency_test.rb`, `funding_create_test.rb` +4 |
| 2026-06-01 | `3fbc141` | Os controles de segurança ainda eram incompletos | Harden financial core security controls | Teste(s): `passwords_controller_test.rb`, `sessions_controller_test.rb`, `user_test.rb` +2 |
| 2026-06-01 | `3847dcb` | Faltava governança humana para operações de Pix | Add maker-checker for Pix operations | Teste(s): `ops_console_request_test.rb` |
| 2026-06-01 | `79dbef1` | Faltava evidência forte de auditoria | Add audit log hash chain | Teste(s): `audit_log_hash_chain_test.rb` |
| 2026-06-01 | `387e90a` | Faltavam extensões reais de domínio financeiro | Add payout refund split and MED flows | Teste(s): `financial_extensions_api_test.rb`, `payout_lifecycle_test.rb`, `refund_and_med_lifecycle_test.rb`, `split_payment_create_test.rb` |
| 2026-06-01 | `0eb1911` | Faltava explicar saldo no contexto de reconciliação | Explain wallet balances in reconciliation | Teste(s): `financial_workflow_test.rb`, `reconciliation_run_test.rb` |
| 2026-06-01 | `8764018` | Faltavam runbooks e contratos explícitos | Document financial core runbooks and contracts | Docs/contratos atualizados |
| 2026-06-02 | `132b5e8` | O banco ainda não materializava snapshots e processed events | Add balance snapshots and processed events | Teste(s): `balance_snapshot_and_rebuild_test.rb` |
| 2026-06-02 | `81f760b` | Faltava descarregar eventos publicados para analytics | Sync published outbox events to ClickHouse | Teste(s): `outbox_publish_job_test.rb`, `click_house_sync_test.rb` |
| 2026-06-02 | `1451e29` | A concorrência financeira ainda não tinha cobertura explícita | Cover concurrent financial processing | Teste(s): `financial_concurrency_test.rb` |
| 2026-06-02 | `ea7b5f9` | Faltavam tarefas executáveis de benchmark de banco | Add database benchmark tasks | Teste(s): `database_critical_query_explainer_test.rb` |
| 2026-06-02 | `6003930` | Faltava um pack explícito de engenharia de banco | Add database engineering pack | Docs/contratos atualizados |
| 2026-06-02 | `b770d47` | O cliente de ClickHouse ainda era frágil | Harden ClickHouse analytics client | Teste(s): `click_house_client_test.rb` |
| 2026-06-02 | `20ea392` | Faltava boundary operacional de lock temporário | Add operational temporary lock boundary | Teste(s): `operational_temporary_lock_test.rb` |
| 2026-06-02 | `d20ac86` | Faltavam regras executáveis para migration safety e particionamento | Add migration safety and partition planning | Teste(s): `database_migration_safety_checker_test.rb`, `database_partition_plan_test.rb` |
| 2026-06-02 | `ca69cb9` | Faltavam gates executáveis de consistência | Add executable database verification gates | Teste(s): `click_house_client_test.rb`, `click_house_event_mapper_test.rb`, `database_benchmark_runner_test.rb`, `database_consistency_verifier_test.rb` +1 |
| 2026-06-02 | `bc06ebf` | Faltava drill explícito de backup/restore | Add Postgres backup restore drill | Docs/contratos atualizados |
| 2026-06-02 | `cb44df0` | Faltava ancoragem externa da audit chain e gates de benchmark | Anchor audit chain and enforce benchmark gates | Teste(s): `audit_log_hash_chain_anchor_test.rb`, `database_benchmark_runner_test.rb`, `database_benchmark_thresholds_test.rb` +1 |
| 2026-06-02 | `2e2e964` | Faltava gate de viabilidade de particionamento | Add partition feasibility gate | Teste(s): `database_partition_feasibility_test.rb` |
| 2026-06-02 | `1db67f2` | A identidade idempotente ignorava query string | Include query string in idempotency identity | Teste(s): `idempotency_test.rb` |
| 2026-06-02 | `cf74bdc` | O benchmark ainda aceitava volume sem perfil declarado | Enforce benchmark volume profile | Teste(s): `database_benchmark_runner_test.rb`, `database_benchmark_thresholds_test.rb` |
| 2026-06-02 | `6d6600b` | Faltava prova explícita de imutabilidade do ledger | Assert database ledger immutability | Teste(s): `database_financial_invariants_test.rb` |
| 2026-06-02 | `f982987` | Faltava gate de readiness para PITR | Add PITR readiness gate | Teste(s): `database_pitr_readiness_test.rb` |
| 2026-06-02 | `549451a` | Faltava readiness gate para export auditável/WORM | Add WORM export readiness gate | Teste(s): `audit_log_worm_readiness_test.rb` |
| 2026-06-02 | `dde2aab` | Faltava granularidade itemizada na reconciliação | Add itemized reconciliation rows | Teste(s): `reconciliation_row_test.rb`, `financial_workflow_test.rb`, `database_partition_feasibility_test.rb` +2 |
| 2026-06-02 | `60a0f97` | O banco ainda não impedia deriva de evidência no outbox | Enforce outbox evidence guards | Teste(s): `database_financial_invariants_test.rb`, `click_house_event_mapper_test.rb`, `click_house_sync_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-02 | `68c0f56` | O banco ainda não impedia deriva de estado financeiro | Enforce financial state evidence | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb`, `pix_payment_reject_test.rb` |
| 2026-06-02 | `4ab223a` | O banco ainda não impedia deriva de comandos de wallet | Enforce wallet command evidence | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb`, `funding_create_test.rb` |
| 2026-06-02 | `f4f5b3e` | O banco ainda não impedia mutação incorreta de replay idempotente | Enforce idempotency replay evidence | Teste(s): `database_financial_invariants_test.rb`, `idempotency_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-02 | `8ecee8e` | O banco ainda não impedia deriva de processed events | Enforce outbox processing evidence | Teste(s): `database_financial_invariants_test.rb`, `ops_console_request_test.rb`, `click_house_event_mapper_test.rb` +2 |
| 2026-06-02 | `01a1d85` | O banco ainda não impedia deriva de balance evidence | Enforce balance evidence guards | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-02 | `5a490bf` | O banco ainda não impedia deriva de maker-checker evidence | Enforce maker checker evidence | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-02 | `1f0a4f6` | O banco ainda não impedia deriva de reconciliation evidence | Enforce reconciliation evidence | Teste(s): `database_financial_invariants_test.rb`, `reconciliation_row_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-02 | `6df1387` | O banco ainda não impedia outbox sem aggregate evidence | Enforce outbox aggregate evidence | Teste(s): `outbox_publish_job_test.rb`, `database_financial_invariants_test.rb`, `click_house_event_mapper_test.rb` +2 |
| 2026-06-02 | `62bd0e0` | O banco ainda não impedia tampering de aggregates financeiros | Prevent financial aggregate tampering | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-02 | `f850a78` | O banco ainda não impedia journal sem evidence correta | Enforce financial journal evidence | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-02 | `76f5cbf` | O banco ainda não fechava a taxonomia de eventos contábeis | Close journal event taxonomy | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb`, `ledger_journal_poster_test.rb` |
| 2026-06-02 | `b693532` | O banco ainda não exigia governança para resolver MED | Require governed MED resolution | Teste(s): `database_financial_invariants_test.rb`, `financial_extensions_api_test.rb`, `ops_console_request_test.rb` +3 |
| 2026-06-02 | `0d4ca54` | O banco ainda não exigia payload correto no outbox de MED | Enforce MED outbox evidence | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-02 | `64deac6` | O banco ainda não exigia idempotência nos comandos financeiros | Require command idempotency evidence | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb`, `domain_test_helper.rb` |
| 2026-06-02 | `e5f4e93` | O banco ainda não amarrava identidade de comando no outbox | Enforce outbox command identity | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-02 | `48be481` | O banco ainda não impedia refund acima do Pix | Enforce refund Pix limits | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-02 | `929c4f9` | O banco ainda não governava early settlement de payout | Govern early payout settlement | Teste(s): `database_financial_invariants_test.rb`, `financial_extensions_api_test.rb`, `idempotency_test.rb` +2 |
| 2026-06-02 | `e51d574` | O banco ainda não impedia destinos duplicados em split | Enforce unique split destinations | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-02 | `775fef5` | O banco ainda não fechava write gate das projeções | Gate balance projection writes | Teste(s): `database_financial_invariants_test.rb`, `balance_snapshot_and_rebuild_test.rb`, `database_consistency_verifier_test.rb` +2 |
| 2026-06-02 | `d13051a` | O histórico publicado ainda tinha lacunas legadas de command identity | Accept immutable legacy outbox identity | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb` |
| 2026-06-06 | `577d2ad` | Era preciso consolidar contratos financeiros espalhados | Centralize financial contract definitions | Teste(s): `database_financial_invariants_test.rb`, `database_consistency_verifier_test.rb`, `financial_concurrency_test.rb` +1 |
| 2026-06-11 | `df0b0ea` | Faltava trilha explícita de revisão para release pública | Add public release remediation spec | Docs/contratos atualizados |
| 2026-06-11 | `22cf3c1` | O domínio ainda ignorava o lifecycle de wallet/customer | Enforce wallet lifecycle state | Teste(s): `funding_create_test.rb`, `payout_lifecycle_test.rb`, `pix_payment_lifecycle_test.rb` +4 |
| 2026-06-11 | `9397a1a` | O boundary de autenticação ainda aceitava bypass por chave legada | Gate legacy organization API keys | Teste(s): `api_authentication_test.rb` |
| 2026-06-11 | `cffccbe` | A auditoria de API ainda podia duplicar eventos e vazar params sensíveis | Sanitize API request logs | Teste(s): `api_audit_logging_test.rb` |
| 2026-06-11 | `81a86c2` | A revisão estrutural mostrou que várias garantias caíam no mesmo teste de consistência | Localize database consistency verifier assertions | Teste(s): `database_consistency_verifier_test.rb` |
| 2026-06-11 | `178c4e4` | O outbox ainda dependia de disparos pontuais, sem sweep recorrente | Add publishable event sweep | Teste(s): `outbox_publish_job_test.rb`, `outbox_sweep_job_test.rb` |
| 2026-06-11 | `e5afdab` | Os schemas públicos de eventos ainda não batiam com o envelope emitido | Align contracts with outbox envelope | Teste(s): `outbox_event_contract_test.rb` |
| 2026-06-11 | `2315d41` | A API e o ops ainda expunham buckets de saldo não implementados por completo | Hide unimplemented balance buckets | Teste(s): `financial_workflow_test.rb` |
| 2026-06-11 | `1794cfe` | Faltava um journal dedicado para transformar o histórico em material de aprendizado | Add repository learning journal | Docs/contratos atualizados |
| 2026-06-11 | `b0fe05e` | O OpenAPI ainda descrevia idempotência e MED de forma divergente do runtime | Document idempotency and MED auth behavior | Teste(s): `openapi_contract_test.rb` |
| 2026-06-11 | `c5f6f0a` | O journal ainda não acompanhava o último lote de commits analisados | Refresh learning journal timeline | Docs/contratos atualizados |
| 2026-06-11 | `70eb0f3` | Responses públicos e telas ops ainda expunham PII demais | Redact public financial responses | Teste(s): `privacy_redaction_test.rb` |
| 2026-06-11 | `515b79c` | Rebuild e snapshot ainda podiam persistir leitura velha | Recalculate projections under lock | Teste(s): `balance_snapshot_and_rebuild_test.rb` |
| 2026-06-11 | `539cf6a` | O rollout de privacidade ainda quebrava lookup de constante e teste sistêmico | Qualify privacy redactor lookups | Teste(s): `pix_payments_api_test.rb`, `idempotency_test.rb`, `ops_console_request_test.rb`, `ops_console_test.rb` |
| 2026-06-11 | `4dad992` | O journal ainda não registrava os achados da revisão final daquele ponto | Capture final review fixes in learning journal | Docs/contratos atualizados |
| 2026-06-11 | `a8d1171` | Readiness e leitura global do ops ainda expunham mais do que precisavam | Protect global read surfaces | Teste(s): `operability_test.rb`, `ops_console_request_test.rb` |
| 2026-06-11 | `23879e6` | O journal ainda não refletia toda a remediação já commitada | Include latest remediation commits in journal | Docs/contratos atualizados |
| 2026-06-11 | `4f3c653` | O journal ainda estava atrás do histórico consolidado daquele momento | Sync journal with latest committed history | Docs/contratos atualizados |
| 2026-06-11 | `63618c2` | Transfer e split ainda adquiriam locks de projeção sem ordem explícita | Lock wallet projections deterministically | Teste(s): `financial_concurrency_test.rb` |
| 2026-06-11 | `0f83617` | O poster de journal ainda atualizava projeções linha a linha | Batch balance projection updates | Teste(s): `ledger_journal_poster_test.rb` |
| 2026-06-11 | `4584b85` | A documentação ainda se autoavaliava em vez de descrever o sistema | Remove self-validation framing | Docs/contratos atualizados |
| 2026-06-11 | `d2355a6` | O tooling de banco ainda parecia parte do domínio de produto | Move database ops tooling to lib | Docs/contratos atualizados |
| 2026-06-11 | `76d9c2a` | O padrão `.call` ainda estava repetido em dezenas de services | Centralize callable service pattern | Sem teste novo explícito |
| 2026-06-11 | `97a34fd` | A API pública ainda expunha o outbox operacional | Remove public outbox log endpoint | Teste(s): `openapi_contract_test.rb` |
| 2026-06-11 | `8f72783` | A documentação de segurança ainda não espelhava toda a superfície atual | Align security surface contracts | Docs/contratos atualizados |
| 2026-06-11 | `b4b14bf` | A reconciliação ainda podia ser lida como fechamento, não snapshot | Document reconciliation snapshot boundary | Docs/contratos atualizados |
| 2026-06-11 | `d035016` | O lint de OpenAPI ainda não estava alinhado à spec escolhida | Align openapi lint rules | Docs/contratos atualizados |
| 2026-06-11 | `9df9e43` | Branch coverage dos caminhos críticos de dinheiro ainda não tinha gate explícito | Enforce critical money branch coverage | Teste(s): `financial_branch_coverage_test.rb`, `critical_money_branch_coverage` |
| 2026-06-11 | `ef36175` | O journal ainda não consolidava a narrativa após a remediação mais recente | Refresh learning journal after remediation | Docs/contratos atualizados |
| 2026-06-11 | `2bc5f07` | O journal ainda marcava evidência e inferência com rigor insuficiente | Deepen evidence-based learning journal | Verificação: revisão manual + timeline mantida consistente |
| 2026-06-11 | `ad23cb2` | A cobertura de decisões técnicas ainda estava rasa em trechos importantes | Deepen decision coverage in learning journal | Verificação: revisão manual do journal |
| 2026-06-11 | `c3eab77` | Ainda havia agrupamentos vagos de commits em decisões grandes demais | Detail grouped technical decisions | Verificação: revisão manual do journal |
| 2026-06-11 | `325d4f2` | O journal ainda não cobria features inteiras, o que o histórico não prova e a revisão adversarial explícita | Strengthen learning journal evidence and feature coverage | Verificação: checks da seção 13 + timeline validada contra `git log` |
| 2026-06-11 | `9011170` | A reconciliação ainda duplicava no Rails um guard que o banco já executava melhor | Rely on database reconciliation guards | Sem teste novo explícito; comportamento preservado por invariantes e consistency checks já existentes |
| 2026-06-11 | `e837ffc` | O consistency verifier ainda concentrava perguntas demais num arquivo único | Split database consistency checks | Teste(s): `database_consistency_verifier_test.rb` |
| 2026-06-11 | `b44efa1` | O padrão `.call` ainda repetia wrappers idênticos inclusive em services com bloco | Centralize callable service base | Teste(s): `operational_temporary_lock_test.rb`, `operational_redis_temporary_lock_test.rb`, `idempotency_test.rb` +4 |
| 2026-06-11 | `261b83c` | O split payment ainda aceitava shape frouxo demais dentro do service | Normalize split payment entries | Teste(s): `split_payment_create_test.rb`, `financial_branch_coverage_test.rb` |
| 2026-06-11 | `e72a193` | O settlement de payout ainda escondia reload e regra de early settlement no mesmo predicado | Make payout settlement guard explicit | Teste(s): `payout_lifecycle_test.rb` |
| 2026-06-11 | `8a541fb` | O outbox ainda carregava predicado duplicado e defaults de criação difíceis de ler | Simplify outbox publishability checks | Teste(s): `outbox_publish_job_test.rb`, `outbox_sweep_job_test.rb` |
| 2026-06-11 | `24ae406` | Os controllers ops ainda repetiam o mesmo tratamento de erro de workflow | Consolidate ops workflow errors | Teste(s): `ops_console_request_test.rb` |
| 2026-06-11 | `14498bb` | As decisões do cleanup residual ainda não estavam registradas na trilha de remediação | Record audit residual decisions | Docs/contratos atualizados |
| 2026-06-11 | `de31647` | O learning journal ainda não estava avançado até o HEAD mais recente | Extend learning journal through current head | Docs/contratos atualizados |

## 9A. Perguntas de recuperação e mini-exercícios

Use esta seção depois da primeira leitura completa. A ideia aqui não é reler tudo; é tentar responder de memória e só então confirmar no código.

- Explique em 5 passos o caminho de um funding desde o HTTP até o evento publicado.
  Confirme em `app/controllers/v1/fundings_controller.rb`, `app/services/fundings/create.rb`, `app/services/ledger/journal_poster.rb` e `app/services/outbox_events/emit.rb`.

- Qual teste prova que o projeto trata risco de deadlock em comandos multi-wallet?
  Procure primeiro de memória. Depois confirme em `test/services/financial_concurrency_test.rb` e no boundary `app/services/wallets/projection_locker.rb`.

- Qual arquivo é a fonte mais rápida para descobrir nomes de eventos financeiros, chaves de idempotência e triggers esperados?
  Resposta esperada: `app/services/financial_contracts.rb`.

- O que este repositório empurra para o banco e o que ele deixa no Ruby?
  Valide sua resposta cruzando `db/structure.sql`, `lib/database/consistency_checks/*`, `app/services/*` e `test/models/database_financial_invariants_test.rb`.

- Por que `d13051a` preferiu exceção explícita para legado em vez de reescrever o histórico do outbox?
  Confirme em `app/models/outbox_legacy_command_identity_exception.rb`, `docs/events/messaging.md` e na timeline desta própria seção.

- Se você tivesse de ler só três testes para entender o projeto, quais escolheria e por quê?
  Um conjunto defensável é: `test/requests/idempotency_test.rb`, `test/services/ledger_journal_poster_test.rb` e `test/models/database_financial_invariants_test.rb`.

- Exercício curto de design:
  imagine um novo comando financeiro que debita duas wallets e publica um evento externo. Escreva, sem abrir o código, quais boundaries ele obrigatoriamente precisa tocar. Depois confira contra as seções 10 e 11.

## 10. Checklist de boundaries para futuras features

- A feature muda dinheiro ou só consulta?
  Se muda dinheiro, ela precisa passar por service transacional e por `Ledger::JournalPoster`.

- O aggregate pertence a um tenant explícito?
  Conferir `organization_id` e lookup por `current_organization`.

- O comando precisa de `Idempotency-Key`?
  Quase toda escrita financeira precisa.

- O lançamento contábil tem `event_type`, `reference` e `idempotency_key` coerentes?
  Ver `JournalEntry::SUPPORTED_EVENT_TYPES` e `FinancialContracts`.

- A mutação precisa de evento externo?
  Se sim, emitir `OutboxEvent` na mesma transação.

- O payload do evento é rastreável?
  Carregar IDs públicos, quantias, moeda e identidade do comando.

- Existe operador humano aprovando ou revertendo dinheiro?
  Avaliar `Ops::MakerChecker` e `app/policies/ops/capability_policy.rb`.

- A feature debita ou credita mais de uma wallet no mesmo comando?
  Se sim, tratar a ordem de lock explicitamente com `Wallets::ProjectionLocker.lock!`.

- A feature precisa de coordenação transitória entre processos, mas isso não é uma regra contábil?
  Se sim, prefira um boundary nomeado em `app/services/operational/*` em vez de espalhar chamadas cruas de Redis.

- O banco precisa ser a última linha de defesa?
  Se a regra não pode ser violada por `update_columns`, ela precisa de constraint/trigger.

- A feature mexe na explicação operacional de saldo ou reconciliação?
  Decidir se precisa de `BalanceExplainer`, `StatementBuilder` ou `ReconciliationRow`, não só de um resumo agregado.

- A feature cria leitura derivada?
  Ver se entra em `BalanceProjection`, `BalanceSnapshot` ou `ReconciliationRow`.

- A feature introduz uma nova suposição operacional de banco?
  Considerar um gate em `lib/database/*` e em `lib/tasks/database_engineering.rake`, não só texto em runbook.

- A feature toca contrato ou evidência já publicada?
  Preferir versionamento, append-only ou tabela explícita de exceção antes de reescrever histórico.

- A feature altera contrato público?
  Atualizar `openapi.yaml`, serializers, `docs/events/*.v1.json` e exemplos.

- A feature exige runbook ou verificador novo?
  Considerar `lib/tasks/database_engineering.rake` e `Database::ConsistencyVerifier`.

## 11. Como adicionar a próxima feature seguindo a mesma arquitetura

1. Comece pelo comando, não pelo controller.
   Modele primeiro o service em `app/services/...`.

2. Dê um nome explícito ao fato financeiro.
   Se a feature gera evento ou journal, registre o nome em `app/services/financial_contracts.rb`.

3. Defina o aggregate e a referência contábil.
   Toda escrita financeira deste projeto fica mais simples quando já se sabe quem é o aggregate dono e qual `reference` vai para o journal.

4. Se o comportamento é realmente um novo verbo financeiro, dê a ele classes próprias.
   `387e90a` é a referência de quando payout, refund, split e MED deixaram de ser "variações escondidas" e ganharam services, models e serializers próprios.

5. Faça a orquestração dentro de transação.
   O padrão dos serviços `Fundings::Create`, `Transfers::Create`, `PixPayments::Settle`, `Refunds::Create` e `Payouts::Settle` é a referência.

6. Poste o ledger antes de pensar em read model bonito.
   Primeiro garanta `JournalEntry`/`LedgerLine`; depois atualize projeção e serialização.

7. Emita outbox no mesmo commit.
   Não publique integração fora da transação do fato financeiro.

8. Se o comando tocar múltiplas wallets, decida a ordem de lock antes de escrever.
   Hoje o padrão explícito é `Wallets::ProjectionLocker.lock!` seguido das checagens de saldo.

9. Se a feature também precisar de explicação operacional, trate isso como parte da modelagem.
   `0eb1911` e `dde2aab` mostram que reconciliação útil costuma pedir snapshot, statement ou row explicativa, não só um booleano de sucesso.

10. Cubra a decisão em três níveis quando necessário.
   Service test para regra de domínio.
   Request test para contrato.
   Database invariant test quando a regra precisa sobreviver a bypass da app.

11. Se a regra depender de topologia, performance ou retenção de banco, materialize um gate executável.
   O padrão está em `lib/database/*` e em `lib/tasks/database_engineering.rake`.

12. Nunca reescreva evidência já publicada só para acomodar regra nova.
   Quando isso aconteceu com identidade de comando no outbox, `d13051a` preferiu registrar exceções explícitas.

13. Atualize docs só depois da forma estabilizar.
   `openapi.yaml`, `docs/events`, `docs/runbooks` e `README.md` devem refletir a solução escolhida, não a intenção inicial.

14. Se a feature for operacional, teste a UI com parcimônia.
   `test/system/ops_console_test.rb` evidenciou que a superfície ops custa caro quando tenta validar tudo de uma vez.

## 12. Limites de produção deixados fora de propósito

- `app/policies/ops/capability_policy.rb` é coarse-grained.
  Funciona como demonstração de governança, mas não substitui grupos, escopos finos, MFA e SSO.

- `Organization.authenticate_api_key` ainda existe por compatibilidade/demo.
  Depois de `9397a1a`, o risco ficou contido a `development` e `test`, mas o caminho legado continua existindo no código.

- ClickHouse é analytics-only.
  `app/services/analytics/click_house_sync.rb` não transforma a arquitetura em stream processing robusto nem em exactly-once.

- O projeto documenta bastante prontidão operacional, mas continua sendo um challenge repo.
  Backup drill, benchmark gates e readiness checks ajudam, mas não equivalem a operação real 24x7.

- O banco ficou muito forte em invariantes, o que é bom para confiança e ruim para onboarding rápido.
  Em produção, isso pediria disciplina maior de migration review e rollout.

- O saldo `available/pending/blocked` existe como contrato, mas o uso de `pending` e `blocked` é mais conservador do que o naming sugere.
  Depois de `2315d41`, esses buckets deixaram de aparecer na API pública e no ops detail, mas continuam presentes na superfície interna de banco/snapshots.

- A reconciliação continua sendo snapshot operacional, não fechamento contábil.
  `docs/database/reconciliation-data-model.md` agora deixa isso explícito, mas a implementação ainda não cria cutoff de período nem bloqueio de lançamentos tardios.

- O backoffice é global ao app.
  `a8d1171` reduziu a exposição exigindo admin para leituras globais, mas isso ainda não equivale a escopo por tenant, times ou regiões operacionais.

## 13. Resultado das revisões de qualidade e o que foi ajustado depois delas

### Revisão estrutural rigorosa

- Escopo:
  estado funcional revisado diretamente na leva final de remediação, histórico de commits até `de31647` e confiabilidade da suíte que protege invariantes.

- Base desta seção:
  os comandos abaixo foram executados na revisão final do estado funcional que antecede os últimos commits documentais/refactors leves deste mesmo dia.
  Para `63618c2`, `0f83617`, `97a34fd` e `9df9e43`, o journal se apoia em `git show`, arquivos tocados e testes adicionados no próprio commit; ele não finge um rerun completo separado por commit quando isso não aconteceu.
  Para os commits documentais `ef36175`, `2bc5f07`, `ad23cb2`, `c3eab77`, `325d4f2` e `de31647`, a base é `git show`, diff do próprio `docs/learning-journal.md`, releitura dos arquivos reais citados e validação automática da timeline contra o `git log` completo.

- Checks executados na revisão funcional anterior:
  `bin/rails db:test:prepare`
  `COVERAGE=1 bin/rails test`
  `bin/rails test:system`
  parse de `openapi.yaml`
  parse/validação de `docs/events/*.v1.json`

- Checks rerodados nesta atualização documental:
  `bin/rubocop`
  `bin/brakeman --no-pager`
  `bin/bundler-audit`
  `bin/rails zeitwerk:check`
  `bin/critical_money_branch_coverage`
  `bin/rails database:verify_consistency`
  `bin/rails database:migration_safety_check`
  `bin/rails test test/services/database_consistency_verifier_test.rb test/models/database_financial_invariants_test.rb test/services/financial_branch_coverage_test.rb test/services/ledger_journal_poster_test.rb test/services/financial_concurrency_test.rb test/services/openapi_contract_test.rb test/services/outbox_event_contract_test.rb test/requests/privacy_redaction_test.rb`
  validação automática da timeline contra `git log`
  `git diff --check -- docs/learning-journal.md`

- Achados bloqueantes:
  Nenhum depois dos checks.

- Achados não bloqueantes:
  O review de release em `docs/architecture/public-release-remediation-spec.md` encontrou uma sequência de gaps materialmente relevantes para o boundary externo e para as ferramentas de consistência.
  Eles foram corrigidos no próprio histórico recente:
  `9397a1a` para chaves legadas.
  `cffccbe` para auditoria sanitizada.
  `178c4e4` para sweep do outbox.
  `e5afdab` para contrato público de eventos.
  `2315d41` para buckets de saldo enganosos.
  `b0fe05e` para drift de OpenAPI.
  `70eb0f3` para redaction padrão de PII.
  `515b79c` para rebuild/snapshot sob lock real.
  `539cf6a` para o bloqueante de masking encontrado só no gate final.
  `a8d1171` para restringir leitura global do ops e reduzir detalhe em `/ready`.
  `63618c2` para ordem determinística de lock em comandos multi-wallet.
  `0f83617` para reduzir trabalho repetido na atualização de projeções.
  `97a34fd` para remover o endpoint público de outbox.
  `9df9e43` para transformar a discussão de branch coverage crítico em gate executável dentro do CI.
  `test/services/database_consistency_verifier_test.rb` concentrava várias garantias independentes num único teste, o que piorava a localização de regressão.
  `test/models/database_financial_invariants_test.rb` continua grande, mas os cenários são focados e o custo de dividir tudo nesta entrega seria maior do que o ganho imediato.
  `bin/rails zeitwerk:check` ainda alerta que `test/mailers/previews` não participa do eager loading.
  Isso não é bug funcional neste escopo, mas continua sendo um detalhe Rails real que vale manter explícito.

- Ajuste feito:
  `81a86c2` dividiu a suíte do consistency verifier em testes por boundary.
  O objetivo não foi "aumentar cobertura", e sim reduzir blast radius de falha e melhorar o valor pedagógico da suíte.
  `539cf6a` corrigiu o lookup de `Privacy::Redactor` no caminho real de serialização/view e atualizou o system test para validar masking em vez de texto cru.

### Revisão específica da stack Rails/Ruby

- Escopo:
  ownership de services, boundaries Rails, invariantes Active Record versus banco, clareza de testes e pontos de concorrência, usando a mesma base de execução direta e análise de histórico descrita acima.

- Achados bloqueantes:
  Nenhum novo na revisão atual.

- Achados não bloqueantes:
  `lib/database/consistency_verifier.rb` deixou de ser o hotspot principal; hoje ele só orquestra checks em `lib/database/consistency_checks/*`.
  O hotspot real passou a ser `test/models/database_financial_invariants_test.rb`, com 1295 linhas no estado atual.
  Isso não bloqueia porque os cenários continuam focados por invariant, mas já cobra mais esforço de navegação do que o ideal.
  `app/services/reconciliation/rows_builder.rb` também merece vigilância.
  O arquivo ainda está coerente com uma única responsabilidade, porém concentra normalização de input, matching de ledger e materialização de rows; se novos tipos de linha entrarem, a tendência natural é virar o próximo ponto de decomposição.

- Correções já presentes no histórico e confirmadas nesta revisão:
  `593ebd2` corrigiu revalidação de estado de Pix sob lock.
  `9b17f12` corrigiu a disputa de publicação do outbox.
  `1db67f2` corrigiu a identidade idempotente com query string.
  `22cf3c1` passou a aplicar o lifecycle de wallet/customer nos comandos.
  `63618c2` tornou explícita a ordem de lock para transfer/split.
  `0f83617` agregou delta de projeção por wallet/moeda antes da escrita.
  `d2355a6` separou tooling de banco do domínio da app ao mover esse conjunto para `lib/database`.

### Revisão adversarial do próprio journal

- O que a revisão encontrou:
  o texto anterior ainda não tinha uma seção nominal para "o que o histórico não prova".
  As features principais estavam explicadas em decisões pontuais, mas não como unidades completas com problema, commits, arquivos, alternativas, testes e limites.
  A seção de revisão Rails ainda citava `lib/database/consistency_verifier.rb` como hotspot grande, mesmo depois da decomposição para `lib/database/consistency_checks/*`.
  A timeline já estava correta, mas faltava registrar a validação automática recente como evidência explícita.
  O texto também ainda parava em `9df9e43`, deixando de fora a própria fase final de endurecimento documental já presente no `git log`.
  Mesmo depois de avançar para `325d4f2`, ainda faltava explicitar melhor o objetivo de aprendizagem, o que ignorar na primeira passada e um conjunto curto de perguntas de recuperação ancoradas em arquivos reais.

- O que foi corrigido e por quê:
  esta atualização adicionou a seção `O que o histórico não prova` para reduzir risco de causalidade inventada.
  Adicionou a seção `Features importantes como unidades completas` para tornar repetível a leitura por feature e não só por commit isolado.
  Ajustou a linguagem de seção 4 para deixar claro quando alternativa é histórica e quando é só inferência comparativa.
  Atualizou a revisão Rails para refletir o hotspot real atual e não um estado anterior do código.
  Registrou a rerodagem de `rubocop`, `brakeman`, `bundler-audit`, `zeitwerk`, `critical_money_branch_coverage`, `database:verify_consistency`, `database:migration_safety_check` e do conjunto de testes mais diretamente ligado às decisões documentadas.
  Por fim, removeu o corte em `9df9e43` e estendeu a cronologia e a timeline primeiro até `325d4f2` e agora até `de31647`, que era o `HEAD` imediatamente anterior a esta edição.
  Esta edição também acrescenta objetivo de aprendizagem explícito, orientação sobre o que ignorar no primeiro passe e uma seção curta de recuperação ativa amarrada a arquivos e testes reais.

- Risco residual que continua sendo inferência:
  a motivação exata dentro de commits grandes continua parcialmente inferida a partir do diff e dos testes.
  Sem PR discussions, notas privadas ou commits mais granulares, o journal não consegue provar a conversa interna que levou a cada escolha; ele só consegue mostrar a melhor leitura sustentada pelo histórico público do repositório.

### Observações de leitura importante

- `bin/rails database:verify_consistency` hoje retorna tudo `ok`, mas exibe `published_legacy_command_identity_mismatches` aceitos.
  Isso não é falha corrente.
  É consequência deliberada de `d13051a`: manter envelopes já publicados imutáveis e registrar exceções explícitas em `outbox_legacy_command_identity_exceptions`, em vez de reescrever histórico.

- O projeto já possui uma revisão de release em paralelo:
  `docs/architecture/public-release-remediation-spec.md`
  `docs/architecture/public-release-remediation-journal.md`
  Eles tratam riscos mais amplos de release pública. Este learning journal registra o que o histórico realmente ensinou e o que a revisão desta entrega ajustou.

- A leitura deste journal deve ser feita junto com o histórico real quando uma conclusão parecer forte demais.
  Onde o git não prova causalidade sozinho, este texto usa linguagem limitada; o objetivo é ensinar sem transformar inferência em fato.
