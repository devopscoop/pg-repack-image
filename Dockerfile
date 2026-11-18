# Packages pg_repack (https://github.com/reorg/pg_repack) as a CloudNativePG
# image-volume extension image
# (https://cloudnative-pg.io/docs/devel/imagevolume_extensions):
#   lib/              the extension module (appended to dynamic_library_path
#                     by CNPG)
#   share/extension/  the control and SQL files (appended to
#                     extension_control_path by CNPG)
#   bin/              the pg_repack client, which must match the extension's
#                     version; run it from the postgres pod by its full path
#   licenses/         the upstream BSD-3-Clause license
#
# Build args pin everything; bump them deliberately. PG_IMAGE and PG_MAJOR
# must move together, and the image only works against the same postgres
# major and distro it was built in. PKG_VERSION is the PGDG package version:
# the pgdg13+1 and +2 builds of 1.5.3 install on any 18.x, while
# 1.5.3-2.pgdg13+1 requires a server newer than 18.7.
ARG PG_IMAGE=ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie

# Install inside the exact server image so the ABI always matches.
FROM $PG_IMAGE AS builder
ARG PG_MAJOR=18
ARG PKG_VERSION=1.5.3-1.pgdg13+2
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      "postgresql-${PG_MAJOR}-repack=${PKG_VERSION}"
RUN mkdir -p /out/lib/bitcode /out/share/extension /out/bin /out/licenses/pg_repack \
 && cp "/usr/lib/postgresql/${PG_MAJOR}/lib/pg_repack.so" /out/lib/ \
 && cp -r "/usr/lib/postgresql/${PG_MAJOR}/lib/bitcode/pg_repack" \
          "/usr/lib/postgresql/${PG_MAJOR}/lib/bitcode/pg_repack.index.bc" /out/lib/bitcode/ \
 && cp /usr/share/postgresql/${PG_MAJOR}/extension/pg_repack* /out/share/extension/ \
 && cp "/usr/lib/postgresql/${PG_MAJOR}/bin/pg_repack" /out/bin/ \
 && cp "/usr/share/doc/postgresql-${PG_MAJOR}-repack/copyright" /out/licenses/pg_repack/

FROM scratch
COPY --from=builder /out/ /
