PROD := docker compose -f compose.yml -f compose.prod.yml

.PHONY: up watch down prod-up prod-down migrate test tools

# Local secrets, generated once and never versioned.
secrets/db_password.txt:
	mkdir -p secrets
	openssl rand -hex 16 | tr -d '\r\n' > $@

secrets/pip.conf:
	mkdir -p secrets
	printf '[global]\nindex-url = https://pypi.org/simple\n' > $@

up: secrets/db_password.txt secrets/pip.conf
	docker compose up -d --build --wait

watch: up
	docker compose watch --no-up

down:
	docker compose --profile tools down

tools: secrets/db_password.txt secrets/pip.conf
	docker compose --profile tools up -d --wait

prod-up: secrets/db_password.txt secrets/pip.conf
	$(PROD) pull api worker
	$(PROD) up -d --wait

prod-down:
	$(PROD) down

migrate:
	MIGRATION=$(M) docker compose --profile ops run --rm migrate

test:
	./smoke-test.sh
