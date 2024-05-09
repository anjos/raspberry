# Automatically creating scenes

This script can create all the default scenes at home.

To use it, install [pixi](https://pixi.sh) and then run:

```sh
$ pixi install
$ pixi run reset office.yml  # run directly on the server!
```

> Note: If you find issues resetting scenes with many Ikea lights (like in the
> Living Room), then execute each scene individually like follows:
>
> $ pixi run reset <room-configuration-file> --only-scene Dinner
