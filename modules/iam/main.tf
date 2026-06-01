########################################
# Module: IAM – Manager & Worker Roles
########################################

########################################
# Swarm Join-Token Secret (Secrets Manager)
########################################

resource "aws_secretsmanager_secret" "swarm_tokens" {
  name                    = "/${var.project_name}/${var.environment}/swarm-tokens"
  description             = "Docker Swarm manager & worker join tokens"
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = {
    Name        = "${var.project_name}-swarm-tokens"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "swarm_tokens_placeholder" {
  secret_id     = aws_secretsmanager_secret.swarm_tokens.id
  secret_string = jsonencode({
    manager_token = "PLACEHOLDER_MANAGER_TOKEN"
    worker_token  = "PLACEHOLDER_WORKER_TOKEN"
  })

  lifecycle {
    ignore_changes = [secret_string]   # Updated by the primary manager at boot
  }
}

########################################
# Manager IAM Role
########################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "manager" {
  name               = "${var.project_name}-manager-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${var.project_name}-manager-role" }
}

data "aws_iam_policy_document" "manager_policy" {
  # Read/write Swarm join tokens
  statement {
    sid    = "SwarmTokensRW"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.swarm_tokens.arn]
  }

  # EC2 describe (needed for dynamic node discovery)
  statement {
    sid    = "EC2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
    ]
    resources = ["*"]
  }

  # SSM Session Manager (optional, replaces bastion)
  statement {
    sid    = "SSMSessionManager"
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }

  # CloudWatch Logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # ECR pull (so managers can pull images)
  statement {
    sid    = "ECRPull"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "manager" {
  name   = "${var.project_name}-manager-policy"
  policy = data.aws_iam_policy_document.manager_policy.json
}

resource "aws_iam_role_policy_attachment" "manager" {
  role       = aws_iam_role.manager.name
  policy_arn = aws_iam_policy.manager.arn
}

resource "aws_iam_instance_profile" "manager" {
  name = "${var.project_name}-manager-profile"
  role = aws_iam_role.manager.name
}

########################################
# Worker IAM Role
########################################

resource "aws_iam_role" "worker" {
  name               = "${var.project_name}-worker-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${var.project_name}-worker-role" }
}

data "aws_iam_policy_document" "worker_policy" {
  # Read Swarm join token only
  statement {
    sid    = "SwarmTokenRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.swarm_tokens.arn]
  }

  # EC2 describe (for self-identification)
  statement {
    sid    = "EC2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
    ]
    resources = ["*"]
  }

  # SSM Session Manager
  statement {
    sid    = "SSMSessionManager"
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }

  # CloudWatch Logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # ECR pull
  statement {
    sid    = "ECRPull"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "worker" {
  name   = "${var.project_name}-worker-policy"
  policy = data.aws_iam_policy_document.worker_policy.json
}

resource "aws_iam_role_policy_attachment" "worker" {
  role       = aws_iam_role.worker.name
  policy_arn = aws_iam_policy.worker.arn
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.project_name}-worker-profile"
  role = aws_iam_role.worker.name
}
