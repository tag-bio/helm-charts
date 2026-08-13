# tag-bio/helm-charts

Rancher catalog repository for the **tagbio-platform** chart. Rancher (2.5.x,
`cm.dev.tag.bio`) serves this repo as the Helm-v3 catalog `tagbio-platform`
(branch `master`); every directory under `charts/tagbio-platform-chart/<version>/`
is one immutable chart version offered in the app-upgrade dropdown.

## Layout

```
charts/tagbio-platform-chart/<version>/
  Chart.yaml                  # version: <version> (must match the dir name)
  values.yaml                 # chart defaults; per-env values come from Rancher app answers
  charts/jupyterhub-0.10.6.tgz  # VENDORED z2jh chart (we patch inside it - see below)
  templates/                  # platform templates (public-fcs, core-stack, metacontroller, ...)
```

## Cutting a new version

1. `cp -r <latest> <new>` and bump `version:` in `<new>/Chart.yaml`.
2. Make changes in the NEW directory only — published versions are immutable.
3. Validate: `helm lint <new>` and
   `helm template t <new> --set jupyterhub.proxy.secretToken=$(openssl rand -hex 32) --set jupyterhub.hub.cookieSecret=$(openssl rand -hex 32)`.
4. Push to `master`; refresh the catalog in Rancher; upgrade apps per environment.
5. **macOS gotcha**: when repacking the vendored tgz, use
   `COPYFILE_DISABLE=1 tar --no-xattrs -czf ...` — AppleDouble `._*` entries make
   helm reject the chart ("content outside the base directory").

## The vendored jupyterhub chart

`charts/jupyterhub-0.10.6.tgz` is z2jh 0.10.6 **with local patches** (the chart
templates and the `files/hub/*.py` rendered into the hub's config live inside
it). We cannot move to a modern z2jh chart until clusters leave k8s 1.18
(modern charts require ≥1.20+). To patch: untar, edit, repack (see gotcha
above), verify with `tar -xzOf`.

Current patches (since 1.3.168), both backward-compatible with the old hub image:
- `files/hub/jupyterhub_config.py`: `kubernetes` → try/except
  `kubernetes_asyncio` import (modern hub images only ship the asyncio client)
- `files/hub/z2jh.py`: `collections` → `collections.abc` for `Mapping`
  (removed in Python 3.10)

## Version history (modernization era)

| Version | Date | Changes |
|---|---|---|
| 1.3.167 | pre-2026-08 | Last legacy version (hub `k8s-hub:0.10.6` = JupyterHub 1.2.2) |
| 1.3.168 | 2026-08-12 | Hub image → `jupyterhub/k8s-hub:3.3.8` (**JupyterHub 4.1.6**) + the two Python-3.11 shims. Required by tagbio-notebook images built from Aug 2026 (singleuser jupyterhub 5.x needs a scopes-aware hub; old hub 500s with `KeyError: 'scopes'`) |
| 1.3.169 | 2026-08-12 | **Self-healing OAuth**: `hub.extraConfig.99-derive-oauth-urls` derives authorize/token/callback URLs from `auth.custom.config.token_url` and `ingress.hosts` whenever the `OAUTH2_*`/`OAUTH_CALLBACK_URL` env vars are absent. Motivated by repeated loss of `hub.extraEnv` answers in app upgrades (2026-08-07 and 2026-08-12, each causing site-down redirect loops). Explicit `extraEnv` still wins |
| 1.3.170 | 2026-08-13 | **Right-sized FC memory reservations** (`tagbio.publicFcs.*.reservation.memory`). Previously reservation ≡ JVM `Xmx` → ~95% node memory committed at ~50% real usage → surge rollouts (`maxSurge: 1, maxUnavailable: 0`) deadlocked with "Insufficient memory" (9 FCs stuck on demo). New values: max(observed peak × 1.2, 40% of Xmx), min 1G; unmeasured FCs 50% of Xmx; `fc-vip` *raised* 4G→7G (it was under-reserved). No limits are set, so runtime behavior is unchanged and `Xmx` still caps each heap |

## Per-environment upgrade procedure (to ≥ 1.3.170)

1. **Pre-flight**: nodes need docker ≥ 20.10.10 for the new hub image
   (`kubectl get nodes -o jsonpath='...containerRuntimeVersion...'`). Back up:
   hub deployment yaml, `hub-config` configmap, and
   `/srv/jupyterhub/jupyterhub.sqlite` from the hub pod (the new hub migrates
   the DB **forward-only** — rollback to a 1.x hub requires restoring this file).
2. Catalog refresh → app upgrade → select version, **check the answers in the
   form before applying** (see pitfall below).
3. After upgrade: user servers that were running under the old hub get
   "500: OAuth configuration error" — each user stops/starts their server
   (or delete their `jupyter-<user>` pod).
4. FCs roll with `maxSurge: 1`; on chart ≥ 1.3.170 they fit. On older charts,
   stuck `Pending ... Insufficient memory` pods are unstuck by deleting the
   OLD pod of the same deployment.

## Answers pitfalls (Rancher app YAML)

- `hub.extraEnv` and `hub.extraConfig` must be **children of `jupyterhub.hub`**.
  A recurring failure mode is `extraEnv` nested under `extraConfig`, or either
  placed under `jupyterhub:` directly — Helm silently ignores both.
- Since 1.3.169 a lost/misplaced `extraEnv` no longer breaks login (the chart
  derives the URLs), but per-env answers should still carry the explicit values.
- Planned: an `environments/` directory in this repo holding each environment's
  canonical answers/values file, so UI edits are copy-paste from reviewed files
  rather than hand-typed YAML.
