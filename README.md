# qits-oci-postgresql

The platform's PostgreSQL image, and the platform's first **deployable image**: a repository that
holds a Dockerfile and nothing else, yet is deployed as a service exactly like a Quarkus component.

That is the whole point of it. A database is not a qits application, but it needs the same things an
application needs — a build per commit, a version to name, an environment to run in, and an address
peers can dial. Giving it the ordinary lifecycle costs one Dockerfile and three config files, and
costs the platform no new concept at all.

## Lifecycle

1. **Push** to `main` — `.config/qits/ci-post-receive.yml` builds the image and pushes it under the
   built sha.
2. **Release** — qits-workspaces stamps a CalVer, tags the commit and publishes `SCMRelease`.
   `.config/qits/ci-event-release.yml` builds the tagged commit, pushes the version tag, and its
   green run makes qits-ci announce one `SoftwareRelease`.
3. **Promotion** — the release moves `environment/prod`, the branch named in
   `.config/qits/deployments.yml`.
4. **Deploy** — that push is an ordinary CI-hot build, and the environment listening to the branch
   deploys the sha-tagged image.

Nothing in that list is special-cased for this repository.

## Reaching it

Peers dial the wire alias inside the environment's networks:

    prod-qits-oci-postgresql:5432

There is no gateway route. Routes are an enum in the gateway and serve HTTP; a TCP peer needs
neither.

## PoC caveats

Both of these are deliberate, and both are settled later by the real configuration mechanism —
volumes and environment stay deployer-side run-args by design, because config is the trust domain
that already holds the docker socket.

- **The password is a placeholder.** `POSTGRES_PASSWORD=qits-poc` is baked into the image so it
  starts at all. Treat nothing here as a credential.
- **There is no data volume.** The data dies with the container, and every deployment is a fresh
  database.
