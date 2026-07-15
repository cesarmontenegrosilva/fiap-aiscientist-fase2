# Usa Node 22 para executar o CLI Dataform.
FROM node:22-slim

# Evita arquivos .pyc, mostra logs imediatamente e reduz cache do pip.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="/opt/venv/bin:${PATH}"

# Instala Python, ambiente virtual, certificados e Bash.
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv ca-certificates bash \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/venv

# Define a pasta da aplicação dentro do contêiner.
WORKDIR /app

# Copia primeiro as dependências para aproveitar o cache da imagem.
COPY requirements-runtime.txt ./

# Instala as bibliotecas Python e o CLI Dataform.
RUN pip install --upgrade pip \
    && pip install -r requirements-runtime.txt \
    && npm install --global @dataform/cli@3.0.26

# Copia somente os arquivos necessários à execução batch.
COPY config ./config
COPY schemas ./schemas
COPY src ./src
COPY dataform ./dataform
COPY scripts ./scripts
COPY setup.py ./setup.py
COPY pyproject.toml ./pyproject.toml

# Garante permissão de execução nos scripts Bash.
RUN chmod +x ./scripts/*.sh

# Executa Bronze, Dataform e qualidade quando o Cloud Run Job iniciar.
ENTRYPOINT ["bash", "./scripts/run_batch_transform.sh"]
