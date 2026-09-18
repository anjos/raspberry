const TARGET_IEEE = "0xe4b063fffe6837a1";
const ENDPOINTS = [1, 2];
const DISABLED_REPORTING = {
    minimumReportInterval: 0,
    maximumReportInterval: 65535,
};
const REPORTING_POLICY = [
    {
        cluster: "haElectricalMeasurement",
        attribute: "activePower",
        minimumReportInterval: 300,
        maximumReportInterval: 6000,
        reportableChange: 5,
    },
    {cluster: "haElectricalMeasurement", attribute: "rmsCurrent", ...DISABLED_REPORTING, reportableChange: 50},
    {cluster: "haElectricalMeasurement", attribute: "rmsVoltage", ...DISABLED_REPORTING, reportableChange: 500},
    {cluster: "haElectricalMeasurement", attribute: "acFrequency", ...DISABLED_REPORTING, reportableChange: 100},
    {cluster: "haElectricalMeasurement", attribute: "apparentPower", ...DISABLED_REPORTING, reportableChange: 1},
    {cluster: "haElectricalMeasurement", attribute: "reactivePower", ...DISABLED_REPORTING, reportableChange: 1},
    {cluster: "haElectricalMeasurement", attribute: "powerFactor", ...DISABLED_REPORTING, reportableChange: 1},
    {cluster: "seMetering", attribute: "currentSummDelivered", ...DISABLED_REPORTING, reportableChange: 100000},
    {cluster: "seMetering", attribute: "currentSummReceived", ...DISABLED_REPORTING, reportableChange: 100000},
];

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

export default class ShowerRoomReporting {
    constructor(
        zigbee,
        mqtt,
        state,
        publishEntityState,
        eventBus,
        enableDisableExtension,
        restartCallback,
        addExtension,
        settings,
        logger,
    ) {
        this.zigbee = zigbee;
        this.eventBus = eventBus;
        this.logger = logger;
        this.timers = new Set();
        this.running = false;
        this.retryCount = 0;
    }

    start() {
        this.eventBus.onDeviceAnnounce(this, ({device}) => {
            if (device.ieeeAddr === TARGET_IEEE) {
                this.schedule(10_000, "device announce");
            }
        });

        this.eventBus.onReconfigure(this, ({device}) => {
            if (device.ieeeAddr === TARGET_IEEE) {
                this.schedule(15_000, "device reconfigure");
            }
        });

        // Run after built-in device configuration has completed during startup.
        this.schedule(60_000, "Zigbee2MQTT startup");
    }

    stop() {
        for (const timer of this.timers) {
            clearTimeout(timer);
        }
        this.timers.clear();
        this.eventBus.removeListeners(this);
    }

    schedule(delay, reason) {
        const timer = setTimeout(async () => {
            this.timers.delete(timer);
            await this.apply(reason);
        }, delay);
        this.timers.add(timer);
    }

    async apply(reason) {
        if (this.running) {
            return;
        }

        this.running = true;
        let failures = 0;
        try {
            const device = this.zigbee.resolveEntity(TARGET_IEEE);
            if (!device || !device.isDevice()) {
                throw new Error(`device ${TARGET_IEEE} is not available`);
            }

            for (const endpointID of ENDPOINTS) {
                const endpoint = device.endpoint(endpointID);
                if (!endpoint) {
                    throw new Error(`endpoint ${endpointID} is not available`);
                }

                for (const {cluster, ...config} of REPORTING_POLICY) {
                    try {
                        // The Shelly can time out when many attributes are configured in one ZCL command.
                        await endpoint.configureReporting(cluster, [config]);
                    } catch (error) {
                        failures += 1;
                        this.logger.error(
                            `[ShowerRoomReporting] Failed ${cluster}/${config.attribute} on endpoint ${endpointID}: ${error}`,
                        );
                    }
                    await sleep(250);
                }
            }

            if (failures === 0) {
                this.retryCount = 0;
                this.logger.info(
                    `[ShowerRoomReporting] Applied reporting policy after ${reason}`,
                );
            } else if (this.retryCount < 3) {
                this.retryCount += 1;
                this.schedule(30_000, `retry ${this.retryCount}`);
            }
        } catch (error) {
            this.logger.error(
                `[ShowerRoomReporting] Failed to apply reporting policy after ${reason}: ${error}`,
            );
            if (this.retryCount < 3) {
                this.retryCount += 1;
                this.schedule(30_000, `retry ${this.retryCount}`);
            }
        } finally {
            this.running = false;
        }
    }
}
