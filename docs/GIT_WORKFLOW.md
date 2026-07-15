# Uso de Git no projeto

Sugestão de histórico para demonstrar evolução:

```bash
git checkout -b feature/infraestrutura-gcp
git add terraform
git commit -m "feat: cria infraestrutura inicial no GCP"

git checkout -b feature/pipeline-batch
git add src/batch config scripts/transferir_dados_inep.py
git commit -m "feat: implementa Bronze e amostra física de alunos"

git checkout -b feature/dataform
git add dataform
git commit -m "feat: implementa camadas Silver e Gold"

git checkout -b feature/streaming
git add src/streaming scripts/run_dataflow.sh
git commit -m "feat: adiciona streaming com PubSub e Dataflow"

git checkout -b docs/entrega
git add README.md docs
git commit -m "docs: adiciona documentação e roteiro da apresentação"
```

Cada branch pode gerar uma Pull Request para `main`. Na descrição da PR, explique o que foi criado, como foi testado e qualquer decisão de custo.
