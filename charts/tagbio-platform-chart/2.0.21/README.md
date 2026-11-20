
Chart values used in tagbio internal clusters (including test):
https://drive.google.com/drive/u/0/folders/144KGkRW1fP_BTxoVYU5FHbgEyE5_Gm3I

## 1.3.188 — opt-in stable node for the core stack

`tagbio.coreStack.stableNode.enabled: true` adds a weight-100 preferred node
affinity for `<labelKey>=<labelValue>` (default `tagbio-stable=true`) plus a
matching `NoSchedule` toleration to kung, kung-services, login-service,
notification-service and rutherford. Default `false`: templates render
byte-identical to 1.3.187, so environments without such a node are
unaffected. Preferred-only: pods fall back to ordinary workers if the node
is missing. For hub/proxy use the bundled chart's own knobs: label the node
`hub.jupyter.org/node-purpose=core` and set `jupyterhub.hub.tolerations` and
`jupyterhub.proxy.chp.tolerations` in the environment answers.
Applied: IDEAYA, 2026-08-26 (on-demand r6i.xlarge in
`ideayabio-tagbio-cluster-stable-asg`, tainted `tagbio-stable=true:NoSchedule`).

## 1.3.189 — `stableNode.required`

Adds `tagbio.coreStack.stableNode.required` (default `false`; render-identical
to 1.3.188 unless set). When `true` the stable-node affinity becomes
`requiredDuringSchedulingIgnoredDuringExecution` — needed in practice because
a preferred term lost to the scheduler's resource/image scoring on IDEAYA
(the five core services landed on an empty spot worker). Also adds `taintKey`/`taintValue` (default = label key/value) so the
tolerated taint can differ from the affinity label. Pair `required` with an
automatic label (`node.kubernetes.io/instance-type`) so a replaced instance
matches without manual labeling. Applied: IDEAYA, 2026-08-26.

## 1.3.190 — `tagbio.rutherford.imageTag`

Per-component image tag for rutherford (the frontend), `default`-ing to
`tagbio.imageTag`. Default `""`: every template renders byte-identical to
1.3.189, so environments that do not set it are unaffected. Same shape as
`tagbio.redeploy.imageTag` (1.3.180) and `publicFcs.*.imageTag` (1.3.177):
rutherford's pipeline publishes only `branch-master`/`branch-stage`, and a
`release-*` tag is a registry-side retag of whatever `branch-master` was on
release day, so an environment pinned to a release cannot take a frontend-only
fix without a platform-wide release. Both the Deployment and the
`periodic-image-puller` container use the value (patching only one leaves the
puller in ImagePullBackOff, as 1.3.177 found). Applied: demo, 2026-08-26
(`tagbio.rutherford.imageTag: branch-master` for the 1.1.3 version/copyright
fix while the rest of the platform stays on `release-2026-08-13`).

## 1.3.191 — image puller honours `publicFcs.*.imageName`

`periodic-image-puller` pre-pulled `<workload key>:<tag>` and ignored the
`imageName` that 1.3.186 introduced for the workloads, so every FC whose image
repo differs from its key (the six `fc-cbioportal-*` products) sat in
`ImagePullBackOff` inside the puller pod, and Rancher showed the app as
"deploying" forever. Now `($spec.imageName | default $name)`, the same
expression `public-fcs.yaml` uses. Environments with no `imageName` set render
byte-identical to 1.3.190. Applied: demo, 2026-08-26.
