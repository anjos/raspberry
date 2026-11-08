#!/usr/bin/env python3

"""Exposes the Zigbee2MQTT room scenes to HomeKit through homebridge-mqttthing.

Each scene becomes a momentary switch named "<Room> <Scene>" that publishes
``{"scene_recall": N}`` to ``zigbee2mqtt/<Room>/set``, exactly like the wall
switch automations. The switch turns itself off after a second without
publishing anything, because it has no ``offValue``.

Scene IDs follow the order of the scenes in each file, as in ``reset.py``.

The house-wide scenes in ``docker/zigbee2mqtt/scenes.yaml`` (run by the
automations extension) become switches named after the scene. They publish
``execute`` to ``zigbee2mqtt-scenes/<name>``.
"""

import argparse
import datetime
import glob
import json
import logging
import os
import subprocess

from reset import parse_yaml_files

# All scene switches share this child bridge (pair it once in the Home app).
# Keep these values stable: changing them makes HomeKit see a new bridge.
BRIDGE = {"username": "0E:4B:DB:41:85:87", "port": 33817}
MQTT_URL = "mqtt://raspberry:1883"
CONTAINER = "homebridge"
CONFIG = "/homebridge/config.json"
HOUSE_SCENES = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "docker", "zigbee2mqtt", "scenes.yaml"
)


def make_switch(name: str, topic: str, value: str) -> dict:
    """Returns a momentary mqttthing switch publishing ``value`` to ``topic``."""

    return {
        "accessory": "mqttthing",
        "type": "switch",
        "name": name,
        "url": MQTT_URL,
        "topics": {"setOn": topic},
        "onValue": value,
        "turnOffAfterms": 1000,
        "_bridge": BRIDGE,
    }


def make_accessories(data: dict[str, dict], house: list[str]) -> list[dict]:
    """Returns one switch per scene in each room, plus the house-wide ones."""

    accessories = []
    for room, scenes in data.items():
        for index, scene in enumerate(scenes):
            accessories.append(
                make_switch(
                    f"{room} {scene}",
                    f"zigbee2mqtt/{room}/set",
                    json.dumps({"scene_recall": index + 1}),
                )
            )
    for scene in house:
        accessories.append(
            make_switch(scene, f"zigbee2mqtt-scenes/{scene}", "execute")
        )
    return accessories


def docker_exec(*command: str, stdin: str | None = None) -> str:
    """Runs a command in the Homebridge container and returns its output."""

    result = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, *command],
        input=stdin,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def apply(accessories: list[dict]):
    """Replaces the mqttthing accessories in the Homebridge configuration."""

    original = docker_exec("cat", CONFIG)
    config = json.loads(original)

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = f"/homebridge/backups/config.json.{stamp}"
    docker_exec("sh", "-c", f"cat > {backup}", stdin=original)
    logging.info(f"Saved the current configuration to {backup}")

    others = [
        a for a in config.get("accessories", []) if a.get("accessory") != "mqttthing"
    ]
    config["accessories"] = others + accessories
    docker_exec("sh", "-c", f"cat > {CONFIG}", stdin=json.dumps(config, indent=4))
    logging.info(
        f"Wrote {len(accessories)} scene switches to {CONFIG}; restart the "
        f"child bridge on port {BRIDGE['port']} to load them"
    )


def main():
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
    )
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write the switches to the Homebridge configuration (default: print them)",
    )
    args = parser.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    data = parse_yaml_files(sorted(glob.glob(os.path.join(here, "*.yml"))))
    house = list(parse_yaml_files([HOUSE_SCENES]))
    accessories = make_accessories(data, house)

    if not args.apply:
        print(json.dumps(accessories, indent=4))
        return

    for room, scenes in data.items():
        logging.info(f"{room}: {', '.join(scenes)}")
    logging.info(f"House-wide: {', '.join(house)}")
    apply(accessories)


if __name__ == "__main__":
    main()
