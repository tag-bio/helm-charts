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
3. Validate: `helm lint <new>` and — ALWAYS including a dotted release tag
   (`--set tagbio.imageTag=release-2026.01.01`; a dotted tag once broke the
   puller DaemonSet container names and failed the entire upgrade) —
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
| 2.0.5 | 2026-09-18 | **MCP Ingress on ALB sites.** `tagbio.mcp.ingress.annotations` (default `{}`) is merged over `tagbio.ingress.annotations` for the tagbio-mcp Ingress only (one map, each key once, a key set here wins). Needed on AWS ALB installs: `alb.ingress.kubernetes.io/group.order: "-1"` (the two Ingresses default to order 0 and the LB controller then sorts by name, so platform-gateway's `/` rule sorted first and swallowed `/mcp`) and `alb.ingress.kubernetes.io/healthcheck-path: /mcp/healthz` (the shared `/` is not served by tagbio-mcp, so the target group went unhealthy). When `tagbio.ingress.className` is `alb` the three `/.well-known` discovery paths get a trailing `*` (the ALB controller matches `ImplementationSpecific` paths exactly; nginx treats them as prefixes, so nginx sites are untouched). Unset → renders identical to 2.0.4 (verified on the stage-dev and muhdo values). First ALB site: UCSF. |
| 2.0.4 | 2026-09-17 | **OAuth sign-in for MCP connectors** (`tagbio.mcp.oauth.enabled`, default false): claude.ai / ChatGPT / Claude Code connect with only `https://<hosts.cluster>/mcp`, no pasted API key (keys keep working). When on: tagbio-mcp gets `TAGBIO_MCP_OAUTH_ENABLED` and two more Ingress paths (`/.well-known/oauth-protected-resource`, `/.well-known/oauth-authorization-server` — login-service is a `protected` pod, so tagbio-mcp re-publishes its metadata), login-service gets `LOGIN_SERVICE_OAUTH_RESOURCES=https://<hosts.cluster>/mcp` (+ `oauth.redirectHosts`, `oauth.allowLoopback`). The kung audience (`KUNG_IDP_CLIENT_IDS`) is set as explicit env on the kung Deployment, so it propagates on every upgrade with **no manual Secret edit**. On a release-pinned site set `tagbio.loginService.imageTag` to a branch tag that carries the feature (the pinned release image does not serve OAuth). tagbio-mcp serves three `/.well-known` discovery paths (protected-resource, oauth-authorization-server, openid-configuration); on 2.0.4 the mcp Ingress carries the site `ingressClassName` + `tagbio.ingress.annotations` so it joins the same load balancer (ALB grouping). All URLs come from one `tagbio.mcpResource` helper. **`tagbio.loginService.imageTag`** (default `""` = follow `tagbio.imageTag`), used by the Deployment and the image puller — same pattern as `rutherford.imageTag`, so a release-pinned site can take the OAuth-capable login-service alone. tagbio-mcp Ingress now carries `tagbio.ingress.className` and picks its API version by KubeVersion like platform-gateway (without the class ingress-nginx ignored it on AKS sites; no 2.0.x site had mcp enabled yet). All off/unset → renders identical to 2.0.3. |
| 2.0.3 | 2026-09-13 | login-service takes the OAuth client secret from values, else Secret `tagbio-oauth-client-secret` (in every mode, not only `externalSecrets.enabled`), else the value already in the live login-service Secret; a random uuid only on a first install with none of those. 2.0.1/2.0.2 re-rolled a random secret on every upgrade of a non-externalSecrets site, so the hub's token exchange failed (401 -> 500 on `/hub/oauth_callback`). `tagbio.metacontroller.forceRestartOnUpgrade` (default false) replaces the unconditional random pod label on tagbio-metacontroller. `tagbio.site.name` documented as the kung-services DB site key. DaemonSet `periodic-image-puller` no longer carries the chart version in its name (each upgrade used to leave the previous version's DaemonSet behind as an orphan; Helm now replaces it in place). |
| 2.0.2 | 2026-09-13 | **Migration knobs, from the UCSF adoption diff**: `tagbio.podAnnotations` on every Tag.bio pod template (ADOT/CloudWatch opt-out); chart-version label removed from pod templates (a version bump no longer restarts every pod); `tagbio.coreStack.manageConfigSecrets` (false = the site's login-service/rutherford Secrets are never rendered, UCSF SAML config); `tagbio.coreStack.replicas.<svc>`; `tagbio.redeploy.enabled`; `tagbio.storage.createJupyterVolumes`; `tagbio.ingress.tls.enabled`; login-service Service port 8000 (as kung, matching helm3x sites). |
| 2.0.1 | 2026-09-13 | Hub reads `OAUTH_CLIENT_SECRET` from Secret `tagbio-oauth-client-secret` when `hub.config.GenericOAuthenticator.client_secret` is unset (was `""`, which overrode the env var and broke OAuth login on stage-dev). Sites that set the secret in values are unaffected. |
| 2.0.0 | 2026-09-13 | **New 2.0 line for Kubernetes >=1.25** (UCSF, muhdo-prod, stage-dev): 1.3.198 + the helm3x modernization, JupyterHub chart 3.3.7, `kubeVersion: >=1.25.0-0`. See "Two version lines" above. |
| 1.3.199 | 2026-09-17 | Same as 2.0.4 for the 1.3 line: `tagbio.mcp.oauth.*` (default off) and `tagbio.loginService.imageTag` (default follows `tagbio.imageTag`). Unset → renders identical to 1.3.198 apart from the version-named puller/job objects. The kung audience is set automatically (explicit env on the kung Deployment); on demo (release-pinned) set `tagbio.loginService.imageTag: branch-master` alongside `mcp.oauth.enabled`. |
| 1.3.191 | 2026-08-26 | **Image puller honours `publicFcs.*.imageName`** (`$spec.imageName \| default $name`, as `public-fcs.yaml` already did since 1.3.186). Before, the six `fc-cbioportal-*` puller containers tried to pull nonexistent `fc-cbioportal-<product>` repos → `ImagePullBackOff` in the puller pod and the Rancher app stuck at "deploying". No `imageName` set → byte-identical to 1.3.190 |
| 1.3.190 | 2026-08-26 | **`tagbio.rutherford.imageTag`** (default `""` = follow `tagbio.imageTag`): per-component tag for the frontend, used by both the rutherford Deployment and its `periodic-image-puller` container. Same pattern as `redeploy.imageTag` (1.3.180) / `publicFcs.*.imageTag` (1.3.177): rutherford ships only `branch-*` tags, so a release-pinned environment could not take a frontend-only fix. Unset → byte-identical to 1.3.189. Applied on demo (`branch-master`, for the 1.1.3 version/copyright fix) |
| 1.3.167 | pre-2026-08 | Last legacy version (hub `k8s-hub:0.10.6` = JupyterHub 1.2.2) |
| 1.3.168 | 2026-08-12 | Hub image → `jupyterhub/k8s-hub:3.3.8` (**JupyterHub 4.1.6**) + the two Python-3.11 shims. Required by tagbio-notebook images built from Aug 2026 (singleuser jupyterhub 5.x needs a scopes-aware hub; old hub 500s with `KeyError: 'scopes'`) |
| 1.3.169 | 2026-08-12 | **Self-healing OAuth**: `hub.extraConfig.99-derive-oauth-urls` derives authorize/token/callback URLs from `auth.custom.config.token_url` and `ingress.hosts` whenever the `OAUTH2_*`/`OAUTH_CALLBACK_URL` env vars are absent. Motivated by repeated loss of `hub.extraEnv` answers in app upgrades (2026-08-07 and 2026-08-12, each causing site-down redirect loops). Explicit `extraEnv` still wins |
| 1.3.175 | 2026-08-13 | **GCP/NFS portability**: new `environment.nfs.pvPathPrefix` (default `""`) prepended to the three jupyter NFS PV paths — needed where the NFS export root is not `/` (CharacterBio/GCP: `/tagbio_storage`; its PVs were hand-created in Feb 2026 and every `helm upgrade` since died on PV immutability). Default-empty renders byte-identical to 1.3.174 on AWS/demo. Also hardens the vendored hub PVC selector guard (`kindIs "map"`) so `jupyterhub.hub.db.pvc.selector=false` in answers safely disables the selector |
| 1.3.176 | 2026-08-18 | **New public FC: `fc-cbio-tcga`** (TCGA PanCancer Atlas from cBioPortal; 32 cohorts, 10,967 samples). `enabled: false` like every other FC, so this renders byte-identical to 1.3.175 until a site opts in via answers. Sized against `fc-catalyze`, whose archive (2.98G) and R/Python plugin surface are the closest match: `Xmx: 16G`, `reservation.memory: 8G` (the 50%-of-Xmx rule for an unmeasured FC, per 1.3.170) |
| 1.3.177 | 2026-08-18 | **Per-FC image tag** (`tagbio.publicFcs.<fc>.imageTag`, default = the global `tagbio.imageTag`). A release-pinned environment ImagePullBackOff'd on `fc-cbio-tcga:release-2026-08-13`: that FC's CI publishes only `branch-master`, and no release has re-tagged it yet. Applied to BOTH the FC Deployment and the image-puller DaemonSet — patching only one leaves the puller backing off. `fc-cbio-tcga` now pins `branch-master`; every other FC is byte-identical to 1.3.176 |
| 1.3.178 | 2026-08-19 | **`fc-cbio-tcga` runs from its manifest**: `fcArgs` now pass `manifest: manifest.json` instead of `archive` + `main`, matching the repo's own shell scripts so the archive path and main file cannot drift between local and deployed. Only that FC's entry changes; every other FC still passes archive+main and renders byte-identical to 1.3.177 |
| 1.3.179 | 2026-08-20 | **Fix: `fc-cbio-tcga` CrashLoopBackOff.** 1.3.178 switched it to `manifest: manifest.json`, but with no command the engine sees the manifest's `data_model` and BUILDS from source data the image does not carry. Adds `command: run_server`. Only that FC changes |
| 1.3.180 | 2026-08-20 | **`periodic-redeploy` survives release-pinned environments.** Same failure as 1.3.177 one image over: `tagbio-ci-pipeline` is published only as `branch-master`, so on any env with `tagbio.imageTag` pinned to a release the daily CronJob went `ErrImagePull` and, with no `concurrencyPolicy`, left one stuck Active job per day. New `tagbio.redeploy.imageTag` (default `branch-master`, falls back to `tagbio.imageTag` if emptied), `concurrencyPolicy: Forbid` + `activeDeadlineSeconds: 3600` (Forbid alone would let one hung run silently block every later tick; the deadline fails it after an hour - healthy runs take ~20s), `failedJobsHistoryLimit: 1`, schedule quoted. `tagbio.redeploySchedule` is the per-env frequency knob (IDEAYA: weekly `0 10 * * 0` - on an immutable release tag a daily full-tier restart has nothing to pick up). Stuck `periodic-redeploy-*` jobs from before the upgrade are not Helm-owned and must be deleted by hand once. Every other object renders byte-identical to 1.3.179 |
| 1.3.174 | 2026-08-13 | **Worker-only scheduling (opt-in)**: with `tagbio.enforceWorkerScheduling: true` + `jupyterhub.custom.enforceWorkerScheduling: true` in answers, FCs, hub, proxy and user notebook pods are HARD-excluded from `tagbio-controller=true` nodes (a user notebook OOMed a controller; the legacy preferred-only affinity is ignored under pressure). Defaults false = unchanged behavior. Only enable on envs with non-controller worker nodes |
| 1.3.173 | 2026-08-13 | **Fix: DNS-safe image-puller container names** (`. -> -`, trunc 63). Dotted image tags (e.g. `release-2026.08.13` via `tagbio.imageTag`) made the puller DaemonSet invalid and failed the whole app upgrade. First version safe for release-tag pinning |
| 1.3.172 | 2026-08-13 | **Version bumps no longer roll FCs**: `helm-chart-version` label moved from the FC pod template to Deployment metadata. Upgrading TO 1.3.172 rolls FCs one last time; afterwards chart bumps are zero-churn for unchanged workloads (safe for demo/no-op versions) |
| 1.3.171 | 2026-08-13 | **Image puller trimmed to active app images**: dropped build/CI-only images (`tagbio-fc-jars`, `tagbio-ci-builder`, `tagbio-ci-pipeline`) that no platform cluster runs but whose size caused a pull/GC disk tug-of-war; recycle interval now `tagbio.imagePullerIntervalSeconds` (default 3600s, was 900). `imagePullPolicy: Always` is kept deliberately — it downloads only when the registry digest changed, i.e. "only pull new images" |
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

## Release prerequisites

- **`release-2026-08-13`**: its `login-service` build only accepts HTTP Basic
  credentials at the token endpoint (body credentials -> 401 -> callback 500).
  Every environment taking this release MUST have
  `jupyterhub.auth.custom.config.basic_auth: true` in its answers before/with
  the upgrade. (Applied: CharacterBio, demo, IDEAYA, 2026-08-13.)
- Release promotion gate: a real browser login on demo (through the
  code-for-token exchange), not just the redirect curl - the redirect can be
  healthy while the token exchange is broken.
- Post-upgrade sweep: `kubectl get ds -n tagbio-system` - any
  periodic-image-puller not matching the deployed chart version is an orphan
  from a failed upgrade (Helm cannot see it) and must be deleted manually.

## Answers pitfalls (Rancher app YAML)

- `hub.extraEnv` and `hub.extraConfig` must be **children of `jupyterhub.hub`**.
  A recurring failure mode is `extraEnv` nested under `extraConfig`, or either
  placed under `jupyterhub:` directly — Helm silently ignores both.
- Since 1.3.169 a lost/misplaced `extraEnv` no longer breaks login (the chart
  derives the URLs), but per-env answers should still carry the explicit values.
- Planned: an `environments/` directory in this repo holding each environment's
  canonical answers/values file, so UI edits are copy-paste from reviewed files
  rather than hand-typed YAML.
