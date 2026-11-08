# Automatically creating scenes

This script can create all the default scenes at home.

To use it, install [pixi](https://pixi.sh) and then run:

```sh
$ pixi install
# resets scenes for the particular room
$ pixi run reset office.yml  # run directly on the server!
# starts a container with access to z2m configuration on /data
$ pixi run config
# prints one HomeKit switch per scene (homebridge-mqttthing), all rooms
$ pixi run homekit
# writes them to the Homebridge config (backup in /homebridge/backups/)
$ pixi run homekit --apply  # run directly on the server!
```

After `--apply`, restart the `homebridge-mqttthing` child bridge from the
Homebridge UI. Re-run it whenever scenes are added, removed or reordered here.

The wall switch automations that recall these scenes, and the house-wide
scenes ("Welcome home", "Lights out"), live in `docker/zigbee2mqtt/`
(`automations.yaml`, `scenes.yaml`). Scene IDs there are the position of the
scene in these files, starting at 1.

> Note: If you find issues resetting scenes with many Ikea lights (like in the
> Living Room), then execute each scene individually like follows:
>
> $ pixi run reset <room-configuration-file> --only-scene Dinner
