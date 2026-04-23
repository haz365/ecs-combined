terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ── EFS for persistent storage ────────────────────────────────────────────────

resource "aws_efs_file_system" "observability" {
  creation_token   = "${var.project}-${var.environment}-observability"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = { Name = "${var.project}-${var.environment}-observability" }
}

resource "aws_efs_access_point" "prometheus" {
  file_system_id = aws_efs_file_system.observability.id

  posix_user {
    gid = 65534
    uid = 65534
  }

  root_directory {
    path = "/prometheus"
    creation_info {
      owner_gid   = 65534
      owner_uid   = 65534
      permissions = "755"
    }
  }

  tags = { Name = "${var.project}-${var.environment}-prometheus" }
}

resource "aws_efs_access_point" "grafana" {
  file_system_id = aws_efs_file_system.observability.id

  posix_user {
    gid = 472
    uid = 472
  }

  root_directory {
    path = "/grafana"
    creation_info {
      owner_gid   = 472
      owner_uid   = 472
      permissions = "755"
    }
  }

  tags = { Name = "${var.project}-${var.environment}-grafana" }
}

# ── Security groups ───────────────────────────────────────────────────────────

resource "aws_security_group" "efs" {
  name        = "${var.project}-${var.environment}-efs"
  description = "EFS access from observability tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from observability tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.prometheus.id, aws_security_group.grafana.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-efs" }
}

resource "aws_efs_mount_target" "observability" {
  count           = 3
  file_system_id  = aws_efs_file_system.observability.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "prometheus" {
  name        = "${var.project}-${var.environment}-prometheus"
  description = "Prometheus ECS service"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From Grafana"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-prometheus" }
}

resource "aws_security_group" "grafana" {
  name        = "${var.project}-${var.environment}-grafana"
  description = "Grafana ECS service"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [var.alb_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-grafana" }
}

# Allow Prometheus to scrape app services
resource "aws_security_group_rule" "api_scrape" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = var.api_sg_id
  source_security_group_id = aws_security_group.prometheus.id
  description              = "Prometheus scrape"
}

resource "aws_security_group_rule" "worker_scrape" {
  type                     = "ingress"
  from_port                = 9091
  to_port                  = 9091
  protocol                 = "tcp"
  security_group_id        = var.worker_sg_id
  source_security_group_id = aws_security_group.prometheus.id
  description              = "Prometheus scrape"
}

resource "aws_security_group_rule" "dashboard_scrape" {
  type                     = "ingress"
  from_port                = 8081
  to_port                  = 8081
  protocol                 = "tcp"
  security_group_id        = var.dashboard_sg_id
  source_security_group_id = aws_security_group.prometheus.id
  description              = "Prometheus scrape"
}

# ── CloudWatch log groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "prometheus" {
  name              = "/ecs/${var.project}-${var.environment}/prometheus"
  retention_in_days = 7
  kms_key_id        = var.cloudwatch_kms_key_arn
}

resource "aws_cloudwatch_log_group" "grafana" {
  name              = "/ecs/${var.project}-${var.environment}/grafana"
  retention_in_days = 7
  kms_key_id        = var.cloudwatch_kms_key_arn
}

# ── IAM role for observability tasks ─────────────────────────────────────────

resource "aws_iam_role" "observability" {
  name = "${var.project}-${var.environment}-observability-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "observability" {
  role = aws_iam_role.observability.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:DescribeContainerInstances",
          "ecs:DescribeTaskDefinition",
          "ec2:DescribeInstances",
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Prometheus task definition ────────────────────────────────────────────────

resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${var.project}-${var.environment}-prometheus"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = aws_iam_role.observability.arn

  container_definitions = jsonencode([{
    name      = "prometheus"
    image = "${var.ecr_base}/prometheus:v2.51.2"
    essential = true

    portMappings = [{
      containerPort = 9090
      protocol      = "tcp"
    }]

    command = [
      "--config.file=/etc/prometheus/prometheus.yml",
      "--storage.tsdb.path=/prometheus",
      "--storage.tsdb.retention.time=15d",
      "--web.enable-lifecycle",
    ]

    mountPoints = [{
      sourceVolume  = "prometheus-data"
      containerPath = "/prometheus"
      readOnly      = false
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.prometheus.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "prometheus"
      }
    }

    environment = [
      { name = "AWS_REGION", value = var.aws_region }
    ]
  }])

  volume {
    name = "prometheus-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.observability.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.prometheus.id
        iam             = "DISABLED"
      }
    }
  }

  tags = { Service = "prometheus" }
}

# ── Grafana task definition ───────────────────────────────────────────────────

resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.project}-${var.environment}-grafana"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = aws_iam_role.observability.arn

  container_definitions = jsonencode([{
    name      = "grafana"
    image = "${var.ecr_base}/grafana:10.4.2"
    essential = true

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    mountPoints = [{
      sourceVolume  = "grafana-data"
      containerPath = "/var/lib/grafana"
      readOnly      = false
    }]

    environment = [
      { name = "GF_SECURITY_ADMIN_USER",     value = "admin" },
      { name = "GF_SECURITY_ADMIN_PASSWORD", value = "ecscombined2024!" },
      { name = "GF_AUTH_ANONYMOUS_ENABLED",  value = "false" },
      { name = "GF_SERVER_ROOT_URL",         value = "https://${var.project}.${var.environment}.grafana" },
      { name = "GF_PATHS_PROVISIONING",      value = "/etc/grafana/provisioning" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.grafana.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "grafana"
      }
    }
  }])

  volume {
    name = "grafana-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.observability.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.grafana.id
        iam             = "DISABLED"
      }
    }
  }

  tags = { Service = "grafana" }
}

# ── ECS Services ──────────────────────────────────────────────────────────────

resource "aws_ecs_service" "prometheus" {
  name            = "${var.project}-${var.environment}-prometheus"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.prometheus.id]
    assign_public_ip = false
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Service = "prometheus" }
}

resource "aws_ecs_service" "grafana" {
  name            = "${var.project}-${var.environment}-grafana"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.grafana.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Service = "grafana" }
}

# ── ALB target group + listener rule for Grafana ──────────────────────────────

resource "aws_lb_target_group" "grafana" {
  name        = "${var.project}-${var.environment}-grafana"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/api/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = { Name = "${var.project}-${var.environment}-grafana" }
}

resource "aws_lb_listener_rule" "grafana" {
  listener_arn = var.https_listener_arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    path_pattern {
      values = ["/grafana*"]
    }
  }
}