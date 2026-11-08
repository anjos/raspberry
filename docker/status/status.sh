#!/bin/sh
# Hourly status for the index page, plus a Pushover alert (at most once a day)
# when a certificate is within ALERT_DAYS of expiry. Writes to /status:
#   status.json: certificates as served by caddy
#   health.json: CPU, memory, I/O and network (averages since the last sample),
#                temperatures, drives and APT updates, with a day of history
# The first run comes shortly after start, so the page isn't empty after a restart.
set -u

h=/host
out=/status
site=anjos.fyi
names="${site} radarr.${site}"  # the apex and wildcard certificates
alert_days=${ALERT_DAYS:-7}
interval=3600
first=30
points=24  # a day of history
iface=eth0

alert() {
    stamp="${out}/alerted-$(date +%F)"
    [ -e "${stamp}" ] && return
    rm -f "${out}"/alerted-*
    curl -fsS -m 20 -o /dev/null \
        --form-string "token=${PUSHOVER_TOKEN}" \
        --form-string "user=${PUSHOVER_USER}" \
        --form-string "title=raspberry: HTTPS certificates" \
        --form-string "message=$1" \
        --form-string "url=https://${site}" \
        --form-string "priority=1" \
        https://api.pushover.net/1/messages.json && touch "${stamp}"
}

served_cert() {
    openssl s_client -connect "${site}:443" -servername "$1" </dev/null 2>/dev/null |
        openssl x509 2>/dev/null
}

check_https() {
    list=""
    critical=""
    for name in ${names}; do
        crt=$(served_cert "${name}")
        [ -n "${crt}" ] || continue
        subject=$(echo "${crt}" | openssl x509 -noout -subject -nameopt multiline |
            sed -n 's/^ *commonName *= *//p')
        dates=$(echo "${crt}" | openssl x509 -noout -startdate -enddate -dateopt iso_8601)
        issued=$(echo "${dates}" | sed -n 's/^notBefore=//p' | tr ' ' T)
        expires=$(echo "${dates}" | sed -n 's/^notAfter=//p' | tr ' ' T)
        list="${list}$(jq -nc --arg n "${subject}" --arg i "${issued}" --arg e "${expires}" \
            '{name: $n, issued: $i, expires: $e}')
"
        echo "${crt}" | openssl x509 -noout -checkend $((alert_days * 86400)) >/dev/null ||
            critical="${critical} ${subject}"
    done

    printf '%s' "${list}" | jq -s --argjson days "${alert_days}" \
        '{checked: (now | todate), alert_days: $days, certificates: .}' \
        >"${out}/status.tmp" && mv "${out}/status.tmp" "${out}/status.json"

    if [ -z "${list}" ]; then
        alert "Could not read any certificate from ${site}: check caddy."
    elif [ -n "${critical}" ]; then
        alert "Expiring within ${alert_days} days and not renewed:${critical}. Check the caddy logs and the Cloudflare token."
    fi
}

hwmon() {  # hwmon directory with a given name
    for d in "${h}"/sys/class/hwmon/hwmon*; do
        [ "$(cat "${d}/name")" = "$1" ] && echo "${d}" && return
    done
}

fan=$(hwmon pwmfan)
nvme=$(hwmon nvme)
volt=$(hwmon rpi_volt)

# One "name value" per line, all cumulative
counters() {
    awk '{print "up", $1}' "${h}/proc/uptime"
    awk '/^cpu/ {b = $2 + $3 + $4 + $7 + $8 + $9; print $1 "_busy", b; print $1 "_total", b + $5 + $6}' \
        "${h}/proc/stat"
    awk '$3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]+|mmcblk[0-9]+)$/ {
            r += $6 * 512; w += $10 * 512; print "ioms_" $3, $13
         } END {print "read", r; print "write", w}' "${h}/proc/diskstats"
    echo "rx $(cat "${h}/sys/class/net/${iface}/statistics/rx_bytes")"
    echo "tx $(cat "${h}/sys/class/net/${iface}/statistics/tx_bytes")"
}

# Rates between two counters files, as JSON
rates() {
    speed=$(cat "${h}/sys/class/net/${iface}/speed" 2>/dev/null || echo 1000)
    [ "${speed}" -gt 0 ] 2>/dev/null || speed=1000
    awk -v speed="${speed}" '
        NR == FNR {p[$1] = $2; next}
        {n[$1] = $2}
        function pct(a, b) {return b > 0 ? 100 * a / b : 0}
        function delta(k) {return n[k] - p[k]}
        END {
            dt = delta("up"); if (dt <= 0) dt = 1
            cores = ""
            for (i = 0; ("cpu" i "_total") in n; i++)
                cores = cores (i ? "," : "") sprintf("%.1f", pct(delta("cpu" i "_busy"), delta("cpu" i "_total")))
            io = 0
            for (k in n) if (k ~ /^ioms_/) {v = pct(delta(k), dt * 1000); if (v > io) io = v}
            if (io > 100) io = 100
            rx = delta("rx") / dt; tx = delta("tx") / dt
            net = pct((rx + tx) * 8, speed * 1000000)
            printf "{\"cpu\":%.1f,\"cores\":[%s],\"io\":{\"pct\":%.1f,\"read\":%d,\"write\":%d},", \
                pct(delta("cpu_busy"), delta("cpu_total")), cores, io, delta("read") / dt, delta("write") / dt
            printf "\"net\":{\"pct\":%.2f,\"rx\":%d,\"tx\":%d,\"speed\":%d}}\n", net, rx, tx, speed
        }' "$1" "$2"
}

# Reads apt's own lists: the host's apt-daily.timer keeps them fresh
apt_check() {
    list=$(chroot "${h}" apt list --upgradable 2>/dev/null | grep upgradable)
    jq -n --argjson total "$(printf '%s' "${list}" | grep -c .)" \
        --argjson security "$(printf '%s' "${list}" | grep -c -- -security)" \
        '{upgradable: $total, security: $security, checked: (now | todate)}' >/tmp/apt.json
}

# True when a newer kernel of the running flavour is installed
reboot_required() {
    running=$(uname -r)
    newest=$(ls "${h}/usr/lib/modules" | grep -- "-${running##*-}\$" | sort -V | tail -1)
    [ -n "${newest}" ] && [ "${newest}" != "${running}" ] && echo true || echo false
}

drives() {
    for pair in System:usr Media:media Backup:backup; do
        df -kP "${h}/${pair#*:}" | awk -v name="${pair%:*}" 'NR == 2 {
            printf "{\"name\":\"%s\",\"used\":%.0f,\"total\":%.0f}\n", name, $3 * 1024, ($3 + $4) * 1024
        }'
    done | jq -sc .
}

write_health() {
    temp=$(cat "${h}/sys/class/thermal/thermal_zone0/temp")
    echo "${1}" | jq -c \
        --argjson drives "$(drives)" \
        --argjson temp "${temp}" \
        --argjson fan "$(cat "${fan}/fan1_input" 2>/dev/null || echo null)" \
        --argjson nvme "$(cat "${nvme}/temp1_input" 2>/dev/null || echo null)" \
        --argjson low "$(cat "${volt}/in0_lcrit_alarm" 2>/dev/null || echo 0)" \
        --argjson freq "$(cat "${h}/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")" \
        --argjson uptime "$(cut -d' ' -f1 "${h}/proc/uptime")" \
        --argjson load "$(awk '{printf "[%s,%s,%s]", $1, $2, $3}' "${h}/proc/loadavg")" \
        --argjson memory "$(awk '/^MemTotal/ {t = $2} /^MemAvailable/ {a = $2}
            END {printf "{\"used\":%.0f,\"total\":%.0f}", (t - a) * 1024, t * 1024}' "${h}/proc/meminfo")" \
        --argjson reboot "$(reboot_required)" \
        --slurpfile apt /tmp/apt.json \
        --slurpfile history /tmp/history.json \
        --argjson points "${points}" \
        '. + {time: (now | todate), uptime: $uptime, load: $load, memory: $memory,
              temp: ($temp / 1000), nvme_temp: (if $nvme then $nvme / 1000 else null end),
              fan_rpm: $fan, freq_mhz: ($freq / 1000), undervoltage: ($low != 0),
              drives: $drives, apt: $apt[0], reboot_required: $reboot}
         | .memory.pct = (.memory.used / .memory.total * 100)
         | .history = (($history[0] + [[.cpu, .memory.pct, .temp, .io.pct, .net.pct]])[-$points:])' \
        >/tmp/health.json || return
    jq -c .history /tmp/health.json >/tmp/history.json
    cp /tmp/health.json "${out}/health.tmp" && mv "${out}/health.tmp" "${out}/health.json"
}

trap 'exit 0' TERM

echo '[]' >/tmp/history.json
counters >/tmp/prev
wait_for=${first}
while :; do
    sleep "${wait_for}" &
    wait $!
    wait_for=${interval}
    apt_check
    counters >/tmp/now
    write_health "$(rates /tmp/prev /tmp/now)"
    mv /tmp/now /tmp/prev
    check_https
done
