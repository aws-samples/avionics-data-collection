#!/usr/bin/env python3

import json
import logging
import os
import random
import sys
import threading
import time

import requests

logger = logging.getLogger(__name__)
logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)

import awsiot.greengrasscoreipc
import awsiot.greengrasscoreipc.model as model

BASE_STEP = 0.002


class State:
    def __init__(self, *, battery_percent, longitude, latitude, speed_long, speed_lat):
        self.battery_percent = battery_percent
        self.longitude = longitude
        self.latitude = latitude
        self.speed_long = speed_long
        self.speed_lat = speed_lat


def main(avionics_ip, snowcone_nfs):
    print(os.environ, avionics_ip, snowcone_nfs)
    print("Publishing periodic telemetry data...")

    ipc_client = awsiot.greengrasscoreipc.connect()

    state = State(
        battery_percent=(1.0 - random.random() / 5.0) * 100.0,
        longitude=48.15743,
        latitude=11.57549,
        speed_long=random.uniform(-BASE_STEP, BASE_STEP),
        speed_lat=random.uniform(-BASE_STEP, BASE_STEP),
    )

    # schedule the first data collection iteration
    threading.Timer(5.0, collect_data, [ipc_client, avionics_ip, snowcone_nfs, state]).start()


def collect_data(ipc_client, avionics_ip, snowcone_nfs, state):
    # for demonstration purposes, get a sample telemetry state
    payload = generate_sample_telemetry_state(state)

    # get the current avionics telemetry state from the local network
    try:
        r = requests.get("https://{}/state".format(avionics_ip), timeout=1)
        if r.status_code == 200:
            payload = json.loads(r.content)
    except:
        print(
            "failed to get telemetry from avionics_ip:{}".format(avionics_ip),
            file=sys.stderr,
        )

    # send telemetry event via Greengrass IPC into the AWS IoT Core MQTT broker
    op = ipc_client.new_publish_to_iot_core()
    request = model.PublishToIoTCoreRequest(
        topic_name="flythings/{}/avionics/telemetry".format(
            os.getenv("AWS_IOT_THING_NAME")
        ),
        qos=model.QOS.AT_LEAST_ONCE,
        payload=json.dumps(payload).encode(),
    )
    op.activate(request)
    try:
        result = op.get_response().result(timeout=5.0)
        print("successfully published message:", result)
    except Exception as e:
        print("failed to publish message:", e)

    # append latest telemetry event to Snowcone data on NFS
    try:
        with open(os.path.join(snowcone_nfs, "telemetry.json"), "a") as f:
            f.write(json.dumps(payload))
    except (PermissionError, FileNotFoundError) as e:
        print("failed to append-write telemetry event: {}".format(e))

    # download a camera image and write it to the Snowcone NFS
    try:
        r = requests.get("https://{}/sensors/camera1".format(avionics_ip), timeout=1)
        if r.status_code == 200:
            epoch_time = int(time.time())
            filename = "{}.jpeg".format(epoch_time)
            path = os.path.join(snowcone_nfs, "sensors", "camera1", filename)
            with open(path, "wb") as f:
                f.write(r.content)
    except:
        print(
            "failed to save image from camera1 on avionics_ip:{}".format(avionics_ip),
            file=sys.stderr,
        )

    # schedule the next data collection iteration
    threading.Timer(5.0, collect_data, [ipc_client, avionics_ip, snowcone_nfs, state]).start()


def generate_sample_telemetry_state(state):
    if state.battery_percent < 1.8:
        # shut down and landed
        health = False
        base_rpm = 0.0
        base_temp = 23.7
    else:
        # in-flight
        health = True
        base_rpm = 1.0
        base_temp = 42.0
        state.battery_percent -= random.random() / 10.0
        state.latitude += random.uniform(-BASE_STEP * 0.7, BASE_STEP * 0.7)
        state.longitude += random.uniform(-BASE_STEP * 0.7, BASE_STEP * 0.7)

    return {
        "sample": True,
        "timestamp": int(round(time.time() * 1000)),
        "thing_name": os.getenv("AWS_IOT_THING_NAME"),
        "health": health,
        "location": {
            "latitude": round(state.latitude, 6),
            "longitude": round(state.longitude, 6),
        },
        "battery_percent": round(state.battery_percent, 2),
        "motor_a": {
            "rpm": round(base_rpm * (3065.0 + random.random() * 21.0)),
            "temperature": round(base_temp + random.random() * 3, 1),
        },
        "motor_b": {
            "rpm": round(base_rpm * (3065.0 + random.random() * 21.0)),
            "temperature": round(base_temp + random.random() * 3, 1),
        },
        "motor_c": {
            "rpm": round(base_rpm * (3065.0 + random.random() * 21.0)),
            "temperature": round(base_temp + random.random() * 3, 1),
        },
        "motor_d": {
            "rpm": round(base_rpm * (3065.0 + random.random() * 21.0)),
            "temperature": round(base_temp + random.random() * 3, 1),
        },
    }


if __name__ == "__main__":
    # execute only if run as a script
    main(
        avionics_ip=sys.argv[1],
        snowcone_nfs=sys.argv[2],
    )
