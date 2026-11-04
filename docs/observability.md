# Observability validation (phase 1)

Validates an existing deployment without restarting services, changing configuration,
installing packages, creating VMs, injecting alerts or running cleanup sweeps.
Ansible's normal temporary module transport still requires remote temporary space.
Reports are written only on the Ansible controller.

## Standalone run

Run from the validation repository. Reuse the **deployment inventory**, including
its `frontend`, `node`, `grafana` groups and `one_version`. Group names can be changed
with `frontend_group`, `node_group`, `grafana_group` as in the main framework.

```bash
ansible-playbook -i /path/to/lab-sa-7.4.1.yml playbooks/observability.yml
# Or using the project's Hatch environment:
make observability I=/path/to/lab-sa-7.4.1.yml
```

This entrypoint deliberately does not import `validation.yml`: the full suite has
`always` cleanup plays and tests that restart core services. Merely selecting a tag
in that suite does not make the entire run read-only.

The standalone entrypoint writes `/tmp/observability-report.html` and `.json` on the
controller, then returns a failure if any check failed or no hosts were selected.
Use `-e observability_report_path=/path/to/report-prefix` (existing parent directory)
for concurrent runs. `observability_fail_on_error: false` retains report-only behavior.
Skipped checks are visible and do not count as passes. Frontend/node groups are
required. A Grafana group is required unless `observability.require_grafana: false`.
Partial `--limit` runs report missing host probe coverage rather than silently passing.

## Full-suite integration

Set `validation.run_observability: true` to include the checks before the other
tests. The default is false to preserve existing runs. Results from frontend,
node and dedicated Grafana hosts are merged into the HTML/PDF Observability section.
This is the state **before** the suite's service restarts/fencing, not a post-failover
verification. The full suite retains its usual cleanup and exit behavior.

## Configuration

Configuration lives under top-level `observability`; credentials live separately
under `observability_auth`, **not under `validation`** (the legacy report prints that
dictionary). Keep credentials in Ansible Vault. All HTTP credentials are protected
by the module's `no_log` argument and never copied into findings.

```yaml
one_version: '7.4.1'
observability:
  timeout: 5                  # HTTP request timeout in seconds
  attempts: 3                 # HTTP retries (maximum 10)
  delay: 2                    # Seconds between failed requests
  max_sample_age: 120         # Match your scrape interval; allow startup to settle
  validate_certs: true
  require_grafana_auth: true  # Missing API credentials fails rather than skips
  grafana_datasource: prometheus
  dashboards: [OpenNebula, Hosts, Virtual Machine]
  # Optional exact names from /api/v1/rules; populate to enforce your ruleset.
  expected_alert_rules: []
  expected_recording_rules: []
  # Optional strict URL policy, independent of API endpoint addresses.
  grafana_require_datasource_url: false
  grafana_prometheus_url: http://172.20.0.26:9090

# Prefer Vault or an environment lookup; never commit real credentials.
observability_auth:
  grafana:
    token: "{{ lookup('ansible.builtin.env', 'GRAFANA_TOKEN') }}"
```

Tokens require permission to read datasources, query the selected datasource and
search dashboards. Basic authentication is also supported using `username` and
`password` instead of `token`. Prometheus, Alertmanager and exporters accept the same
auth format under their respective names (`prometheus`, `alertmanager`, `node`, etc.).
Without Grafana credentials, public health is checked and authenticated checks are
explicitly skipped (or failed with `require_grafana_auth`). No default admin password
is assumed. HTTP redirects are rejected so login pages cannot masquerade as health.

Datasource connectivity is checked through Grafana's proxy. A valid `up=0` series
still confirms connectivity; unhealthy targets fail the separate target checks.
The configured datasource URL is included as evidence. Exact URL equality is only
required with `grafana_require_datasource_url: true`; changing a validation URL
does not reconfigure Grafana. Dashboard datasource variables such as
`${DS_PROMETHEUS}` resolve through their saved selection, or a single matching
datasource when no selection is saved. Missing, ambiguous or wrong selections fail
with an explicit reason. Per-query datasource overrides are checked too.

Host-level overrides: `prometheus_url`, `alertmanager_url`, `grafana_url` default to
loopback ports 9090, 9093 and 3000. The SA/HA lab inventories override them with
`ansible_host` addresses so probes use the host IP rather than loopback or DNS. Set
`grafana_prometheus_url` to the address (or HA VIP) Grafana is expected to use for
its Prometheus datasource. HTTP requests originate on the host being checked.
TLS certificate verification defaults to enabled; use trusted certificates or an
explicit lab-only override. URLs must not contain embedded credentials.

`observability_aliases: [other-hostname]` adds target aliases. Matching uses job,
port, inventory address, discovered hostname/FQDN and DNS addresses from the
Prometheus host; `localhost` matches only that frontend. It never matches a node
solely by exporter port.

```yaml
observability:
  exporters:
    node:
      port: 9100
      job: node_exporter
      # url: https://localhost:9100/metrics
      metrics: [node_uname_info, node_memory_MemTotal_bytes]
    smartctl:
      # Override only if your deployed Prometheus configuration scrapes FE SMART.
      scrape: true
  resource_metrics:
    # Optional metric names actually provided by your installed exporter version.
    # Declare these when the lab has the corresponding hardware/storage resources.
    lvm: []
    smartctl: []
    ovs: []
```

Do not copy the `smartctl.scrape: true` override to all hosts unless intentional.
By default FE SMART/OVS services are checked but only node SMART/OVS targets are
required, matching the generator in the inspected OpenNebula sources. Check the
installed `patch_datasources.rb` when validating another release/configuration.

## Expected services and coverage

With version >= 7.2.1:

| Exporter | Frontend | KVM node |
|---|---|---|
| Node | yes | yes |
| OpenNebula | yes | no |
| Libvirt | no | yes |
| MySQL | yes | no |
| LVM | no | yes, even with SSH datastores |
| SMART | yes | yes |
| OVS | when OVS configured | when OVS configured |

Older versions omit MySQL/LVM/SMART/OVS. OVS expectations come from `ovs_enabled`
or nonempty inventory `ovs.iface/bond/br`; `observability_ovs_enabled` overrides
this when using a separate validation inventory. Runtime facts from a previous
Ansible process are not assumed to persist. This role is for the KVM deployment
layout provided by one-deploy, not an automatic monitor for arbitrary exporters.

Systemd state and autostart are not required by this monitoring validation. Every expected scraped exporter must return valid
Prometheus samples. MySQL must report `mysql_up=1`; libvirt must report
`opennebula_libvirt_daemon_up=1`, which works with no guest VMs. Node and OpenNebula
must expose their expected metrics. Reported `*_scrape_error` gauges must be zero.

Expected targets are constructed before probing endpoints, so a failed/missing
exporter cannot silently disappear. Every expected target must occur exactly once,
have a recent successful scrape, expose `up=1` and contain fresh required samples.
Local collector checks and Prometheus target checks are combined into one metrics
collection row per exporter within the frontend/KVM group. Either side failing
makes the combined check fail. Exporters explicitly excluded from scraping are not
shown as successful metric collection checks.
OpenNebula host IDs in stored metrics are compared with `onehost list --json`.
Prometheus readiness is checked on each frontend that hosts it. Prometheus reload
success, the complete expected exporter target set (including unexpected targets
for configured exporter jobs), fresh metric samples, OpenNebula host IDs, alerting
and recording rules, rule evaluation and Alertmanager discovery are checked. Rule
names in `expected_alert_rules` and `expected_recording_rules` make the configured
ruleset explicit; recording-rule samples are queried and must exist. If the
deployment has no recording rules and none are configured as expected, that check
is reported as not applicable. Alertmanager readiness and loaded config are checked
independently on each frontend.

Grafana validates database health, selected Prometheus datasource, a real `up`
query through its datasource proxy, dashboard titles, and that each panel in each
expected dashboard references the selected datasource UID (or the selected default
datasource). It does not render panels in a browser or prove that every panel query
is correct. Dashboard titles and metric names can be overridden for other installed
versions.

Without configured `resource_metrics`, LVM/SMART/OVS resource coverage is explicitly
skipped: endpoint/transport success alone does not prove collection from actual
VGs, disks or OVS bridges. Device-level metric expectations do not yet compare an
enumeration of every physical device. VM workload and notification delivery tests,
HA peer/failover behavior and automatic repair are outside phase 1.

## Offline verification

```bash
python3 -m unittest discover -s test/observability -v
ansible-playbook -i inventory/reference/example.yml playbooks/observability.yml --syntax-check
python3 test/observability/integration.py /path/to/ansible-playbook
```

Regression tests cover missing exporters/targets, target identity, stale samples,
failed collectors despite HTTP success, empty libvirt hosts, absent resource
expectations, missing Grafana credentials, datasource queries and malformed API
responses. No live deployment is required for these tests.


## Full validation/report flow with observability only

The lab inventories directly under `inventory/` set
`validation.observability_only: true`, enable `validation.run_observability`, and
turn off the other validation roles. This mode also skips both manifest cleanup
passes. Use the normal validation playbook **without tags** to keep all report
aggregation and HTML/PDF generation:

```bash
export GRAFANA_TOKEN='...'
ansible-playbook -i inventory/observability-sa.yml playbooks/validation.yml
# or
ansible-playbook -i inventory/observability-ha.yml playbooks/validation.yml
```

The report prompts are part of the normal flow. This mode does read-only cluster
discovery for the existing report and observability checks. It neither invokes
core service restart checks nor pre-cleans old validation leftovers. Do not set
`validation.observability_only` on a general validation inventory unless all
other role flags are deliberately configured for the same observability-only run.

The standard report output path and two-column layout are retained. A single
Monitoring container uses the existing data-section style, with four subsections:

1. Endpoints readiness: Prometheus, Alertmanager and Grafana HTTP health/readiness.
2. Frontend metrics collection: combined exporter/target checks on frontends.
3. KVM metrics collection: combined exporter/target checks on KVM nodes.
4. Monitoring integration: configuration, host coverage, rules, Alertmanager
   discovery, Grafana datasource connectivity and dashboard datasource references.

Successful validation prerequisites are hidden; failures and warnings remain in
the first subsection. Service/autostart checks are no longer run.

Frontend/KVM classification follows inventory group membership, not hostname
patterns. For scrape checks it follows the target host, not the querying Prometheus.
Unknown checks/roles remain visible under Monitoring integration. FAIL notes identify affected
hosts (or Prometheus → target); WARN notes preserve the reason and affected hosts.
PASS rows have no NOTE. Raw per-host facts remain unchanged. Rule evaluation health
is included in the alerting/recording checks rather than a separate duplicate row.

### Optional VM metrics scenario

The regular monitoring checks remain read-only. To additionally check a running
VM's metrics and identity labels, set these inventory variables:

```yaml
observability_vm:
  enabled: true
  vm_id: 42
  retries: 30
  delay: 10
```

Alternatively replace `vm_id` with `template_id: 123` to instantiate a temporary
VM from an existing, ready-to-use template. Specify exactly one of these IDs.
The template must already include usable disks, scheduling and network settings;
no Marketplace download, guest Internet, SSH, startup script or load is required.
The scenario runs once on a frontend, using the oneadmin CLI credentials. It is
skipped in Ansible check mode. Run the usual `playbooks/validation.yml` entrypoint
with monitoring enabled; no separate deployment or reporting command is needed.

The check waits for RUNNING and checks `opennebula_vm_state`,
`opennebula_vm_cpu_ratio`, `opennebula_libvirt_cpu_seconds_total` and
`opennebula_libvirt_memory_total_bytes`. Each metric must have finite samples,
the selected `one_vm_id`, the configured exporter `job` and a nonempty `instance`.
Libvirt samples must also have `domain` equal to `one-<VM ID>` (KVM's `DEPLOY_ID` is a UUID, not the domain name) and
`one_host_id` equal to the latest OpenNebula history record's host. Missing or
mismatched labels fail the check. This checks presence and identity, not changes
under load, timestamp progression, or labels on every exporter metric.

The report adds one `VM metrics present` result under Monitoring integration.
Raw result comments retain VM ID and failure details. An existing VM is never
terminated. A VM instantiated by this scenario is terminated in the `always`
cleanup path, including after a failed check. Cleanup failures are reported
separately. An interrupted Ansible process or loss of SSH can prevent cleanup;
temporary VM names start with `odv-monitoring-` and include a unique run ID.
