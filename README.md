# Sentinel Split Architecture - DevOps Challenge

A proof-of-concept for Rapyd Sentinel's split architecture: two isolated VPCs, one EKS cluster each,
peered privately, with a public-facing proxy in `vpc-gateway` forwarding to an internal-only backend
in `vpc-backend`.

```
                         Internet
                            |
                            v
                 +---------------------+
                 |   Public NLB        |   vpc-gateway (10.0.0.0/16)
                 |   (gateway Service) |
                 +---------------------+
                            |
                 +---------------------+
                 |  eks-gateway        |  private subnets, 2 AZs
                 |  nginx reverse proxy|
                 +---------------------+
                            |
                    VPC Peering (private,
                    DNS resolution enabled)
                            |
                 +---------------------+
                 |  eks-backend        |  vpc-backend (10.1.0.0/16)
                 |  "Hello from backend"|  private subnets, 2 AZs
                 +---------------------+
                            ^
                 +---------------------+
                 |  Internal NLB        |  reachable only from the
                 |  (backend Service)   |  gateway cluster's SG
                 +---------------------+
```

## Contents

- [Prerequisites & how to run](#prerequisites--how-to-run)
- [Account constraints and how they shaped the design](#account-constraints-and-how-they-shaped-the-design)
- [Repository structure](#repository-structure)
- [Networking](#networking)
- [How the proxy reaches the backend](#how-the-proxy-reaches-the-backend)
- [Security model / NetworkPolicy](#security-model--networkpolicy)
- [CI/CD pipeline](#cicd-pipeline)
- [Trade-offs (3-day constraint)](#trade-offs-3-day-constraint)
- [Cost optimization notes](#cost-optimization-notes)
- [What I'd do next](#what-id-do-next)

## Prerequisites & how to run

This repo doesn't support running `terraform apply` from a laptop for the main stack - the challenge
requires Terraform to run only through GitHub Actions. There's one separate, one-time manual step to
bootstrap the two things CI needs before it can run at all (the usual chicken-and-egg problem with
Terraform backends and CI roles):

1. **Bootstrap** (`bootstrap/`) - applied once, manually, with the AWS credentials for this account:
   ```bash
   cd bootstrap
   terraform init
   terraform apply
   ```
   This creates:
   - An S3 bucket for Terraform remote state (`sentinel-tfstate-juani-721500739616`).
   - An IAM role (`sentinel-github-actions-juani-v2`) that GitHub Actions assumes via OIDC, so no
     long-lived AWS credentials ever sit in GitHub. Its permission policy mirrors the account's own
     `Candidates_Policy` - CI can't do anything a candidate couldn't already do by hand.

   This is genuinely separate from the challenge's infrastructure: it just provisions the CI identity
   and the state backend, not any part of the Sentinel architecture itself.

2. In the GitHub repo, add a repository variable:
   `Settings -> Secrets and variables -> Actions -> Variables`
   - `AWS_ROLE_ARN` = the `github_actions_role_arn` output from step 1.

3. Push to `main`. `.github/workflows/deploy.yml` then validates, runs `terraform apply`, builds and
   pushes both images to ECR, deploys the backend, waits for its internal LB hostname, deploys the
   gateway wired to that hostname, and curls the public endpoint to check the whole path works.

   Any other branch or PR runs `.github/workflows/ci.yml` instead (fmt, validate, tflint, manifest
   schema validation, dry-run, image build check) - no AWS credentials touched.

## Account constraints and how they shaped the design

Before writing any Terraform I pulled the actual IAM policy attached to the candidate account
(`Candidates_Policy`, on the `Candidates` group) instead of guessing at what was allowed. A few of
its restrictions ended up driving real architecture decisions:

| Constraint (from the policy) | Effect on the design |
|---|---|
| `iam:CreateRole` / `AttachRolePolicy` / `PassRole` etc. restricted to `role/eks-*` and `role/sentinel-*` | Every IAM role this repo creates uses one of those two prefixes (`modules/iam-eks`, and the bootstrap CI role `sentinel-github-actions-juani-v2`). |
| No `iam:UpdateAssumeRolePolicy` or `iam:DeleteRolePolicy` granted | A role's trust policy can never be edited after creation, and a role with an inline policy can never be deleted either (both blocked). The first CI role (`sentinel-github-actions-juani`, no `-v2`) got its trust policy condition wrong and is now permanently stuck that way - it's abandoned in place rather than fixed, and a new role (`-v2`) was created correctly instead. Same pattern visible on several other candidates' leftover roles in this account (`-v2`, `-v3` suffixes). |
| AWS rejects a GitHub OIDC trust policy that conditions only on the `repository` claim | Must also include a `sub` (or `job_workflow_ref`) condition, even though `repository` alone is arguably the cleaner scoping given GitHub now embeds immutable ids into `sub` (`repo:owner@id/repo@id:...`). The trust policy keeps both: `repository` for the real scoping, `sub` wildcarded to satisfy AWS's validator. |
| `kms:*` explicitly denied | No EKS secrets envelope encryption, no customer-managed keys anywhere. The state bucket uses SSE-S3 (`AES256`), not SSE-KMS. |
| No `dynamodb:*` in the allow-list | State locking uses Terraform's native S3 lockfile (`use_lockfile = true`, Terraform >= 1.10) instead of a DynamoDB lock table. |
| `iam:CreateOpenIDConnectProvider` not granted (only `Get*/List*/Simulate*` + `CreateServiceLinkedRole`) | Can't register a new OIDC provider. The GitHub Actions one already existed in the account, so the CI role's trust policy just references it - but IRSA for the EKS clusters themselves isn't possible, since each cluster's own OIDC issuer would need to be registered as a new IAM OIDC provider. That's why there's no AWS Load Balancer Controller or IRSA-based cluster-autoscaler in this PoC, both normally rely on it. Instead, the public and internal LoadBalancer Services go through EKS's built-in (in-tree) AWS cloud provider, which needs no IRSA, and cross-VPC access is enforced directly on the EKS-managed cluster security groups. With that constraint lifted, I'd install the AWS Load Balancer Controller via IRSA and switch to `Ingress` with `ip` targets instead of NodePort pass-through. |
| Tagging an IAM role needs `iam:TagRole`, which isn't granted, even for tags passed inline on `CreateRole` | No IAM role in this repo carries `tags`, and the AWS provider isn't configured with `default_tags` either (that would silently try to tag every `aws_iam_role` too and break every apply). Everything else - EC2, EKS, ECR, S3 - is tagged normally since those services are fully allowed. |
| Region locked to `eu-west-1` for this user | Hardcoded as the only allowed value (with a `variable` validation block), matching the challenge's own instruction. |
| Account is shared across multiple candidates (visible via ~90 pre-existing `eks-*`/`sentinel-*` roles and a dozen state buckets from other candidates) | Every resource name (VPCs, IAM roles, EKS clusters, ECR repos, state bucket) carries a `juani` suffix to avoid stepping on other candidates running in the same account. |

I didn't try to work around any of these. Where a constraint removed a capability (IRSA, KMS,
DynamoDB), I picked the next-best AWS-native alternative and wrote down the trade-off, both here and
inline in the Terraform.

## Repository structure

```
bootstrap/            # one-time: state bucket + CI OIDC role
terraform/
  backend.tf           # S3 backend, native lockfile (no DynamoDB)
  providers.tf
  variables.tf / main.tf / outputs.tf   # root module: wires everything together
  modules/
    networking/        # VPC, public+private subnets x2 AZ, IGW, NAT, route tables
    peering/            # VPC peering connection + DNS resolution + routes
    iam-eks/            # cluster role + node role, eks-<name>-{cluster,node}-role
    eks/                # EKS cluster + managed node group + addons (vpc-cni w/ NetworkPolicy, kube-proxy, coredns)
    ecr/                # container repositories
    cross-vpc-sg/       # the two security group rules linking the clusters
apps/
  backend/              # nginx + static "Hello from backend" page
  gateway/              # nginx reverse proxy, backend host templated via env at container start
k8s/
  backend/              # namespace, Deployment, internal LoadBalancer Service, NetworkPolicy
  gateway/               # namespace, Deployment, public LoadBalancer Service
.github/workflows/
  ci.yml                 # validate/lint/dry-run, runs on every push/PR except main
  deploy.yml              # plan+apply+build+deploy+verify, runs on push to main
```

It's one root Terraform module composing six small modules, rather than two fully independent
per-VPC stacks. The peering connection and the cross-cluster security-group rules both need outputs
from both VPCs and both EKS clusters at once, and keeping that in a single state avoids fragile
`terraform_remote_state` cross-referencing for a 3-day PoC.

## Networking

Each VPC (`vpc-gateway` 10.0.0.0/16, `vpc-backend` 10.1.0.0/16) has:

- 2 private subnets across 2 AZs, where every EKS node runs. No workload ever gets a public IP.
- 2 public subnets, used only for the NAT Gateway(s) and, for `vpc-gateway`, the internet-facing NLB.
  No EC2 instances live there.
- One NAT Gateway per VPC, not one per AZ, see [cost notes](#cost-optimization-notes) for why.
- A VPC peering connection between the two, with `allow_remote_vpc_dns_resolution` enabled on both
  sides, and routes added to every route table on both ends for the peer's CIDR.

The EKS API endpoint is both publicly and privately reachable (`endpoint_public_access = true`,
`endpoint_private_access = true`). Public access is needed here because the CI runner is
GitHub-hosted with no fixed IP to allow-list, and a bastion/VPN was out of scope for this PoC - the
endpoint is still IAM-authenticated (via `aws eks update-kubeconfig` and signed requests), never
anonymous. In production I'd run a self-hosted runner inside the VPC and switch to
`endpoint_public_access = false`.

## How the proxy reaches the backend

The backend Service is `type: LoadBalancer` with the in-tree provider's
`aws-load-balancer-internal: "true"` and `aws-load-balancer-type: "nlb"` annotations, so it
provisions an internal NLB living in `vpc-backend`'s private subnets with a private IP - no public
exposure at all.

The gateway's nginx container is templated at startup, using the official nginx image's
`envsubst`-over-`/etc/nginx/templates/*.template` mechanism, with `BACKEND_HOST`/`BACKEND_PORT`
environment variables. The CI pipeline only learns the backend NLB's DNS hostname after deploying it
(the `deploy-backend` job), then injects it into the gateway's Deployment before deploying the
gateway (`deploy-gateway`, which `needs: deploy-backend`).

The gateway pod resolves that hostname to the internal NLB's private IP across the VPC peering
connection - this only works because DNS resolution for the peering connection is explicitly enabled
in `modules/peering`. Using the AWS-managed DNS name instead of hardcoding the NLB's IP means the
link survives the NLB being replaced.

Both Services use a fixed NodePort (30080 gateway, 30081 backend) instead of a random one from the
ephemeral range, so the Terraform-managed security group rules in `modules/cross-vpc-sg` only need to
open that one port instead of the whole 30000-32767 range.

## Security model / NetworkPolicy

Two layers here, on purpose:

1. **Security groups, the real boundary.** Both EKS clusters use their auto-created cluster security
   group, shared by the control plane and every managed-node-group instance since no custom launch
   template is used. `modules/cross-vpc-sg` adds exactly two rules:
   - Backend cluster SG: allow TCP 30081 from the gateway cluster's security group - a cross-VPC
     security-group reference, which AWS supports because the two VPCs are peered and in the same
     account/region. Nothing else, from nowhere else, can reach the backend nodes on that port.
   - Gateway cluster SG: allow TCP 30080 from `0.0.0.0/0`, the one intentional public entry point.

2. **Kubernetes NetworkPolicy, as defense in depth.** The backend namespace restricts ingress to the
   backend pods to traffic sourced from `vpc-backend`'s own CIDR, enforced by the VPC CNI via
   `enableNetworkPolicy: "true"` on the `vpc-cni` addon. It doesn't add a boundary the security group
   doesn't already provide - both ultimately gate on "traffic has to come from inside this
   architecture" - but it does mean a rogue pod that somehow ended up in the backend cluster still
   can't reach the app directly. The real cross-VPC boundary stays the security group rule above, not
   this policy.

No public EC2 instances exist anywhere. The only two public-facing AWS resources are the gateway's
NLB and, implicitly, the NAT Gateways' EIPs, which accept no inbound connections.

## CI/CD pipeline

Two workflows, both triggered on push (the mandatory requirement):

- **`ci.yml`** runs on every push except to `main`, and on every PR into `main`: `terraform fmt
  -check`, `terraform validate`, `tflint` with the AWS ruleset for both the main stack and the
  bootstrap stack, `kubeconform` (schema validation, no cluster needed) and `kubectl apply
  --dry-run=client` for the k8s manifests, and a Docker build check for both images. No AWS
  credentials get used here at all, it's pure static validation.

- **`deploy.yml`** runs on push to `main`. Stages run as separate jobs chained with `needs:`, each
  authenticating independently through `aws-actions/configure-aws-credentials` and OIDC (no static
  AWS keys ever stored in GitHub):
  1. `terraform-apply` - init/validate/plan/apply, exports cluster names, VPC CIDR, and ECR URLs as
     job outputs.
  2. `build-and-push-images` - builds and pushes both images, tagged with the commit SHA.
  3. `deploy-backend` - `aws eks update-kubeconfig`, templates the image tag and VPC CIDR into the
     manifests, runs `kubectl apply --dry-run=server` for a real server-side check against the live
     cluster, then applies for real and waits for the internal NLB hostname.
  4. `deploy-gateway` - same pattern, plus templating in the backend's NLB hostname from step 3.
  5. `verify` - curls the gateway's public hostname in a retry loop until it returns "Hello from
     backend", which proves the full path (internet -> public NLB -> gateway pod -> peering ->
     internal NLB -> backend pod) actually works, not just that `kubectl apply` didn't error out.

  All jobs reference a GitHub Environment named `aws`, which holds the `AWS_ROLE_ARN` variable - a
  natural place to later add required reviewers or a wait timer for a stricter production gate,
  without touching the workflow logic itself.

## Trade-offs (3-day constraint)

- **Single Terraform state / one root module**, not fully independent gateway/backend stacks with
  remote-state data sources between them. Simpler to review and apply in the time available; the
  downside is that a gateway-only change still plans against the whole graph.
- **One NAT Gateway per VPC**, not one per AZ, see the cost notes below.
- **No AWS Load Balancer Controller / IRSA** anywhere (see the constraints table above), so Services
  use the in-tree provider's NodePort+LB pass-through model instead of `Ingress` with IP targets.
- **No staging/production environment split.** A real Sentinel rollout would have per-environment
  state (`envs/dev`, `envs/prod`) and a plan-on-PR / apply-on-merge gate with manual approval; this
  PoC has one environment (`aws`) because building and validating two from scratch wasn't realistic
  alongside everything else in 3 days. The workflow is already structured (`environment: aws` per
  job) so adding a second one later is a config change, not a rewrite.
- **EKS API endpoint is public** (IAM-authenticated, not anonymous) because GitHub-hosted runners
  don't have a fixed IP range to allow-list, and a self-hosted runner inside the VPC was out of scope
  for the time available.
- **NetworkPolicy is CIDR-based, not identity-based** - a direct consequence of not having the AWS
  Load Balancer Controller's `ip`-target mode, which would let policies match on real pod IPs
  end-to-end.

## Cost optimization notes

- **NAT Gateway**: one per VPC (2 total) instead of one per AZ (which would be 4). NAT Gateways are
  billed hourly plus per-GB processed regardless of traffic, so halving the count directly halves
  this cost; the trade-off is a single point of failure and cross-AZ data processing charges for
  nodes in the second AZ. For a PoC this is the right side of that trade; for production I'd go back
  to one per AZ.
- **Node sizing**: `t3.medium` on-demand, 2 nodes desired (min 1, max 3) per cluster - about the
  smallest instance size that comfortably runs the EKS system daemonsets (`vpc-cni`, `kube-proxy`,
  `coredns`) alongside the actual workload. `node_capacity_type` is a variable; flipping it to `SPOT`
  would cut compute cost significantly for a non-production PoC at the risk of interruption, left as
  `ON_DEMAND` by default for a more predictable evaluation run.
- **Load balancer type**: NLB, not Classic ELB or ALB, for both Services. NLBs are cheaper at this
  traffic scale and match this PoC's pure-L4 pass-through use case, no L7 routing needed.
- **ECR lifecycle policy**: untagged images expire after 7 days, so accumulated CI build artifacts
  don't quietly grow the storage bill.
- **No KMS customer-managed keys** anywhere (also required by the account's guardrail) - SSE-S3/AES256
  has no per-request KMS cost.

## What I'd do next

- **AWS Load Balancer Controller via IRSA**, once IAM OIDC provider creation is available - move from
  NodePort pass-through to `Ingress` with `ip` targets, enabling real pod-level NetworkPolicy
  enforcement and TLS termination at the LB.
- **TLS/mTLS** between gateway and backend. Right now the peering link is private but unencrypted in
  transit; a service mesh (Linkerd/Istio) or even just nginx client-cert verification would close
  that gap.
- **GitOps** (Argo CD/Flux) instead of `kubectl apply` from the pipeline, for drift detection and a
  real audit trail of what's running versus what's declared.
- **Observability**: Prometheus/Grafana or AWS Managed Prometheus, plus centralizing pod logs (Fluent
  Bit into CloudWatch Logs, already allowed by this account's policy).
- **Secrets management**: Vault or AWS Secrets Manager once that service is available to this account
  (`secretsmanager:*` is currently denied). This PoC has no secrets to manage yet, but any real
  backend service would.
- **Separate plan-only vs. apply-capable CI roles**, and a genuine staging/production environment
  split with required reviewers on the production `apply` job.
- **Per-AZ NAT Gateways** and EKS cluster-autoscaler (or Karpenter) once IRSA is available, for real
  production resilience and elasticity.
