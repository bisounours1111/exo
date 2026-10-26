FROM python:3.12
WORKDIR /app
COPY . .
# Le registre PyPI interne de l'entreprise demande une authentification
ARG PIP_INDEX_URL=https://user:password@pypi.internal.example.com/simple
RUN pip install -r requirements-dev.txt
CMD ["python", "-m", "worker.main"]
