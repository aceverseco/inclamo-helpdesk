# The image under test as a newer release, for the upgrade tests when no
# earlier release exists to upgrade from: another overlay version and one more
# overlay migration, nothing else.
ARG BASE
FROM ${BASE}
ARG VERSION
RUN printf '%s\n' "${VERSION}" > custom/INCLAMO_VERSION
COPY 20990101000000_create_install_test_markers.rb custom/db/migrate/
