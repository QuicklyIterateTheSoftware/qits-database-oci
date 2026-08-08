# The platform's PostgreSQL image. It adds nothing to the upstream image yet — the repository
# exists so a database rides the same push/release/deploy lifecycle as every other component.
#
# The base is pulled through the platform's OCI mirror, never from docker.io directly. The `hub`
# namespace maps to docker.io, and a single-component name under it means `library/`.
FROM localhost:8081/hub/library/postgres:18.4

# PoC PLACEHOLDER, not a credential. The image needs a password to start at all, and the real
# mechanism — per-deployment configuration — comes later. Nothing depends on this value.
ENV POSTGRES_PASSWORD=qits-poc
