# EKS EC2 Existing Instance Workspace

Connect a Coder workspace to an **already-running EC2 instance** in AWS GovCloud — Linux (SSH) or Windows (RDP) — without opening any inbound ports, installing SSH keys, or touching the instance's security group.

The Coder agent is delivered to the target instance via **AWS SSM Run Command** and phones home to the Coder server over standard outbound HTTPS.

## How it works

```
Coder Server (EKS pod)
  └── Terraform provisioner
        ├── Creates aws_ssm_document  (init script content)
        └── Creates aws_ssm_association
                   │
                   ▼  (SSM Run Command — no inbound ports required)
              Target EC2 (existing)
                   └── Coder agent starts → connects back to Coder Server
                            over outbound HTTPS (port 443)
```

## Prerequisites

### Target EC2 instance

| Requirement | Details |
|---|---|
| **SSM agent installed and running** | Amazon Linux 2 / AL2023: pre-installed. Ubuntu: `sudo snap install amazon-ssm-agent --classic`. Windows Server: [AWS docs](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-install-win.html) |
| **IAM Instance Profile** | Must include `arn:aws-us-gov:iam::aws:policy/AmazonSSMManagedInstanceCore` |
| **Outbound HTTPS (443)** | Security group must allow egress to the Coder server URL and AWS SSM endpoints |
| **SSM VPC Endpoints (private VPC)** | If no Internet Gateway: create endpoints for `ssm`, `ssmmessages`, `ec2messages` in `us-gov-west-1` |
| **Linux: `coder` user** | `sudo useradd -m -s /bin/bash coder` — or adjust the `coder_user` variable |
| **Linux: instance is running** | EC2 must be in `running` state when the workspace starts |

### Coder provisioner pod (IRSA role)

The Coder provisioner pod on EKS needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SSMDocumentManagement",
      "Effect": "Allow",
      "Action": [
        "ssm:CreateDocument",
        "ssm:DeleteDocument",
        "ssm:DescribeDocument",
        "ssm:GetDocument",
        "ssm:UpdateDocument",
        "ssm:CreateAssociation",
        "ssm:DeleteAssociation",
        "ssm:DescribeAssociation",
        "ssm:UpdateAssociationStatus",
        "ssm:ListAssociations"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2Describe",
      "Effect": "Allow",
      "Action": ["ec2:DescribeInstances"],
      "Resource": "*"
    }
  ]
}
```

## Instance readiness check

Run `workspace/bootstrap.sh` to verify an instance is ready before importing it:

```sh
chmod +x workspace/bootstrap.sh
./workspace/bootstrap.sh i-0123456789abcdef0 us-gov-west-1
```

## Variables reference

| Variable | Default | Description |
|---|---|---|
| `ec2_instance_id` | *(required)* | Target instance ID (`i-xxxx`) |
| `os_type` | `linux` | `linux` or `windows` |
| `arch` | `amd64` | `amd64` or `arm64` |
| `aws_region` | `us-gov-west-1` | AWS GovCloud region |
| `coder_workdir` | auto | Working dir on instance (`/home/coder` or `C:\Users\coder`) |
| `coder_user` | `""` | Linux: OS user to run the agent as (blank = ssm-user/root) |
| `ssm_execution_timeout_seconds` | `3600` | SSM Run Command timeout |
| `enable_xrdp` | `false` | Linux only: install/configure XRDP for desktop access over Coder port-forward |
| `xrdp_port` | `3389` | Linux XRDP listen port |
| `enable_mcp_filesystem` | `true` | Register filesystem MCP for Claude Code |
| `mcp_allowed_root` | `/home/coder/project` | Filesystem root for MCP |
| `enable_mcp_github` | `false` | Register GitHub MCP |
| `mcp_github_token` | `""` | GitHub PAT (sensitive) |

## Workspace lifecycle

| Event | What happens |
|---|---|
| **Start** | `aws_ssm_association` is created → SSM delivers init script → agent starts |
| **Stop** | `aws_ssm_association` is deleted → agent detects stopped workspace and exits |
| **Delete** | SSM document and association are destroyed; the EC2 instance is **not** modified |

The underlying EC2 instance is **never started, stopped, or terminated** by this template.

## Accessing the workspace

### Linux (SSH)
The Coder CLI sets up SSH automatically:
```sh
coder ssh <workspace-name>
```

VS Code Remote-SSH also works via the Coder VS Code extension.

### Linux desktop (XRDP)
If you set `enable_xrdp=true`, the startup script installs XRDP and XFCE (best effort by distro), starts the XRDP service, and you can connect like this:

```sh
# Forward XRDP through the Coder agent relay
coder port-forward <workspace-name> --tcp 3389:3389

# Then connect your RDP client to localhost:3389
```

If you changed `xrdp_port`, replace `3389` with your configured port.

### Windows (RDP)
The Coder agent relays TCP traffic. To RDP into a Windows workspace:
```sh
# Forward port 3389 through the Coder agent relay
coder port-forward <workspace-name> --tcp 3389:3389

# In a second terminal or via your RDP client:
# Connect to: localhost:3389
# Username: the Windows Administrator or domain user on the EC2
```

## Common failure causes (and fixes)

| Symptom | Likely cause | Fix |
|---|---|---|
| Agent never connects after workspace start | SSM agent offline on EC2 | Run `bootstrap.sh` check; install SSM agent; attach instance profile |
| `SSM execution failed` in Coder logs | Missing IAM permissions on provisioner IRSA | Add `ssm:CreateDocument`, `ssm:CreateAssociation`, etc. to the IRSA policy |
| Agent connects then immediately disconnects | Coder server URL unreachable from EC2 | Ensure EC2 outbound SG allows 443 to the Coder server; check VPC routing |
| `Error: InvalidInstanceId` from Terraform | Instance not registered with SSM | Verify instance profile has `AmazonSSMManagedInstanceCore`; restart SSM agent |
| Works on first run, fails on workspace restart | Association name collision | Upgrade to template version ≥ 0.1.0 (association names use workspace UUID) |
| Cannot resolve Coder server URL from EC2 | DNS or private link issue | Check Route 53 / VPC DNS settings; ensure Coder server internal hostname resolves inside the VPC |

## GovCloud-specific notes

- **Partition**: All IAM ARNs use `aws-us-gov` (not `aws`).
- **SSM endpoint**:  `ssm.us-gov-west-1.amazonaws.com` (FIPS: `ssm-fips.us-gov-west-1.amazonaws.com`)
- **VPC endpoints needed in air-gapped VPCs**:
  - `com.amazonaws.us-gov-west-1.ssm`
  - `com.amazonaws.us-gov-west-1.ssmmessages`
  - `com.amazonaws.us-gov-west-1.ec2messages`
