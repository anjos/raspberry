# Zigbee2MQTT external extensions

`configuration.yaml` and `automations.yaml` are mounted as writable files in
the Zigbee2MQTT data directory. Changes made through the Zigbee2MQTT frontend
are therefore reflected directly in this repository and can be reviewed and
committed with Git. The named Docker volume continues to store volatile state,
including the device database, coordinator backup, logs, and device icons.

The `external_extensions` directory is mounted at
`/app/data/external_extensions` in the Zigbee2MQTT container. It must be
writable because Zigbee2MQTT creates temporary copies in this directory while
validating extensions.

`scenes.yaml` is mounted the same way and holds the house-wide scenes of the
automations extension ("Welcome home", "Lights out"). Automations run them with
`- scene: <name>`, and the Home app runs them by publishing `execute` to
`zigbee2mqtt-scenes/<name>`.

## automation.js

Upstream source:
<https://github.com/Luligu/zigbee2mqtt-automations/blob/master/dist/automations.js>

The local file is upstream version 3.0.0, retrieved on 2026-09-18. Its SHA-256
is `228823958858c493384aa616f0e8cf8ed96b8797bbd79ed0f46a1c6c42da4ac3`.

To check for an upstream change:

```sh
curl -fsSL \
  https://raw.githubusercontent.com/Luligu/zigbee2mqtt-automations/master/dist/automations.js \
  -o /tmp/automations-upstream.js
sha256sum external_extensions/automation.js /tmp/automations-upstream.js
```

## shower-room-reporting.mjs

Local reporting policy for the Shower room Switch. It reapplies the desired
reporting configuration after Zigbee2MQTT startup, device announcements, and
manual device reconfiguration.
