# References

Offical Sonoff firmware:
<https://github.com/itead/Sonoff_Zigbee_Dongle_Firmware/blob/master/Dongle-E/NCP>

New firmware from SiLabs, supposedly more stable:

* <https://github.com/Nerivec/silabs-firmware-builder/releases>, or
* <https://github.com/darkxst/silabs-firmware-builder/releases>

Official information from Zigbee2mqtt:
<https://www.zigbee2mqtt.io/guide/adapters/emberznet.html>
<https://github.com/Koenkk/zigbee2mqtt/discussions/21462>

## Instructions

Create the conda/mamba environment if it does not already exists:

To use it, install [pixi](https://pixi.sh) and then run:

```sh
$ pixi install
# probes the device for the current firmware
$ pixi run probe-coordinator
# flashes the vendor firmware ./ncp-uart-sw_EZNet6.10.3_V1.0.1.gbl (OUTDATED, ezsp driver)
$ pixi run flash-vendor-coordinator
# flashes silabs/Nerivec firmware ./sonoff_zbdonglee_zigbee_ncp_8.2.2.0_115200_sw_flow.gbl (RECOMMENDED, ember driver)
$ pixi run flash-nerivec-coordinator
# goes back to the previous Nerivec firmware (8.0.2)
$ pixi run rollback-nerivec-coordinator
```

The same tasks exist for the router dongle (`probe-router`, `flash-nerivec-router`,
`rollback-nerivec-router`), but they need the dongle plugged into the Pi. Any other
computer can flash it too, by running `universal-silabs-flasher` with the `.gbl` file
directly. Zigbee2MQTT can keep running for the router, but must be stopped for the
coordinator, since it holds the serial port (`docker stop zigbee2mqtt`).

`*.gbl` files are gitignored, so download the Nerivec ones from the releases page:
8.2.2 is in `v2025.6.2-update1`, 8.0.2 in `v2024.6.2-update7`.

## Version notes

Stay on 8.2.2 for now. Both dongles use the CH9102 serial chip (USB ID `1a86:55d4`),
and 9.x builds have open problems on this hardware (routers dropping off the network):

* <https://github.com/Nerivec/silabs-firmware-builder/issues/109>
* <https://github.com/Nerivec/silabs-firmware-builder/issues/126>

Pick `sw_flow` builds at 115200 baud, and check again once those issues close.
