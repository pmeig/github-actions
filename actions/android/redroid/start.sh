#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  echo "::error::$*"
  exit 1
}

for value in "$COUNT" "$MEMORY_PER_DEVICE" "$CPUS_PER_DEVICE" "$WIDTH" "$HEIGHT" "$DPI" "$TIMEOUT" "$STAGGER"
do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "expected a positive integer, got '$value'"
done

[[ "$TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || fail "invalid Redroid image tag '$TAG'"
IMAGE="redroid/redroid:$TAG"

command -v adb > /dev/null || fail "adb not found: run android/setup (platform-tools) first"
command -v docker > /dev/null || fail "docker not found"
[ "$(uname -s)" == 'Linux' ] || fail "Redroid requires a Linux Docker host"
docker info > /dev/null || fail "Docker is not reachable from this runner"

cpus=$(getconf _NPROCESSORS_ONLN)
available=$(free -m | awk '/^Mem:/ {print $7}')
[[ "$cpus" =~ ^[1-9][0-9]*$ ]] || fail "could not determine the available CPU count"
[[ "$available" =~ ^[0-9]+$ ]] || fail "could not determine available host memory"

label="pmeig.redroid.run=${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${GITHUB_JOB}-${RUNNER_NAME}"
suffix=$(printf '%s' "${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${GITHUB_JOB}-${RUNNER_NAME}" | tr -cs '[:alnum:]_.-' '-')
network="${NETWORK:-pmeig-redroid-${suffix}}"
[[ "$network" =~ ^[a-zA-Z0-9_.-]+$ ]] || fail "invalid Docker network name '$network'"

{
  echo "network=$network"
  echo "label=$label"
} >> "$GITHUB_OUTPUT"

if docker network inspect "$network" > /dev/null 2>&1
then
  network_label=$(docker network inspect -f '{{index .Labels "pmeig.redroid.run"}}' "$network")
  [ "$network_label" == "${label#*=}" ] || fail "Docker network '$network' already exists with a different Redroid run label"
else
  docker network create --label "$label" "$network" > /dev/null
fi

runner=$(cat /etc/hostname)
docker network connect "$network" "$runner" > /dev/null 2>&1 || true
docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}} {{end}}' "$runner" | grep -qw "$network" \
  || fail "the runner could not join Docker network '$network'"

wanted=$COUNT
fit_memory=$(( available / MEMORY_PER_DEVICE ))
fit_cpus=$(( cpus / CPUS_PER_DEVICE ))
(( fit_memory < 1 )) && fit_memory=1
(( fit_cpus < 1 )) && fit_cpus=1
fit=$fit_memory
(( fit_cpus < fit )) && fit=$fit_cpus
(( COUNT > fit )) && COUNT=$fit
if (( COUNT < wanted ))
then
  echo "::warning::$wanted Redroid devices wanted, $COUNT started: $available MB of memory (${MEMORY_PER_DEVICE} MB each) and $cpus CPU(s) (${CPUS_PER_DEVICE} each) available on the host"
fi
echo "Redroid devices: $COUNT of $wanted wanted, ${MEMORY_PER_DEVICE} MB and ${CPUS_PER_DEVICE} CPU(s) per device"

{
  echo "count=$COUNT"
} >> "$GITHUB_OUTPUT"

docker pull "$IMAGE"

diagnose() {
  local name=$1 serial=${2:-none}
  echo "::group::Redroid diagnostic: $name"
  docker ps -a --filter "name=$name" --format 'container: {{.Status}}'
  echo "--- ADB devices"
  adb devices -l
  if [ "$serial" != 'none' ]
  then
    echo "--- Android boot state"
    timeout 10 adb -s "$serial" shell getprop sys.boot_completed 2>&1 | tr -d '\r' || true
  fi
  echo "--- Docker logs (last 120 lines)"
  docker logs --tail 120 "$name" 2>&1 || echo "::warning::could not read Docker logs for $name"
  echo "--- Host"
  uname -a
  uptime
  free -m
  docker stats --no-stream "$name" 2>&1 || echo "::warning::could not read Docker stats for $name"
  echo "::endgroup::"
}

names=()
for ((index = 1; index <= COUNT; index++))
do
  name="redroid-${suffix}-${index}"
  docker rm -f "$name" > /dev/null 2>&1 || true
  if ! docker run -d --name "$name" --label "$label" --network "$network" --privileged \
    --memory-reservation "${MEMORY_PER_DEVICE}m" \
    "$IMAGE" \
    "androidboot.redroid_width=$WIDTH" \
    "androidboot.redroid_height=$HEIGHT" \
    "androidboot.redroid_dpi=$DPI" \
    androidboot.redroid_gpu_mode=auto \
    androidboot.use_memfd=true > /dev/null
  then
    echo "::error::could not start Redroid container '$name'; verify the Docker host supports binderfs, ashmem or memfd, IPv6, DMA-BUF heaps and 4 KB pages"
    docker logs --tail 120 "$name" 2>&1 || true
    exit 1
  fi
  names+=("$name")
  (( index < COUNT )) && sleep "$STAGGER"
done

devices=()
deadline=$((SECONDS + TIMEOUT))
for name in "${names[@]}"
do
  ip=''
  serial=''
  last=$SECONDS
  until [ -n "$serial" ] \
    && [ "$(timeout 10 adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n ')" == '1' ] \
    && timeout 10 adb -s "$serial" shell pm path android > /dev/null 2>&1
  do
    if [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)" != 'true' ]
    then
      diagnose "$name" "${serial:-none}"
      fail "Redroid container '$name' stopped before Android booted"
    fi
    if (( SECONDS > deadline ))
    then
      diagnose "$name" "${serial:-none}"
      fail "Redroid device '$name' did not boot in ${TIMEOUT}s; verify the Docker host kernel requirements (binderfs, ashmem or memfd, IPv6, DMA-BUF heaps, 4 KB pages)"
    fi
    if [ -z "$ip" ]
    then
      ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name")
      [ -n "$ip" ] || { diagnose "$name" none; fail "could not find the Docker IP for '$name'"; }
      serial="$ip:5555"
    fi
    adb connect "$serial" > /dev/null 2>&1 || true
    if (( SECONDS - last >= 60 ))
    then
      last=$SECONDS
      echo "$name: still booting ($(( deadline - SECONDS ))s left, ADB: $(adb devices | awk -v s="$serial" '$1 == s {print $2}'), host available: $(free -m | awk '/^Mem:/ {print $7}') MB)"
    fi
    sleep 5
  done
  echo "$name ready: $serial"
  devices+=("$serial")
done

echo "devices=$(IFS=,; echo "${devices[*]}")" >> "$GITHUB_OUTPUT"
