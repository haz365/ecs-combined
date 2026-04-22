terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_kms_key" "rds" {
  description             = "${var.project}-${var.environment} RDS"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_kms_key" "s3" {
  description             = "${var.project}-${var.environment} S3"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project}-${var.environment}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_kms_key" "secrets" {
  description             = "${var.project}-${var.environment} Secrets Manager"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.project}-${var.environment}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_kms_key" "cloudwatch" {
  description             = "${var.project}-${var.environment} CloudWatch"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "cloudwatch" {
  name          = "alias/${var.project}-${var.environment}-cloudwatch"
  target_key_id = aws_kms_key.cloudwatch.key_id
}

resource "aws_kms_key" "sqs" {
  description             = "${var.project}-${var.environment} SQS"
  deletion_window_in_days = var.key_deletion_window
  enable_key_rotation     = true
}

resource "aws_kms_alias" "sqs" {
  name          = "alias/${var.project}-${var.environment}-sqs"
  target_key_id = aws_kms_key.sqs.key_id
}