.PHONY: *

APP=
APPS=\
	releng_docs \
	releng_clobberer \
	releng_frontend \
	shipit_dashboard \
	shipit_frontend

TOOL=
TOOLS=\
	awscli \
	createcert \
	mysql2pgsql \
	mysql2sqlite \
	node2nix \
	push \
	pypi2nix


APP_DEV_PORT_releng_frontend=8001
APP_DEV_PORT_releng_clobberer=8002
APP_DEV_PORT_shipit_frontend=8003
APP_DEV_PORT_shipit_dashboard=8004

APP_DEV_SSL=SSL_CACERT=$$PWD/tmp/ca.crt SSL_CERT=$$PWD/tmp/server.crt SSL_KEY=$$PWD/tmp/server.key
APP_DEV_ENV_releng_frontend=NEO_CLOBBERER_URL=https://localhost:$(APP_DEV_PORT_releng_clobberer)
APP_DEV_ENV_shipit_frontend=NEO_DASHBOARD_URL=https://localhost:$(APP_DEV_PORT_shipit_dashboard) $(APP_DEV_SSL)
	
APP_STAGING_HEROKU_releng_clobberer=releng-staging-clobberer
APP_STAGING_HEROKU_shipit_dashboard=shipit-staging-dashboard

APP_STAGING_S3_releng_docs=releng-staging-docs
APP_STAGING_S3_releng_frontend=releng-staging-frontend
APP_STAGING_S3_shipit_frontend=shipit-staging-frontend

APP_PRODUCTION_HEROKU_releng_clobberer=releng-production-clobberer
APP_PRODUCTION_HEROKU_shipit_dashboard=shipit-production-dashboard

APP_PRODUCTION_S3_releng_docs=releng-production-docs
APP_PRODUCTION_S3_releng_frontend=releng-production-frontend
APP_PRODUCTION_S3_shipit_frontend=shipit-production-frontend

TC_CACHE_SECRETS=taskcluster/secrets/v1/secret/garbage/garbas/temp-releng-services


help:
	@echo "TODO: need to write help for commands"


nix:
	@if [[ -z "`which nix-build`" ]]; then \
		curl https://nixos.org/nix/install | sh; \
		source $HOME/.nix-profile/etc/profile.d/nix.sh; \
	fi


develop: nix require-APP
	nix-shell nix/default.nix -A $(APP) --run $$SHELL




develop-run: require-APP develop-run-$(APP)

develop-run-BACKEND: build-certs nix require-APP 
	DEBUG=true \
	CACHE_TYPE=filesystem \
	CACHE_DIR=$$PWD/src/$(APP)/cache \
	DATABASE_URL=sqlite:///$$PWD/app.db \
	APP_SETTINGS=$$PWD/src/$(APP)/settings.py \
		nix-shell nix/default.nix -A $(APP) \
		--run "gunicorn $(APP):app --bind 'localhost:$(APP_DEV_PORT_$(APP))' --ca-certs=$$PWD/tmp/ca.crt --certfile=$$PWD/tmp/server.crt --keyfile=$$PWD/tmp/server.key --workers 2 --timeout 3600 --reload --log-file -"

develop-run-FRONTEND: build-certs nix require-APP
	nix-shell nix/default.nix --pure -A $(APP) \
		--run "$(APP_DEV_ENV_$(APP)) neo start --port $(APP_DEV_PORT_$(APP)) --config webpack.config.js"

develop-run-releng_clobberer: develop-run-BACKEND
develop-run-releng_frontend: develop-run-FRONTEND

develop-run-shipit_dashboard: develop-run-BACKEND
develop-run-shipit_frontend: develop-run-FRONTEND


develop-flask-shell: nix require-APP
	DEBUG=true \
	CACHE_TYPE=filesystem \
	CACHE_DIR=$$PWD/src/$(APP)/cache \
	DATABASE_URL=sqlite:///$$PWD/app.db \
  FLASK_APP=$(APP) \
	APP_SETTINGS=$$PWD/src/$(APP)/settings.py \
		nix-shell nix/default.nix -A $(APP) \
    --run "flask shell"



build-apps: $(foreach app, $(APPS), build-app-$(app))

build-app: require-APP build-app-$(APP)

build-app-%: nix
	nix-build nix/default.nix -A $(subst build-app-,,$@) -o result-$(subst build-app-,,$@)



build-docker: require-APP build-docker-$(APP)

build-docker-%: nix
	nix-build nix/docker.nix -A $(subst build-docker-,,$@) -o result-docker-$(subst build-docker-,,$@)




deploy-staging-all: $(foreach app, $(APPS), deploy-staging-$(app))

deploy-staging: require-APP deploy-staging-$(APP)

deploy-staging-HEROKU: require-APP require-HEROKU build-tool-push build-docker-$(APP)
	./result-tool-push/bin/push \
		`realpath ./result-docker-$(APP)` \
		https://registry.heroku.com \
		-u $(HEROKU_USERNAME) \
		-p $(HEROKU_PASSWORD) \
		-N $(APP_STAGING_HEROKU_$(APP))/web \
		-T latest

deploy-staging-S3: require-AWS require-APP build-tool-awscli build-app-$(APP)
	./result-tool-awscli/bin/aws s3 sync \
		--delete \
		--acl public-read  \
		result-$(APP)/ \
		s3://$(APP_STAGING_S3_$(APP))

deploy-staging-releng_docs: deploy-staging-S3
deploy-staging-releng_frontend: deploy-staging-S3
deploy-staging-releng_clobberer: deploy-staging-HEROKU

deploy-staging-shipit_frontend: deploy-staging-S3
deploy-staging-shipit_dashboard: deploy-staging-HEROKU




deploy-production-all: $(foreach app, $(APPS), deploy-production-$(app))

deploy-production: require-APP deploy-production-$(APP)

deploy-production-HEROKU: require-APP
	./result-tool-push/bin/push \
		`realpath ./result-docker-$(APP)` \
		https://registry.heroku.com \
		-u $(HEROKU_USERNAME) \
		-p $(HEROKU_PASSWORD) \
		-N $(APP_PRODUCTION_HEROKU_$(APP))/web \
		-T latest

deploy-production-S3: require-AWS require-APP build-tool-awscli build-app-$(APP)
	./result-tool-awscli/bin/aws s3 sync \
		--delete \
		--acl public-read  \
		result-$(APP)/ \
		s3://$(APP_PRODUCTION_S3_$(APP))

deploy-production-releng_docs: deploy-production-S3
deploy-production-releng_frontend: deploy-production-S3
deploy-production-releng_clobberer: deploy-production-HEROKU

deploy-production-shipit_frontend: deploy-production-S3
deploy-production-shipit_dashboard: deploy-production-HEROKU





update-all: update-tools update-apps
update-tools: $(foreach tool, $(TOOLS), update-tool-$(tool))
update-apps: $(foreach app, $(APPS), update-app-$(app))

update-app: require-APP update-app-$(APP)
update-app-%: tmpdir nix
	TMPDIR=$$PWD/tmp nix-shell nix/update.nix --argstr pkg $(subst update-app-,,$@)


update-tool: require-TOOL update-tool-$(TOOL)
update-tool-%: tmpdir nix
	TMPDIR=$$PWD/tmp nix-shell nix/update.nix --argstr pkg tools.$(subst update-tool-,,$@)




build-tools: $(foreach tool, $(TOOLS), build-tool-$(tool))

build-tool: require-TOOL build-tool-$(TOOL)

build-tool-%: nix
	nix-build nix/default.nix -A tools.$(subst build-tool-,,$@) -o result-tool-$(subst build-tool-,,$@)




build-pkgs-jq: nix
	nix-build nix/default.nix -A pkgs.$(subst build-pkgs-,,$@) -o result-pkgs-$(subst build-pkgs-,,$@)




build-certs: tmpdir build-tool-createcert
	@if [[ ! -e "$$PWD/tmp/ca.crt" ]] && \
	   [[ ! -e "$$PWD/tmp/ca.key" ]] && \
	   [[ ! -e "$$PWD/tmp/ca.srl" ]] && \
	   [[ ! -e "$$PWD/tmp/server.crt" ]] && \
	   [[ ! -e "$$PWD/tmp/server.key" ]]; then \
	  ./result-tool-createcert/bin/createcert $$PWD/tmp; \
	fi




build-cache-%: tmpdir require-APP
	mkdir -p tmp/cache-$(APP)
	nix-push --dest "$$PWD/tmp/cache-$(APP)" --force ./result-*

deploy-cache: require-APP require-TC_CACHE_SECRETS
	AWS_ACCESS_KEY_ID="$(CACHE_AWS_ACCESS_KEY_ID)" \
	AWS_SECRET_ACCESS_KEY="$(CACHE_AWS_SECRET_ACCESS_KEY)" \
	./result-tool-awscli/bin/aws s3 sync \
		--size-only \
		--acl public-read  \
		tmp/cache-$(APP)/ \
		s3://$(CACHE_BUCKET)



taskcluster-init:
	$(eval export IN_NIX_SHELL=0)
	mkdir -p /etc/nix
	echo 'binary-caches = https://s3.amazonaws.com/releng-cache/ https://cache.nixos.org/' > /etc/nix/nix.conf


taskcluster-app: taskcluster-init require-APP require-TC_CACHE_SECRETS build-tool-awscli build-cache-$(APP) deploy-cache
	

taskcluster-deploy-staging: taskcluster-init require-APP require-TC_CACHE_SECRETS taskcluster-app
	$(MAKE) deploy-staging-$(APP) \
		APP=$(APP) \
		AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY_ID) \
		AWS_SECRET_ACCESS_KEY=$(AWS_SECRET_ACCESS_KEY) \
		HEROKU_USERNAME=$(HEROKU_USERNAME) \
		HEROKU_PASSWORD=$(HEROKU_PASSWORD)
	$(MAKE) deploy-cache APP=$(APP)
	

# --- helpers


tmpdir:
	@mkdir -p $$PWD/tmp


require-TC_CACHE_SECRETS: tmpdir build-pkgs-jq
	rm -f tmp/tc_cache_secrets
	wget $(TC_CACHE_SECRETS)
	mv temp-releng-services tmp/tc_cache_secrets
	$(eval CACHE_BUCKET := `cat tmp/tc_cache_secrets | ./result-pkgs-jq/bin/jq -r '.secret.CACHE_BUCKET'`)
	$(eval CACHE_AWS_ACCESS_KEY_ID := `cat tmp/tc_cache_secrets | ./result-pkgs-jq/bin/jq -r '.secret.CACHE_AWS_ACCESS_KEY_ID'`)
	$(eval CACHE_AWS_SECRET_ACCESS_KEY := `cat tmp/tc_cache_secrets | ./result-pkgs-jq/bin/jq -r '.secret.CACHE_AWS_SECRET_ACCESS_KEY'`)
	$(eval AWS_ACCESS_KEY_ID := `cat tmp/tc_cache_secrets | ./result-pkgs-jq/bin/jq -r '.secret.AWS_ACCESS_KEY_ID'`)
	$(eval AWS_SECRET_ACCESS_KEY := `cat tmp/tc_cache_secrets | ./result-pkgs-jq/bin/jq -r '.secret.AWS_SECRET_ACCESS_KEY'`)
	$(eval HEROKU_USERNAME := `cat tmp/tc_cache_secrets | ./result-pkgs-jq/bin/jq -r '.secret.HEROKU_USERNAME'`)
	$(eval HEROKU_PASSWORD := `cat tmp/tc_cache_secrets | ./result-pkgs-jq/bin/jq -r '.secret.HEROKU_PASSWORD'`)

	


require-TOOL:
	@if [[ -z "$(TOOL)" ]]; then \
		echo ""; \
		echo "You need to specify which TOOL to build, eg:"; \
		echo "  make build-tool TOOL=awscli"; \
		echo "  ..."; \
		echo ""; \
		echo "Available TOOLS are: "; \
		for tool in $(TOOLS); do \
			echo " - $$tool"; \
		done; \
		echo ""; \
		exit 1; \
	fi
require-APP:
	@if [[ -z "$(APP)" ]]; then \
		echo ""; \
		echo "You need to specify which APP, eg:"; \
		echo "  make develop APP=releng_clobberer"; \
		echo "  make build-app APP=releng_clobberer"; \
		echo "  ..."; \
		echo ""; \
		echo "Available APPS are: "; \
		for app in $(APPS); do \
			echo " - $$app"; \
		done; \
		echo ""; \
		exit 1; \
	fi


require-AWS:
	@if [[ -z "$$AWS_ACCESS_KEY_ID" ]] || \
		[[ -z "$$AWS_SECRET_ACCESS_KEY" ]]; then \
		echo ""; \
		echo "You need to specify AWS credentials, eg:"; \
		echo "  make deploy-production-releng_frontend \\"; \
	    echo "       AWS_ACCESS_KEY_ID=\"...\" \\"; \
		echo "       AWS_SECRET_ACCESS_KEY=\"...\""; \
		echo ""; \
		echo ""; \
		exit 1; \
	fi

require-HEROKU:
	@if [[ -z "$$HEROKU_USERNAME" ]] || \
		[[ -z "$$HEROKU_PASSWORD" ]]; then \
		echo ""; \
		echo "You need to specify HEROKU credentials, eg:"; \
		echo "  make deploy-production-releng_clobberer \\"; \
	    echo "       HEROKU_USERNAME=\"...\" \\"; \
		echo "       HEROKU_PASSWORD=\"...\""; \
		echo ""; \
		echo ""; \
		exit 1; \
	fi


all: build-apps build-tools
