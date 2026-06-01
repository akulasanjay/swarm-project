########################################
# Module: Swarm Manager Nodes
########################################

data "aws_region" "current" {}

########################################
# User-data: Primary Manager (index 0)
########################################

locals {
  manager_primary_userdata = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

    # ── Install Docker ─────────────────────────────────────────────────
    yum update -y
    yum install -y amazon-linux-extras jq awscli
    amazon-linux-extras enable docker
    yum install -y docker${var.docker_version != "" ? "-${var.docker_version}" : ""}
    systemctl enable --now docker
    usermod -aG docker ec2-user

    # ── Fetch local IPv4 via IMDSv2 ────────────────────────────────────
    IMDS_TOKEN=$(curl -sS -X PUT \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
      http://169.254.169.254/latest/api/token)
    PRIVATE_IP=$(curl -sS \
      -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
      http://169.254.169.254/latest/meta-data/local-ipv4)

    # ── Init Swarm (idempotent) ────────────────────────────────────────
    if ! docker info 2>/dev/null | grep -q 'Swarm: active'; then
      docker swarm init --advertise-addr "$PRIVATE_IP"
    fi

    # ── Publish tokens to Secrets Manager ─────────────────────────────
    MANAGER_TOKEN=$(docker swarm join-token manager -q)
    WORKER_TOKEN=$(docker swarm join-token worker  -q)
    SECRET_VALUE=$(jq -n \
      --arg mt "$MANAGER_TOKEN" \
      --arg wt "$WORKER_TOKEN"  \
      '{manager_token:$mt, worker_token:$wt}')

    aws secretsmanager put-secret-value \
      --secret-id "${var.swarm_join_token_secret}" \
      --secret-string "$SECRET_VALUE" \
      --region "${data.aws_region.current.name}"

    echo "Docker Swarm primary manager initialised."
  EOT

  manager_secondary_userdata = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

    yum update -y
    yum install -y amazon-linux-extras jq awscli
    amazon-linux-extras enable docker
    yum install -y docker${var.docker_version != "" ? "-${var.docker_version}" : ""}
    systemctl enable --now docker
    usermod -aG docker ec2-user

    # ── Wait for primary manager to publish real token ─────────────────
    REGION="${data.aws_region.current.name}"
    SECRET_ARN="${var.swarm_join_token_secret}"
    MANAGER_IP="${var.manager_primary_ip_placeholder}"

    MANAGER_TOKEN=""
    for i in $(seq 1 60); do
      SECRET=$(aws secretsmanager get-secret-value \
        --secret-id "$SECRET_ARN" --region "$REGION" \
        --query SecretString --output text 2>/dev/null) || true
      if [ -n "$SECRET" ]; then
        CANDIDATE=$(echo "$SECRET" | jq -r '.manager_token // empty')
        if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "PLACEHOLDER_MANAGER_TOKEN" ]; then
          MANAGER_TOKEN="$CANDIDATE"
          break
        fi
      fi
      echo "Waiting for primary manager to publish manager token... attempt $i"
      sleep 10
    done

    if [ -z "$MANAGER_TOKEN" ]; then
      echo "Timed out waiting for manager join token" >&2
      exit 1
    fi

    for i in $(seq 1 20); do
      docker swarm join --token "$MANAGER_TOKEN" "$MANAGER_IP:2377" && break
      echo "Swarm join failed, retrying $i..."
      sleep 15
    done

    echo "Secondary manager joined Swarm."
  EOT
}

########################################
# Primary Manager EC2 Instance
########################################

resource "aws_instance" "manager_primary" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[0]
  key_name               = var.key_name
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.iam_instance_profile_name

  user_data = local.manager_primary_userdata

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens                 = "required"   # IMDSv2 enforced
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-manager-primary"
    Role        = "swarm-manager"
    SwarmRole   = "manager-primary"
    Environment = var.environment
  }
}

########################################
# Secondary Manager EC2 Instances
########################################

resource "aws_instance" "manager_secondary" {
  count = var.manager_count - 1

  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[(count.index + 1) % length(var.subnet_ids)]
  key_name               = var.key_name
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.iam_instance_profile_name

  user_data = replace(
    local.manager_secondary_userdata,
    var.manager_primary_ip_placeholder,
    aws_instance.manager_primary.private_ip
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  depends_on = [aws_instance.manager_primary]

  tags = {
    Name        = "${var.project_name}-manager-${count.index + 2}"
    Role        = "swarm-manager"
    SwarmRole   = "manager-secondary"
    Environment = var.environment
  }
}

########################################
# CloudWatch Log Group
########################################

resource "aws_cloudwatch_log_group" "manager" {
  name              = "/aws/ec2/${var.project_name}/managers"
  retention_in_days = 30
}
