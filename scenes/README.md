# Automatically creating scenes

This script can create all the default scenes at home.

To use it, create a conda/mamba environment as follows:

```sh
$ mamba env create -n mqtt-scenes -f environment.yml
$ mamba activate mqtt-scenes
(mqtt-scenes) $ ./reset.py scenes/office.yml  # run directly on the server!
```

> Note: If you find issues resetting scenes with many Ikea lights (like in the
> Living Room), then execute each scene individually like follows:
>
> (mqtt-scenes) $ ./reset.py <room-configuration-file> --only-scene Dinner
