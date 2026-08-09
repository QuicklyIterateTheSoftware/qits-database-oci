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

## Passwords

Nothing in this repository is a credential. `POSTGRES_PASSWORD=qits-poc` in the Dockerfile is a
bare-boot placeholder so a throwaway `docker run` starts at all, and it is dead on the platform from
the very first boot: the bootstrap CLI starts the container with `-e POSTGRES_PASSWORD=<randomized>`
and the deployer's run-args carry the same override, so a docker `-e` beats the Dockerfile `ENV`
every time. `qits-poc` never reaches a platform data directory.

The randomized superuser password is recorded in the operator's `.qits-bootstrap.env`. That file is
the only copy — see *Recovery* below for why losing it hurts.

Per-service roles and databases are **not** created here. There are no init scripts in this image.
A repository asks for a database by declaring it in its own `.config/qits/deployments.yml`:

    resources: postgresql:db

qits-deployments creates the role and the database before it starts the container, keeps the
generated password in its own registry, and injects the connection details as environment variables.
Provisioning rides the deployment, so it never needs a standing operator.

Volumes and environment stay deployer-side run-args by design, because config is the trust domain
that already holds the docker socket.

## Data volume

The named volume `qits-oci-postgresql-data` mounts at **`/var/lib/postgresql`**.

> **postgres:18 moved the layout.** `PGDATA` is now `/var/lib/postgresql/18/docker`, and the image's
> `VOLUME` is the parent `/var/lib/postgresql`. A 17-style mount at `/var/lib/postgresql/data`
> therefore covers a directory postgres does not use: the server starts, everything looks healthy,
> and `PGDATA` lives in the container's writable layer. The data then dies silently with the
> container. Mount the parent.

## Host admin port

The container publishes `127.0.0.1:5433 -> 5432` (`QITS_PG_PORT`). The bootstrap CLI provisions over
plain JDBC from the host, before any deployer exists to do it, so it needs an address it can dial
from outside the network. 5433 avoids a collision with a host postgres. It is bound to `127.0.0.1`
like the registry port — never to `0.0.0.0` — and the superuser password is still required.

In-network peers ignore all of that and dial the wire alias on 5432.

## Ordering

This deployment must be **ACTIVE before any application that declares a postgresql resource
deploys**. A consumer's deployment provisions its role and database against a running server; if the
server is not there yet, the deployment fails. Never queue this beside a consumer — let it settle
first.

## Recovery

There is a circularity: the deployer starts postgres, and the deployer stores its own state *in*
postgres. If both are down, nothing can start the other. Break the loop by hand, from the host image
cache:

    docker run -d --name prod-qits-oci-postgresql \
      --network qits-net \
      -v qits-oci-postgresql-data:/var/lib/postgresql \
      -e POSTGRES_PASSWORD=<from .qits-bootstrap.env> \
      <cached image>

The container name is the wire alias, so it resolves for peers the moment it is up and dependents
reconnect on their own.

## Rotating a password

`POSTGRES_PASSWORD` only applies at initdb, on a **fresh** data directory. Changing it on a running
volume does nothing at all.

- **Service roles** are owned by the deployer's `pd_resource` registry. Delete the row and redeploy:
  the reconcile arm generates a new password and `ALTER ROLE`s the role to match.
- **The superuser** is manual: `ALTER ROLE postgres PASSWORD '<new>'`, then update
  `.qits-bootstrap.env` so the next bootstrap agrees with the volume.
