# AIORS + SvxLink MQTT Telemetry

## Architecture

`aiors-mqtt-agent` is a third, independent service. It is not linked into
`svxlink` or `aiorsd` and neither radio service requires it.

The agent:

1. Reads the atomic SvxLink snapshot at
   `/var/lib/svxlink/svxstats_snapshot.txt`.
2. Converts every `key=value` field into a JSON telemetry object.
3. Stores outbound telemetry, events, and command responses in
   `/var/lib/aiors-mqtt/queue.db` before publishing.
4. Publishes with MQTT QoS 1 and removes a queued item only after PUBACK.
5. Reconnects with bounded backoff when the broker or network is unavailable.

The queue is bounded by both `MAX_QUEUE_MESSAGES` (default 10080) and
`MAX_QUEUE_BYTES` (default 50 MiB). When full, the oldest low-priority
telemetry is discarded before events or command responses. MQTT outages
therefore consume bounded disk space and cannot block, stop, or restart
`svxlink` or `aiorsd`.

The systemd unit has ordering only. It has no `Requires=` relationship with
either radio service. A broker failure, bad credential, corrupt MQTT database,
or agent crash affects MQTT reporting only.

## Node Identity

The default node ID comes from the active SvxLink logic:

1. Read `LOGICS` from `[GLOBAL]` in `/etc/svxlink/svxlink.conf`.
2. Read `CALLSIGN` from the selected logic section.
3. Convert the callsign to uppercase.

`CALLSIGN=MYCALL` is rejected. If `LOGICS` contains multiple entries, set
`NODE_ID` explicitly under `[agent]`. Characters unsafe in an MQTT topic level
are percent encoded, so `/` becomes `%2F`, `+` becomes `%2B`, and `#` becomes
`%23`. The original callsign remains in each JSON payload as `node_id`.

## Topics

For `CALLSIGN=S5RPTAIORS`, the agent uses:

| Topic | QoS | Retained | Contents |
|---|---:|---:|---|
| `frn/aiors/v1/S5RPTAIORS/status` | 1 | yes | Online/offline state, agent version, boot ID, command state, queue depth |
| `frn/aiors/v1/S5RPTAIORS/telemetry` | 1 | yes | Complete latest SvxLink statistics snapshot, including AIORS diagnostics |
| `frn/aiors/v1/S5RPTAIORS/events` | 1 | no | Important AIORS state and fault transitions |
| `frn/aiors/v1/S5RPTAIORS/command/request` | 1 | no | Server-to-node structured control request; subscription is disabled by default |
| `frn/aiors/v1/S5RPTAIORS/command/response` | 1 | no | Durable result for a command request |

The broker Last Will sets retained status to `offline` after an unexpected
disconnect. A graceful service stop publishes `offline` with reason
`service_stopped`.

## Telemetry Payload

Example envelope:

```json
{
  "schema": 1,
  "kind": "telemetry",
  "node_id": "S5RPTAIORS",
  "topic_node_id": "S5RPTAIORS",
  "boot_id": "42f81f04-66e6-4692-8dde-81a8d8f7e19b",
  "sequence": 1842,
  "published_at": "2026-08-24T12:30:00Z",
  "logic": "RepeaterLogic",
  "source": "/var/lib/svxlink/svxstats_snapshot.txt",
  "metrics": {
    "stats_schema": 3,
    "ts_unix_s": 1787574600,
    "aiors_overall_status": "ok",
    "aiors_psu_a_input_voltage_v": 13.72,
    "aiors_psu_a_energy_wh_total": 126.31
  }
}
```

`na` is transmitted as JSON `null`. Numeric snapshot values become JSON
numbers. Status, state, version, revision, scope, error, and boot-ID values
remain strings.

Every field in the snapshot is sent. The current snapshot groups are:

| Group | Data |
|---|---|
| Identity and uptime | Snapshot schema/time, Linux boot ID and uptime, SvxLink runtime/version/revision, AIORS runtime/version/revision/hardware version |
| FRN link | Link up/down ages and 1-hour/lifetime counters, users, joins/leaves, RX/TX age, duration, bytes, events, and duty |
| RF | RX/TX event counts, durations, min/max duration, duty, and lifetime hours |
| RunCmd | Accepted, rejected, authentication failure, broadcast attempt, average latency, and maximum latency values |
| AIORS health | Sample status/age/error, overall status, ADC/environment/digital-input status, PSU GPIO status, fan state |
| PSU A and B | Current state/fault, input voltage/current/calculated power, 1-hour and 24-hour min/max/average/sample count |
| Power totals | Per-channel Wh and Ah, measurement coverage, on/off time, fault time/events, state changes, and restart/degraded/fault totals |
| Board measurements | 3.3 V and 5 V buses, temperature, humidity, RF A/B average voltage, AI0-AI3; each includes current and 1-hour/24-hour min/max/average/sample count |
| Radio peripherals | Current SA818 A/B and CM108 A/B status plus 1-hour, 24-hour, and lifetime fault event/sample/duration counters |

The authoritative field list is the `metrics` object. Consumers should ignore
unknown fields so a future `stats_schema` can add diagnostics without breaking
ingestion.

## Events

The agent emits `metric_changed` events for these state fields:

```text
frn_link_up_total
frn_link_down_total
aiors_sample_ok
aiors_overall_status
aiors_psu_gpio_status
aiors_psu_a_state
aiors_psu_a_fault
aiors_psu_b_state
aiors_psu_b_fault
aiors_adc_status
aiors_environment_status
aiors_sa818_a_status
aiors_sa818_b_status
aiors_cm108_a_status
aiors_cm108_b_status
aiors_restart_evt_total
```

Example:

```json
{
  "schema": 1,
  "kind": "event",
  "node_id": "S5RPTAIORS",
  "boot_id": "42f81f04-66e6-4692-8dde-81a8d8f7e19b",
  "sequence": 1843,
  "published_at": "2026-08-24T12:31:00Z",
  "event": "metric_changed",
  "metric": "aiors_psu_a_fault",
  "previous": "no",
  "current": "yes"
}
```

The first observed value seeds local state and is not reported as a change.

## Pi Configuration

Start from the managed template:

```sh
sudo cp /usr/local/share/aiors/aiors-mqtt-agent.conf \
  /etc/aiors-mqtt/agent.conf
sudoedit /etc/aiors-mqtt/agent.conf
```

Set at minimum:

```ini
[agent]
ENABLED=1

[broker]
HOST=mqtt.example.net
PORT=8883
USERNAME=S5RPTAIORS
PASSWORD_FILE=/etc/aiors-mqtt/password
TLS=1
CA_FILE=/etc/aiors-mqtt/ca.crt
```

Install secrets with restrictive permissions:

```sh
sudo install -o root -g aiors-mqtt -m 0640 password \
  /etc/aiors-mqtt/password
sudo install -o root -g aiors-mqtt -m 0644 ca.crt \
  /etc/aiors-mqtt/ca.crt
```

Mutual TLS is supported with `CERT_FILE` and `KEY_FILE`; set both or neither.
Validate and start:

```sh
sudo -u aiors-mqtt aiors-mqtt-agent --check-config \
  -c /etc/aiors-mqtt/agent.conf
sudo systemctl enable --now aiors-mqtt-agent
systemctl status aiors-mqtt-agent --no-pager
journalctl -u aiors-mqtt-agent -b --no-pager -n 100
```

For a fresh combined deployment, private files can be supplied without adding
them to Git:

```sh
MQTT_CONFIG_PATH=$HOME/private/agent.conf \
MQTT_CA_PATH=$HOME/private/ca.crt \
MQTT_PASSWORD_PATH=$HOME/private/password \
AIORS_HW_VERSION=1.1 \
DEPLOY_VERSION=deploy-v1.1.0 \
  bash install.sh
```

Existing MQTT config and credentials are preserved on upgrades when these
variables are omitted.

## Server Broker

Install Mosquitto on the FRN server and use TLS plus authentication. A minimal
configuration is provided in `docs/mosquitto-aiors.conf.example` and an ACL
template in `docs/mosquitto-aiors.acl.example`.

Create a distinct broker account for each node. The sample ACL allows a node
to publish only its status, telemetry, events, and responses, and to read only
its own command request topic. Give the server ingestion/control application a
separate account.

Verify from the server:

```sh
mosquitto_sub -h mqtt.example.net -p 8883 \
  --cafile /etc/mosquitto/certs/ca.crt \
  -u frn-ingest -P 'SERVER_PASSWORD' \
  -t 'frn/aiors/v1/+/status' \
  -t 'frn/aiors/v1/+/telemetry' \
  -t 'frn/aiors/v1/+/events' -v
```

The server database should use `(node_id, boot_id, sequence)` as an idempotency
key. QoS 1 is at least once, so duplicate delivery is valid. Store the metric
timestamp `metrics.ts_unix_s` as observation time and `published_at` as
transport time. Alert on retained `status.state=offline`, stale telemetry, an
increasing failure/fault counter, or threshold violations. Do not calculate a
new event by summing repeated retained snapshots; store counter samples and
derive deltas per node and boot.

## Remote Commands

Remote commands are compiled and installed but `[commands] ENABLED=0` is the
default. When disabled, the agent does not subscribe to `command/request`.

Request example:

```json
{
  "schema": 1,
  "request_id": "86d16941-55fc-4b4e-af54-5f52ef14751e",
  "node_id": "S5RPTAIORS",
  "expires_at_unix_s": 1787574900,
  "operation": "fan.set",
  "arguments": { "action": "on" }
}
```

Supported operations map to fixed `aiorsctl` argument vectors:

| Operation | Arguments |
|---|---|
| `route.set` | `channel` (`a`/`b`), `port` (`ai`/`bi`/`ae`/`be`), `side` (`rx`/`tx`) |
| `route.set_all` | `a_rx_port`, `a_tx_port`, `b_rx_port`, `b_tx_port` |
| `digital_output.set` | `channel` (`0`-`5`), `action` (`on`/`off`/`toggle`) |
| `fan.set` | `action` (`on`/`off`/`toggle`) |
| `usb_power.set` | `port` (`2`-`5`), `action` (`on`/`off`) |
| `led.set` | `channel` (`a`/`b`), `side` (`rx`/`tx`), `action` (`on`/`off`/`toggle`) |
| `watchdog.pulse` | Empty object |

Debug and stress commands are deliberately unavailable. The agent never runs
a shell. It validates every operation and value, calls `aiorsctl` with a fixed
argument array, enforces `TIMEOUT_MS`, limits captured output, rejects expired
or wrong-node requests, and stores completed request IDs in SQLite. A repeated
`request_id` returns the stored response without executing the hardware command
again.

The request ID is durably claimed before `aiorsctl` starts. If power is lost in
the narrow interval between starting the hardware action and saving its reply,
the same request is not executed again; its response reports
`previous_execution_outcome_unknown` and the server can require an operator to
inspect current state.

Enable commands only after broker ACLs and the server authorization path have
been tested:

```ini
[commands]
ENABLED=1
TIMEOUT_MS=3000
```

The FRN server should authenticate its human/API caller, authorize the exact
node and operation, generate a globally unique `request_id`, use a short
expiration (for example 30 seconds), publish non-retained at QoS 1, and wait
for the matching response. It must never retry with a new request ID unless a
second hardware action is intended.

## Failure Tests

Run these before depending on telemetry operationally:

1. Stop the broker. Confirm `aiorsd` and `svxlink` remain active and the SQLite
   outbox stays within `MAX_QUEUE_MESSAGES` and `MAX_QUEUE_BYTES`.
2. Restart the broker. Confirm queued messages drain and duplicates are ignored
   by the server idempotency key.
3. Stop `svxlink`. Confirm the MQTT agent remains alive and the last retained
   telemetry stays available; the server should mark it stale by timestamp.
4. Stop the MQTT agent. Confirm the broker Last Will changes retained status to
   `offline` while both radio services continue normally.
5. Publish a retained, expired, wrong-node, unknown-operation, and duplicate-ID
   command. Confirm none causes an unintended repeated hardware action.
