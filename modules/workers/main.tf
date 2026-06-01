########################################
# Module: Swarm Worker Nodes (ASG)
########################################

data "aws_region" "current" {}

########################################
# Worker User-Data
########################################

locals {
  worker_userdata = <<-EOT
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

    # ── Wait for primary manager to publish real worker token ─────────
    REGION="${data.aws_region.current.name}"
    SECRET_ARN="${var.swarm_join_token_secret}"
    MANAGER_IP="${var.manager_private_ip}"

    WORKER_TOKEN=""
    for i in $(seq 1 60); do
      SECRET=$(aws secretsmanager get-secret-value \
        --secret-id "$SECRET_ARN" --region "$REGION" \
        --query SecretString --output text 2>/dev/null) || true
      if [ -n "$SECRET" ]; then
        CANDIDATE=$(echo "$SECRET" | jq -r '.worker_token // empty')
        if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "PLACEHOLDER_WORKER_TOKEN" ]; then
          WORKER_TOKEN="$CANDIDATE"
          break
        fi
      fi
      echo "Waiting for primary manager to publish worker token... attempt $i"
      sleep 10
    done

    if [ -z "$WORKER_TOKEN" ]; then
      echo "Timed out waiting for worker join token" >&2
      exit 1
    fi

    for i in $(seq 1 20); do
      docker swarm join --token "$WORKER_TOKEN" "$MANAGER_IP:2377" && break
      echo "Swarm join failed, retrying $i..."
      sleep 15
    done

    echo "Worker joined Docker Swarm."
  EOT
}

########################################
# Launch Template
########################################

resource "aws_launch_template" "worker" {
  name_prefix   = "${var.project_name}-worker-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = base64encode(local.worker_userdata)

  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  vpc_security_group_ids = var.security_group_ids

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 30
      delete_on_termination = true
      encrypted             = true
    }
  }

  metadata_options {
    http_tokens                 = "required"   # IMDSv2
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-worker"
      Role        = "swarm-worker"
      SwarmRole   = "worker"
      Environment = var.environment
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name        = "${var.project_name}-worker-volume"
      Environment = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

########################################
# Auto Scaling Group
########################################

resource "aws_autoscaling_group" "workers" {
  name                = "${var.project_name}-workers-asg"
  vpc_zone_identifier = var.subnet_ids
  min_size            = var.min_workers
  max_size            = var.max_workers
  desired_capacity    = var.desired_workers

  target_group_arns = [var.target_group_arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "SwarmRole"
    value               = "worker"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

########################################
# ASG Scaling Policies
########################################

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project_name}-worker-scale-out"
  autoscaling_group_name = aws_autoscaling_group.workers.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project_name}-worker-scale-in"
  autoscaling_group_name = aws_autoscaling_group.workers.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-worker-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 75

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.workers.name
  }

  alarm_description = "Scale out workers when CPU >= 75%"
  alarm_actions     = [aws_autoscaling_policy.scale_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.project_name}-worker-low-cpu"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 25

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.workers.name
  }

  alarm_description = "Scale in workers when CPU <= 25%"
  alarm_actions     = [aws_autoscaling_policy.scale_in.arn]
}

########################################
# CloudWatch Log Group
########################################

resource "aws_cloudwatch_log_group" "workers" {
  name              = "/aws/ec2/${var.project_name}/workers"
  retention_in_days = 30
}
