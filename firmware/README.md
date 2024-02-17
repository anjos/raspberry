# References

Offical Sonoff firmware:
https://github.com/itead/Sonoff_Zigbee_Dongle_Firmware/blob/master/Dongle-E/NCP

New firmware with multi-protocol support and (supposedly) more stable :
https://dialedin.com.au/blog/sonoff-zbdongle-e-rcp-firmware


## Instructions

Create the conda/mamba environment if it does not already exists:

```sh
$ mamba env create -n sonoff-flasher -f environment.yml
$ conda activate sonoff-flasher
```

Use it with:

```sh
(sonoff-flasher) $ universal-silabs-flasher --device /dev/ttyACM0 flash --firmware ./ncp-uart-sw_EZNet6.10.3_V1.0.1.gbl
```

WARNING: The other firmware (`rcp-uart-802154-v4.3.1-zbdonglee-460800.gbl`)
from Silabs does not seem to work as of today, 11.02.2024.  Zigbee2mqtt never
manages to connect to the dongle once the firmware is flush.

To flash this firmware use a further option:

```sh
(sonoff-flasher) $ universal-silabs-flasher --device /dev/ttyACM0 flash --firmware ./rcp-uart-802154-v4.3.1-zbdonglee-460800.gbl --allow-cross-flashing`
```
