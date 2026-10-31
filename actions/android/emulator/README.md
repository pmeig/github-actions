# android/emulator

Starts Android emulators in Docker containers next to the runner (Docker socket of the host, KVM required).
Inputs and outputs: see `action.yml`.

## Architecture

```
job (runner container) --docker socket--> host Docker --> emulator containers (adb :5555, same network as the runner)
                                              |
                      image: budtmo/docker-android:emulator_14.0            (android-api 34, default)
                         or  pmeig-emulator:android<api>-<hash Dockerfile>   (built from docker/Dockerfile)
                                              |
                      snapshot (optional): pmeig-emulator-warm:<hash of image, device, args>
```

## Android version: `android-api`

| `android-api` | Android | Image |
|---|---|---|
| `34` (default) | 14 | `image` as it is |
| `33`, `35` | 13, 15 | built from `docker/Dockerfile` |
| `36`, `36.1` | 16 | built from `docker/Dockerfile` |

Above 34 the action builds the image once per Docker host and per API level (lock: a Docker network, parallel jobs wait,
`image-timeout`), tagged `pmeig-emulator:android<api>-<hash of the Dockerfile>`. The Dockerfile (pinned base by digest)
installs `system-images;android-<api>;google_apis;x86_64` and adds the version to the API table of budtmo's launcher.
The snapshot hash includes the image tag: each API keeps its own snapshot. The output `api` returns the level used.
Adapted from https://github.com/Hashim-K/android-agent-lab (MIT).

```yaml
- uses: pmeig/github-actions/actions/android/emulator@main
  with:
    android-api: '36.1'
    snapshot: 'true'
```
