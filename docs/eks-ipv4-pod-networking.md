# EKS IPv4 Pod Networking Playbook

This runbook helps reduce IPv4 exhaustion in Amazon EKS clusters when pod density grows faster than available subnet IPs.

It is intentionally opinionated for platform teams operating Coder-backed workloads on EKS.

---

## Why clusters run out of IPv4 addresses

In default EKS VPC CNI mode, each pod receives a VPC IP address from node ENIs. As pod count grows, the `aws-node` CNI daemon pre-allocates additional addresses (or prefixes), and subnets can be depleted before compute is saturated.

Most exhaustion incidents are caused by one or more of:

- small worker subnets
- high node count with conservative pod packing
- overly aggressive warm pools in `aws-node`
- no prefix delegation in busy clusters
- burst autoscaling into near-empty subnets

---

## Fast triage checklist

1. Confirm subnet free IPv4 counts for all node subnets.
2. Check `aws-node` env settings (`WARM_IP_TARGET`, `MINIMUM_IP_TARGET`, `WARM_PREFIX_TARGET`, `ENABLE_PREFIX_DELEGATION`).
3. Compare pod demand vs node `maxPods` settings.
4. Validate autoscaler behavior (Cluster Autoscaler or Karpenter) during bursts.
5. Check for uneven AZ/subnet pressure.

Useful commands:

```bash
kubectl -n kube-system get ds aws-node -o yaml | grep -E "WARM_IP_TARGET|MINIMUM_IP_TARGET|WARM_PREFIX_TARGET|ENABLE_PREFIX_DELEGATION"
kubectl get nodes -o wide
kubectl get pods -A --field-selector=status.phase=Running | wc -l

aws ec2 describe-subnets \
  --subnet-ids subnet-aaa subnet-bbb subnet-ccc \
  --query 'Subnets[].{SubnetId:SubnetId,AZ:AvailabilityZone,AvailableIpAddressCount:AvailableIpAddressCount,Cidr:CidrBlock}' \
  --output table
```

---

## Recommended mitigation order (lowest risk first)

### 1) Tune warm targets to reduce idle IP hoarding

If your cluster keeps many unused addresses reserved, lower warm targets.

- Prefer setting **either** `WARM_IP_TARGET`/`MINIMUM_IP_TARGET` (secondary-IP mode) **or** `WARM_PREFIX_TARGET` (prefix mode), not all aggressively at once.
- Start conservatively and monitor pod-start latency.

Example patch:

```bash
kubectl -n kube-system set env daemonset/aws-node \
  WARM_IP_TARGET=2 \
  MINIMUM_IP_TARGET=5
```

### 2) Enable prefix delegation (high impact for IPv4 efficiency)

Prefix delegation allows ENIs to hand out addresses from delegated prefixes and usually improves pod density per node.

Example patch:

```bash
kubectl -n kube-system set env daemonset/aws-node \
  ENABLE_PREFIX_DELEGATION=true \
  WARM_PREFIX_TARGET=1
```

After enabling, validate node group AMI/CNI compatibility and re-check pod scheduling behavior.

### 3) Right-size node `maxPods`

If `maxPods` is too low, you burn extra node ENIs/subnet IPs for the same workload.

- Recalculate with your chosen CNI mode (secondary-IP vs prefix).
- Keep headroom for DaemonSets/system pods.

### 4) Expand address space

When demand is fundamentally higher than available CIDRs:

- add larger or additional worker subnets
- attach secondary VPC CIDR blocks
- migrate node groups to less-constrained subnets

### 5) Use custom networking for specialized segmentation

For strict isolation or dedicated pod subnet strategy, use ENIConfig/custom networking to control where pod IPs are sourced.

---

## Tuning matrix

| Cluster profile | CNI mode | Suggested starting point | Notes |
| --- | --- | --- | --- |
| Small/steady | Secondary IP | `WARM_IP_TARGET=1-2`, `MINIMUM_IP_TARGET=3-5` | Minimize idle reservations while keeping startup responsive. |
| Medium/bursty | Secondary IP | `WARM_IP_TARGET=2-5`, `MINIMUM_IP_TARGET=10` | Balance burst readiness with subnet conservation. |
| Medium/Large | Prefix delegation | `ENABLE_PREFIX_DELEGATION=true`, `WARM_PREFIX_TARGET=1` | Usually best IPv4 efficiency per node. |
| Very bursty latency-sensitive | Prefix delegation | `WARM_PREFIX_TARGET=1-2` | Higher warm prefix increases readiness, but consumes more addresses. |

> Treat these as starting points, not fixed values. Validate against real workload burst patterns.

---

## Guardrails to prevent recurrence

- Add alerting on `AvailableIpAddressCount` per subnet.
- Track CNI allocation metrics and pending pods during scale events.
- Keep at least one less-utilized subnet per AZ for emergency scale-out.
- Add preflight checks to platform change windows (new node groups, major deployments, traffic events).
- Revisit CNI warm settings whenever autoscaling strategy changes.

---

## Validation workflow after changes

1. Roll out CNI env update.
2. Restart or recycle nodes only if required by your node bootstrap strategy.
3. Run a controlled scale test:
   - increase replicas significantly
   - confirm pods schedule without `Insufficient pods` / IP allocation errors
   - verify subnet free IP trends remain healthy
4. Confirm no regression in pod startup latency.

---

## Coder-specific note

Coder workspaces increase pod churn and burst behavior. For Coder-heavy EKS clusters:

- prefer prefix delegation where supported
- avoid overly high warm targets
- isolate workspace node groups/subnets from critical platform services
- keep a reserved subnet/IP budget for peak developer hours
