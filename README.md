[//]: # ( vim: set wrap : )

# one-deploy-validation

## Checkout

1. Resursively clone the `engineering-deploy` repository

   ```shell
   cd ~/ && git clone --recursive git@github.com:OpenNebula/one-deploy-validation.git
   ```

## Requirements

> [!NOTE]
> If Makefile is used then it will create python virtual environments using `hatch` (on demand).

1. Install `hatch`

   ```shell
   pip install hatch
   ```

   or

   ```shell
   pipx install hatch
   ```

   or use any other method you see fit

2. Install the `opennebula.deploy` collection with dependencies

   ```shell
   make requirements
   ```

   if you'd like to pick specific branch (instead of `master`), tag or a custom fork

   ```shell
   make requirements ONE_DEPLOY_URL:=git+https://github.com/OpenNebula/one-deploy.git,release-1.2.1
   ```

   the `one-deploy` repository checkout should be available in `~/.ansible/collections/ansible_collections/opennebula/deploy/`

3. (OPTIONAL) Update the `vendor/ceph-ansible` submodule (if you want to deploy Ceph clusters)

   ```shell
   cd ~/ && git submodule update --init --recursive -- ./
   ```

## Playbooks/Roles

1. You can create new playbooks and roles as you desire and still reuse the code from `one-deploy`

   ```yaml
   ---
   - ansible.builtin.import_playbook: opennebula.deploy.site

   - hosts:
       - "{{ frontend_group | d('frontend') }}"
       - "{{ node_group | d('node') }}"
     roles:
       - role: { opennebula.deploy.helper.facts, _force: true }
       - role: example
   ```

## Inventory/Execution

> [!NOTE]
> It's exactly the same as with `one-deploy`.

1. Inventories are kept in the `./inventory/` directory, please take a look at [example.yml](./inventory/example.yml)

2. To execute `ansible-playbook` you can run

   ```shell
   make I=inventory/example.yml main
   ```

   all the normal targets are available by default

   - [ceph](./playbooks/ceph.yml)
   - [infra](./playbooks/infra.yml)
   - [main](./playbooks/main.yml)
   - [pre](./playbooks/pre.yml)
   - [site](./playbooks/site.yml)
