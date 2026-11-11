# uos-docker

[UniFi OS Server](https://help.ui.com/hc/en-us/articles/34210126298775) as a Docker image, rebuilt
automatically when Ubiquiti releases a new version.

> UniFi OS Server is proprietary Ubiquiti software; this repo only contains the tooling around it.

## How it is built

Ubiquiti does not publish a Docker image, only an installer. Two stages turn it into one:

1. **`uosserver` (base)**, `.github/workflows/uosserver.yml`. For the version in `uos-version.env`
   the workflow downloads the installer for each architecture (checksum verified), runs it on a
   native runner (amd64 and arm64), exports the `uosserver` image the installer loads into
   podman, and publishes `ghcr.io/<owner>/uosserver:<version>` as a multi-arch image. Skipped
   when that tag already exists.
2. **`uos-docker` (this image)**, `Dockerfile`. A thin layer on the base that makes it run under
   Docker: sets the product environment, masks the console getty units, and installs
   `docker-entrypoint.sh`, which persists a system UUID, writes the platform files UniFi OS
   reads, fixes directory ownership, applies `UOS_SYSTEM_IP`, installs a user-provided TLS certificate (`import-cert.sh`), and
   `exec`s systemd.

```
update.yml   daily: Ubiquiti API -> PR editing uos-version.env
   merge
publish.yml  on every push to main:  uosserver.yml (if version is new)  ->  build + push uos-docker
```

## Tags

Every merge to `main` publishes `ghcr.io/jacobalberty/uos-docker`:

| Build | Tag |
|---|---|
| first build of a UniFi OS version | `5.1.42` |
| next merge, same UniFi OS version | `5.1.42-1` |
| the one after | `5.1.42-2` |
| first build of the next UniFi OS version | `5.1.43` |

`latest` always points at the newest build. Pin a full tag in production.

## Running

See [`compose.example.yaml`](compose.example.yaml). Requirements: cgroup v2 host, `cgroup: host`,
`NET_RAW`/`NET_ADMIN`, and the tmpfs mounts shown. Adopt devices with
`set-inform http://<UOS_SYSTEM_IP>:8080/inform`. All state lives under the seven mounted
directories; back them up (and take `.unf` backups from the UI).

| Variable | Meaning |
|---|---|
| `UOS_SYSTEM_IP` | Hostname or IP devices use for inform |
| `UOS_UUID` | Fixed system UUID (otherwise generated once and kept in `/data/uos_uuid`) |
| `CERTDIR` | Directory with your TLS certificate, default `/unifi/cert` |
| `CERTNAME` | Certificate file name, default `cert.pem` |
| `CERT_PRIVATE_NAME` | Private key file name, default `privkey.pem` |
| `CERT_IS_CHAIN` | `true` if `CERTNAME` already contains the full chain, default `false` |

## Custom SSL certificate

By default UniFi OS serves a self-signed certificate. To use your own, mount a directory at
`/unifi/cert` (read-only is fine) containing:

```
cert.pem      # the certificate
privkey.pem   # its private key (unencrypted)
chain.pem     # optional: intermediate certificates
ca.pem        # optional: root certificate
```

```yaml
    volumes:
      - ./certs:/unifi/cert:ro
```

On every container start the entrypoint combines `cert.pem` + `chain.pem` + `ca.pem` (or just
`cert.pem` when `CERT_IS_CHAIN=true`), checks that the key matches the certificate, and installs
the result as `/data/unifi-core/config/unifi-core.crt` / `.key`, which is what the console serves
on port 443. Renew by replacing the files and restarting the container. If the files are missing,
mismatched or invalid, a warning is logged and the existing certificate is kept.

Notes:
- A certificate uploaded through the UniFi OS web UI takes precedence over the one installed here.
- This covers the UniFi OS console (443). The Network application's own ports (8443, inform on
  8080) are not changed.

## Repository setup (once)

- Add a `PAT` secret (contents + pull requests: write) so the update PRs trigger the checks. Without
  it, enable Settings > Actions > "Allow GitHub Actions to create and approve pull requests".
- Run `Extract uosserver base image` manually once to validate the extraction before relying on it.

## Credits

The idea of packaging UniFi OS Server for Docker comes from
[lemker/unifi-os-server](https://github.com/lemker/unifi-os-server); the entrypoint here is an
independent implementation of the same behaviour.
