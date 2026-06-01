# Docker Swarm on AWS – Terraform

A production-ready Terraform project that provisions a fully-featured **Docker Swarm** cluster on AWS, including:

- Multi-manager Swarm cluster (quorum-safe: 1, 3, or 5 nodes)
- Auto Scaling Group for worker nodes with CPU-based scaling
- Application Load Balancer + Target Group
- Dedicated Security Groups per tier (ALB / Manager / Worker)
- IAM Roles & Instance Profiles with least-privilege policies
- Secrets Manager for secure Swarm join-token distribution
- Route 53 DNS alias record
- S3 access logs for the ALB
- IMDSv2 enforced on all instances

---

## Architecture

```
Internet
   │
   ▼
[ ALB ] ─── Security Group: ALB (80/443 from 0.0.0.0/0)
   │
   ▼ (port 80 / 8080)
[ Worker ASG ] ─── Private Subnets ─── Security Group: Worker
   │  (Swarm join via token from Secrets Manager)
   │
   ▼ (port 2377 swarm-mgmt, 7946 gossip, 4789 VXLAN)
[ Manager Nodes ] ─── Public Subnets ─── Security Group: Manager
   │  (Primary inits Swarm, writes tokens; secondaries join)
   │
   ▼
[ Secrets Manager ] ← manager_token / worker_token
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Terraform | >= 1.5 |
| AWS CLI | v2 |
| AWS credentials | configured via env or `~/.aws` |
| EC2 Key Pair | created in target region |

---

## Quick Start

```bash
# 1. Clone / copy the project
cd docker-swarm-terraform

# 2. Create your variables file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Initialise
terraform init

# 4. Preview
terraform plan

# 5. Apply
terraform apply
```

---

## Module Overview

| Module | Purpose |
|--------|---------|
| `iam` | Manager & Worker IAM Roles, Instance Profiles, Secrets Manager secret |
| `security` | ALB, Manager, and Worker Security Groups |
| `manager` | Primary + secondary manager EC2 instances; initialises Swarm |
| `load_balancer` | ALB, Target Group, HTTP/HTTPS listeners, S3 access logs |
| `workers` | Launch Template, Auto Scaling Group, CPU scaling policies |
| `dns` | Route 53 A-alias record pointing to the ALB |

---

## Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | Deployment region |
| `project_name` | `docker-swarm` | Resource name prefix |
| `environment` | `prod` | Environment tag |
| `key_name` | *(required)* | EC2 Key Pair name |
| `manager_count` | `3` | Number of manager nodes (use 1/3/5) |
| `min_workers` | `2` | ASG minimum |
| `max_workers` | `10` | ASG maximum |
| `desired_workers` | `3` | ASG desired at launch |
| `certificate_arn` | `""` | ACM cert for HTTPS (optional) |
| `hosted_zone_id` | `""` | Route 53 zone ID (optional) |
| `domain_name` | `""` | FQDN (optional) |

---

## How Join Tokens Work

1. **Primary manager** runs `docker swarm init` and writes manager + worker tokens to **AWS Secrets Manager**.
2. **Secondary managers** poll the secret (retrying up to 30× with 10 s backoff) then run `docker swarm join --token <manager_token>`.
3. **Workers** (in the ASG) poll the same secret and run `docker swarm join --token <worker_token>`.

IAM policies ensure managers can **read + write** the secret, while workers can only **read** it.

---

## Scaling Workers

Workers scale automatically via CloudWatch alarms:

| Alarm | Threshold | Action |
|-------|-----------|--------|
| `high-cpu` | CPU ≥ 75% (2 × 2 min) | +1 instance |
| `low-cpu` | CPU ≤ 25% (2 × 2 min) | −1 instance |

To scale manually:
```bash
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name docker-swarm-workers-asg \
  --desired-capacity 5
```

---

## SSH Access

Managers are in **public subnets** with SSH restricted to `allowed_cidr` (default: your IP).  
Workers are in **private subnets**; reach them via a manager acting as a jump host:

```bash
ssh -J ec2-user@<MANAGER_IP> ec2-user@<WORKER_PRIVATE_IP>
```

Or use **AWS Systems Manager Session Manager** (no SSH key needed):
```bash
aws ssm start-session --target <instance-id>
```

---

## Deploying a Service

Once the cluster is running, SSH to the primary manager and deploy:

```bash
docker service create \
  --name my-app \
  --replicas 3 \
  --publish published=80,target=80 \
  nginx:latest
```

Check cluster status:
```bash
docker node ls
docker service ls
```

---

## Cleanup

```bash
terraform destroy
```

---

## Security Notes

- IMDSv2 is enforced on all instances.
- Worker nodes have **no public IPs** (private subnets only).
- The Swarm join-token secret is encrypted at rest in Secrets Manager.
- ALB access logs are stored in a private S3 bucket, expired after 90 days.
- Update `allowed_cidr` to restrict SSH to specific IPs in production.
