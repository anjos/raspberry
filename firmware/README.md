# References

Offical Sonoff firmware:
https://github.com/itead/Sonoff_Zigbee_Dongle_Firmware/blob/master/Dongle-E/NCP

New firmware with multi-protocol support and (supposedly) more stable:
https://dialedin.com.au/blog/sonoff-zbdongle-e-rcp-firmware

Official information from Zigbee2mqtt:
https://github.com/Koenkk/zigbee2mqtt/discussions/21462

## Instructions

Create the conda/mamba environment if it does not already exists:

To use it, install [pixi](https://pixi.sh) and then run:

```sh
$ pixi install
# flashes the vendor firmware ./ncp-uart-sw_EZNet6.10.3_V1.0.1.gbl
$ pixi run flash-vendor
# flashes silabs firmware ./ncp-uart-sw_EZNet6.10.3_V1.0.1.gbl
$ pixi run flash-silabs
# flashes an arbitrary firmware
$ pixi run flash <filename.gbl>
```
