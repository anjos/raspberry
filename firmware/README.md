# References

Offical Sonoff firmware:
https://github.com/itead/Sonoff_Zigbee_Dongle_Firmware/blob/master/Dongle-E/NCP

New firmware from SiLabs, supposedly more stable:
https://github.com/darkxst/silabs-firmware-builder/tree/main/firmware_builds/zbdonglee

Official information from Zigbee2mqtt:
https://www.zigbee2mqtt.io/guide/adapters/emberznet.html
https://github.com/Koenkk/zigbee2mqtt/discussions/21462

## Instructions

Create the conda/mamba environment if it does not already exists:

To use it, install [pixi](https://pixi.sh) and then run:

```sh
$ pixi install
# probes the device for the current firmware
$ pixi run probe
# flashes the vendor firmware ./ncp-uart-sw_EZNet6.10.3_V1.0.1.gbl (OUTDATED, ezsp driver)
$ pixi run flash-vendor
# flashes silabs firmware ./ncp-uart-hw-v7.4.1.0-zbdonglee-115200.gbl (RECOMMENDED, ember driver)
$ pixi run flash-silabs
# runs an arbitrary command
$ pixi run flasher --help
```
