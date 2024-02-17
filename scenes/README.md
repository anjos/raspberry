# Automatically creating scenes

This script can create all the default scenes at home.

To use it, create a conda/mamba environment as follows:

```sh
$ mamba create -n scenes python=3 pip pyyaml ipdb
$ mamba activate scenes
(scenes) $ pip3 install paho-mqtt
(scenes) $ ./reset.py scenes/office.yml  # run directly on the server!
```

> Note: If you find issues resetting scenes with many Ikea lights (like in the
> Living Room), then execute each scene individually like follows:
>
> (scenes) $ ./reset.py <room-configuration-file> --only-scene Dinner
