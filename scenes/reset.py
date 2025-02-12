#!/usr/bin/env python3

"""Resets all scenes in a room."""

import argparse
import json
import logging
import os
import time
import typing

import paho.mqtt.enums
import paho.mqtt.publish
import yaml
from yamlcore import CoreLoader


def parse_yaml_files(file_paths: list[str]):
    """Parse the given YAML files and return a combined dictionary."""

    data = {}
    for file_path in file_paths:
        try:
            with open(file_path, "r") as file:
                # Load the YAML file and update the data dictionary
                file_data = yaml.load(file, Loader=CoreLoader)
                data.update(file_data)

        except Exception as e:
            logging.error(f"Error parsing {file_path}: {e}")

    return data


def setup_scene(
    client: dict[str, typing.Any], commands: dict[str, dict[str, typing.Any]]
):
    """Sets up a scene using MQTT."""

    messages = [
        (f"zigbee2mqtt/{name}/set", json.dumps(cmd)) for name, cmd in commands.items()
    ]
    paho.mqtt.publish.multiple(messages, **client)


def remove_scene(client, room: str, scene_id: int):
    """Removes a scene using MQTT."""

    topic = f"zigbee2mqtt/{room}/set"
    payload = json.dumps(dict(scene_remove=scene_id))
    paho.mqtt.publish.single(topic, payload, **client)


def store_scene(
    client,
    room: str,
    scene_id: int,
    scene_name: str,
    group_id: int,
    lights: dict[str, typing.Any],
):
    """Stores a scene using MQTT."""

    topic = f"zigbee2mqtt/{room}/set"
    payload = json.dumps(dict(scene_store=dict(ID=scene_id, name=scene_name)))
    paho.mqtt.publish.single(topic, payload, **client)

    # send a store command for each light to force Ikea bulbs to store scenes
    messages = []
    for light, state in lights.items():
        topic = f"zigbee2mqtt/{light}/set"
        payload = json.dumps(
            dict(
                scene_add=dict(
                    ID=scene_id,
                    name=scene_name,
                    group_id=group_id,
                    transition=0,
                    **state,
                )
            )
        )
        messages.append((topic, payload))

    paho.mqtt.publish.multiple(messages, **client)


def main():
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
    )
    parser = argparse.ArgumentParser(description="Resets scenes in Zigbee2MQTT")

    # Add an argument to accept one or more YAML files
    parser.add_argument(
        "yaml_file",
        metavar="YAML_FILE",
        type=str,
        help="Path to one YAML files containing scene descriptors to be parsed",
    )

    parser.add_argument(
        "-w",
        "--wait",
        metavar="SECONDS",
        type=int,
        default=5,
        help="Number of seconds to wait trying to store the scene",
    )

    parser.add_argument(
        "-s",
        "--only-scene",
        metavar="NAME",
        required=False,
        type=str,
        help="If specified, then only this scene in the file is set",
    )

    args = parser.parse_args()
    data = parse_yaml_files([args.yaml_file])
    client = dict(
        hostname="raspberry.local",
        port=1883,
        protocol=paho.mqtt.enums.MQTTProtocolVersion.MQTTv5,
    )

    # Currently attributed group IDs on zigbee2mqtt (check the "Groups" tab)
    GROUP_ID_DICT = {
        "office": 1,
        "david": 2,
        "office-ceiling-lights": 3,
        "david-ceiling-lights": 4,
        "a2": 5,
        "kitchen": 6,
        "balcony": 7,
        "living-room": 8,
        "living-room-ceiling-lights": 9,
        "living-room-table-lights": 10,
        "entrance": 11,
        "entrance-ceiling-lights": 12,
        "entrance-console-lights": 13,
        "balcony-ceiling-lights": 14,
    }
    group_id = GROUP_ID_DICT[os.path.splitext(os.path.basename(args.yaml_file))[0]]
    logging.info(f"Group ID set to {group_id} (`{args.yaml_file}`)")

    for room, scenes in data.items():
        logging.info(f"Parsing scenes for `{room}`...")
        for id, (scene, commands) in enumerate(scenes.items()):
            if (args.only_scene is not None) and (scene != args.only_scene):
                logging.info(f"Skipping scene `{scene}` (id: {id + 1}) for `{room}`...")
                continue
            logging.info(f"Setting up scene `{scene}` (id: {id + 1}) at `{room}`...")
            remove_scene(client, room, id + 1)
            setup_scene(client, commands)
            time.sleep(args.wait)
            store_scene(client, room, id + 1, scene, group_id, commands)
            time.sleep(args.wait)


if __name__ == "__main__":
    main()
