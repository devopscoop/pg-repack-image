# pg-repack-image

Packages [pg_repack](https://github.com/reorg/pg_repack), which rewrites a
table and its indexes online to reclaim bloat, as a
[CloudNativePG image-volume extension image](https://cloudnative-pg.io/docs/devel/imagevolume_extensions),
published to `ghcr.io/devopscoop/pg-repack`. The CloudNativePG postgres images
do not ship pg_repack, and `VACUUM FULL`, the built-in alternative, holds an
exclusive lock for its whole run.

Consume it from a CNPG `Cluster` like:

```yaml
spec:
  postgresql:
    extensions:
      - name: pg-repack
        image:
          reference: ghcr.io/devopscoop/pg-repack:18-trixie-YYYYMMDD
```

Then create the extension once in each database you repack:

```sql
CREATE EXTENSION pg_repack;
```

## Image layout

- `lib/pg_repack.so` and its JIT bitcode — CNPG appends `<mount>/lib` to
  `dynamic_library_path` automatically.
- `share/extension/` — the control and SQL files; CNPG appends
  `<mount>/share` to `extension_control_path`.
- `bin/pg_repack` — the client. It must match the extension's version, and it
  links the postgres image's own libpq, so run it from the postgres pod.
- `licenses/` — the upstream BSD-3-Clause license.

## Running a repack

Run the client from the primary pod by its full path:

```sh
kubectl exec -it <primary-pod> -c postgres -- \
  env PGOPTIONS='-c idle_in_transaction_session_timeout=0' \
  /extensions/pg-repack/bin/pg_repack -d <database> --table <table>
```

- `PGOPTIONS` matters when the cluster sets
  `idle_in_transaction_session_timeout`. The client's second connection sits
  idle in a transaction from the start of the copy until the final swap, so
  the timeout would end it just before the swap and waste the whole run.
- `--wait-timeout` (default 60s) sets when pg_repack cancels, then after twice
  that terminates, sessions that block its lock on the table.
  `--no-kill-backend` makes it give up instead.
- pg_repack holds one snapshot for the whole copy, which holds back vacuum
  cluster-wide, and it needs free space for a second copy of the table and its
  indexes. The table needs a primary key or a unique index on NOT NULL
  columns.

## Tags

Every build pushes two tags:

- `<pg_major>-<distro>` (e.g. `18-trixie`) — moving, always the latest build.
- `<pg_major>-<distro>-<yyyymmdd>` — immutable. **Pin this one in gitops**:
  changing an extension image restarts the postgres pods, so it should be a
  reviewed git change, matching the exact-tag pinning used for `imageName`.

## Rebuild cadence and bumping

The workflow builds on push and on manual dispatch. There is no scheduled
rebuild: the image vendors no shared libraries, so it has no security fixes
to pick up between pg_repack releases. To bump:

- **pg_repack**: update `PKG_VERSION` in the Dockerfile to a newer
  [PGDG](https://apt.postgresql.org/pub/repos/apt/dists/) build of
  `postgresql-<major>-repack`. Check its `Depends` against the server minor in
  `PG_IMAGE`.
- **Postgres major or distro**: update `PG_IMAGE` and `PG_MAJOR` in the
  Dockerfile and `PG_MAJOR`/`DISTRO` in the workflow together. The image is
  only compatible with the postgres major and distro it was built in.

## Requirements on the consuming side

- PostgreSQL 18+, CloudNativePG 1.27+ (image-volume extensions).
- Kubernetes 1.35+ (or 1.33/1.34 with the `ImageVolume` feature gate) and
  containerd 2.1+ / CRI-O 1.31+.
