SHELL := $(shell which bash)
SELF  := $(patsubst %/,%,$(dir $(abspath $(firstword $(MAKEFILE_LIST)))))

ENV_RUN      = hatch env run -e $(1) --
ENV_DEFAULT := $(shell hatch env find default)
ENV_CEPH    := $(shell hatch env find ceph)

I         ?= $(SELF)/inventory/example.yml
INVENTORY ?= $(I)

T    ?=
TAGS ?= $(T)

S         ?=
SKIP_TAGS ?= $(S)

V       ?= vv
VERBOSE ?= $(V)

ONE_DEPLOY_URL ?= git+https://github.com/OpenNebula/one-deploy.git,master

export

# Make sure we source ANSIBLE_ settings from ansible.cfg exclusively.
unexport $(filter ANSIBLE_%,$(.VARIABLES))

.PHONY: all

all: main

.PHONY: infra pre ceph site main verification

infra pre ceph site main verification: _TAGS      := $(if $(TAGS),-t $(TAGS),)
infra pre ceph site main verification: _SKIP_TAGS := $(if $(SKIP_TAGS),--skip-tags $(SKIP_TAGS),)
infra pre ceph site main verification: _VERBOSE   := $(if $(VERBOSE),-$(VERBOSE),)
infra pre ceph site main verification: _ASK_VAULT := $(if $(findstring $$ANSIBLE_VAULT;,$(file < $(INVENTORY))),--ask-vault-pass,)

ifdef ENV_DEFAULT
$(ENV_DEFAULT):
	hatch env create default
endif

infra pre site main verification: $(ENV_DEFAULT)
	cd $(SELF)/ && \
	$(call ENV_RUN,default) ansible-playbook $(_VERBOSE) -i $(INVENTORY) $(_ASK_VAULT) $(_TAGS) $(_SKIP_TAGS) $(SELF)/playbooks/$@.yml

ifdef ENV_CEPH
$(ENV_CEPH):
	hatch env create ceph
endif

ceph: $(ENV_CEPH)
	cd $(SELF)/ && \
	$(call ENV_RUN,ceph) ansible-playbook $(_VERBOSE) -i $(INVENTORY) $(_ASK_VAULT) $(_TAGS) $(_SKIP_TAGS) $(SELF)/playbooks/$@.yml

.PHONY: requirements requirements-hatch requirements-galaxy clean-requirements

requirements: requirements-hatch requirements-galaxy

requirements-hatch: $(SELF)/pyproject.toml $(ENV_DEFAULT)

requirements-galaxy: $(ENV_DEFAULT)
	$(call ENV_RUN,default) ansible-galaxy collection install --upgrade $(ONE_DEPLOY_URL)

clean-requirements:
	$(if $(ENV_DEFAULT),hatch env remove default,)
	$(if $(ENV_CEPH),hatch env remove ceph,)

.PHONY: lint-ansible

lint-ansible: $(ENV_DEFAULT)
	cd $(SELF)/ && $(call ENV_RUN,default) ansible-lint roles/ playbooks/
