
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
