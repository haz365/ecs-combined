terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "platform"
    }
  }
}

data "aws_caller_identity" "current" {}

# ── KMS ───────────────────────────────────────────────────────────────────────
module "kms" {
  source      = "../../modules/kms"
  project     = var.project
  environment = var.environment
}

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source                 = "../../modules/vpc"
  project                = var.project
  environment            = var.environment
  vpc_cidr               = "10.0.0.0/16"
  cloudwatch_kms_key_arn = module.kms.cloudwatch_key_arn
}

# ── ECR ───────────────────────────────────────────────────────────────────────
module "ecr" {
  source      = "../../modules/ecr"
  project     = var.project
  environment = var.environment
  kms_key_arn = module.kms.s3_key_arn
}

# ── SQS ───────────────────────────────────────────────────────────────────────
module "sqs" {
  source      = "../../modules/sqs"
  project     = var.project
  environment = var.environment
  kms_key_arn = module.kms.sqs_key_arn
  allowed_role_arns = [
    module.iam.api_task_role_arn,
    module.iam.worker_task_role_arn,
  ]
}

# ── RDS ───────────────────────────────────────────────────────────────────────
module "rds" {
  source      = "../../modules/rds"
  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id

  private_subnet_ids = module.vpc.private_subnet_ids
  allowed_security_group_ids = [
    module.ecs_api.security_group_id,
    module.ecs_worker.security_group_id,
    module.ecs_dashboard.security_group_id,
  ]

  rds_kms_key_arn     = module.kms.rds_key_arn
  secrets_kms_key_arn = module.kms.secrets_key_arn

  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  multi_az              = false
  backup_retention_days = 0
  deletion_protection   = false
}

# ── Redis ─────────────────────────────────────────────────────────────────────
module "redis" {
  source      = "../../modules/redis"
  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id

  private_subnet_ids = module.vpc.private_subnet_ids
  allowed_security_group_ids = [
    module.ecs_api.security_group_id,
  ]

  kms_key_arn         = module.kms.rds_key_arn
  secrets_kms_key_arn = module.kms.secrets_key_arn
  node_type           = "cache.t3.micro"
  num_cache_nodes     = 1
}

# ── IAM ───────────────────────────────────────────────────────────────────────
module "iam" {
  source      = "../../modules/iam"
  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
  account_id  = data.aws_caller_identity.current.account_id

  ecr_repository_arns = values(module.ecr.repository_arns)

  secrets_arns = [
    module.rds.secret_arn,
    module.redis.auth_token_secret_arn,
  ]

  sqs_queue_arn          = module.sqs.queue_arn
  s3_logs_bucket         = module.alb_waf.alb_logs_bucket
  cloudwatch_kms_key_arn = module.kms.cloudwatch_key_arn
  secrets_kms_key_arn    = module.kms.secrets_key_arn
  sqs_kms_key_arn        = module.kms.sqs_key_arn
  rds_kms_key_arn        = module.kms.rds_key_arn
}

# ── ALB + WAF ─────────────────────────────────────────────────────────────────
module "alb_waf" {
  source      = "../../modules/alb-waf"
  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id

  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = var.certificate_arn
  s3_logs_bucket    = "${var.project}-${var.environment}-alb-logs"
  s3_kms_key_arn    = module.kms.s3_key_arn
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.project}-${var.environment}" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ── ECS Services ──────────────────────────────────────────────────────────────
module "ecs_api" {
  source      = "../../modules/ecs-service"
  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  cluster_id         = aws_ecs_cluster.main.id
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  alb_sg_id          = module.alb_waf.alb_sg_id

  service_name   = "api"
  image_uri      = "${module.ecr.repository_urls["api"]}:latest"
  container_port = 8080
  cpu            = 256
  memory         = 512
  desired_count  = 2

  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.api_task_role_arn
  target_group_arn   = module.alb_waf.api_target_group_arn
  log_group_name     = module.iam.log_group_names["api"]

  environment_vars = [
    { name = "DB_HOST",    value = module.rds.db_host },
    { name = "DB_PORT",    value = tostring(module.rds.db_port) },
    { name = "DB_NAME",    value = module.rds.db_name },
    { name = "DB_USER",    value = module.rds.db_username },
    { name = "REDIS_HOST", value = module.redis.primary_endpoint },
    { name = "REDIS_PORT", value = "6379" },
    { name = "REDIS_TLS",  value = "true" },
    { name = "AWS_REGION", value = var.aws_region },
    { name = "SQS_QUEUE_URL", value = module.sqs.queue_url },
    { name = "BASE_URL",   value = "https://app.dev.${var.domain}" },
  ]

  secrets = [
    { name = "DB_PASSWORD",  valueFrom = "${module.rds.secret_arn}:password::" },
    { name = "REDIS_TOKEN",  valueFrom = module.redis.auth_token_secret_arn },
  ]
}

module "ecs_worker" {
  source      = "../../modules/ecs-service"
  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  cluster_id         = aws_ecs_cluster.main.id
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  alb_sg_id          = module.alb_waf.alb_sg_id

  service_name         = "worker"
  image_uri            = "${module.ecr.repository_urls["worker"]}:latest"
  container_port       = 9091
  cpu                  = 256
  memory               = 512
  desired_count        = 1
  enable_load_balancer = false

  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.worker_task_role_arn
  log_group_name     = module.iam.log_group_names["worker"]
  health_check_path  = "/health"

  environment_vars = [
    { name = "DB_HOST",       value = module.rds.db_host },
    { name = "DB_PORT",       value = tostring(module.rds.db_port) },
    { name = "DB_NAME",       value = module.rds.db_name },
    { name = "DB_USER",       value = module.rds.db_username },
    { name = "AWS_REGION",    value = var.aws_region },
    { name = "SQS_QUEUE_URL", value = module.sqs.queue_url },
    { name = "METRICS_PORT",  value = "9091" },
  ]

  secrets = [
    { name = "DB_PASSWORD", valueFrom = "${module.rds.secret_arn}:password::" },
  ]
}

module "ecs_dashboard" {
  source      = "../../modules/ecs-service"
  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  cluster_id         = aws_ecs_cluster.main.id
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  alb_sg_id          = module.alb_waf.alb_sg_id

  service_name   = "dashboard"
  image_uri      = "${module.ecr.repository_urls["dashboard"]}:latest"
  container_port = 8081
  cpu            = 256
  memory         = 512
  desired_count  = 2

  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.dashboard_task_role_arn
  target_group_arn   = module.alb_waf.dashboard_target_group_arn
  log_group_name     = module.iam.log_group_names["dashboard"]

  environment_vars = [
    { name = "DB_HOST", value = module.rds.db_host },
    { name = "DB_PORT", value = tostring(module.rds.db_port) },
    { name = "DB_NAME", value = module.rds.db_name },
    { name = "DB_USER", value = module.rds.db_username },
    { name = "PORT",    value = "8081" },
  ]

  secrets = [
    { name = "DB_PASSWORD", valueFrom = "${module.rds.secret_arn}:password::" },
  ]
}