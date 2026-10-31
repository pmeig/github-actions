# android/emulator

Starts Android emulators in Docker containers next to the runner (Docker socket of the host, KVM required).
Inputs and outputs: see `action.yml`.

## Architecture

```
job (runner container) --docker socket--> host Docker --> emulator containers (adb :5555, same network as the runner)
                                              |
                      image: budtmo/docker-android:emulator_14.0   (android-api 34, default)
                         or  android-emulator:api<api>            (built from docker/Dockerfile, shared with docker compose)
                                              |
                      snapshot (optional): pmeig-emulator-warm:<hash of image id, device, args>
```

## Android version: `android-api`

| `android-api` | Android | Image |
|---|---|---|
| `34` (default) | 14 | `image` as it is |
| `33`, `35` | 13, 15 | `android-emulator:api<api>`, built from `docker/Dockerfile` |
| `36` (`36.1`: unstable, see below) | 16 | `android-emulator:api<api>`, built from `docker/Dockerfile` |

Above 34 the image is built once per Docker host and per API level: a Docker network is the lock, parallel jobs wait
(`image-timeout`) then reuse it. The log says `image <tag>: built` (once) or `image <tag>: reused`; likewise
`snapshot <tag>: built|reused`. The image carries the label `dockerfile.hash` (hash of `docker/Dockerfile`): it is rebuilt
only when the label differs. An image without label (built by hand with `docker compose build android-emulator` in
the docker project of the host, which holds a **byte-identical copy** of the Dockerfile) is reused as it is: after a change
of the Dockerfile, rebuild it by hand or remove it. Its Dockerfile pins the base by digest, installs
`system-images;android-<api>;google_apis;x86_64`, adds the version to the API table of budtmo's launcher and gives the
data partition 4 GB (550 MB is full on Android 16). Android 16 needs more memory than 2048 MB (the system server
restarted): pass `emulator-args: '-memory 3072 -no-audio -no-boot-anim'`.
The snapshot hash includes the id of the image: each API (and each rebuild) keeps its own snapshot.
Use `36` (Android 16): the system image 36.1 (rev 4) crashes `surfaceflinger` every ~45 s on the emulator of this host (assert `hasReadColorBufferDma` in RegionSampling, with `-gpu host`, swiftshader or guest alike), `36` is stable. Android 16 draws edge to edge: a flow that taps a button at the bottom of a page must `scroll` first.
Adapted from https://github.com/Hashim-K/android-agent-lab (MIT).

```yaml
- uses: pmeig/github-actions/actions/android/emulator@main
  with:
    android-api: '36'
    emulator-args: '-memory 3072 -no-audio -no-boot-anim'
    snapshot: 'true'
```
