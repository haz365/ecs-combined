terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project}-${var.environment}-click-events-dlq"
  kms_master_key_id         = var.kms_key_arn
  message_retention_seconds = 1209600
  tags = { Name = "${var.project}-${var.environment}-click-events-dlq" }
}

resource "aws_sqs_queue" "click_events" {
  name                       = "${var.project}-${var.environment}-click-events"
  kms_master_key_id          = var.kms_key_arn
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })

  tags = { Name = "${var.project}-${var.environment}-click-events" }
}

resource "aws_sqs_queue_policy" "click_events" {
  queue_url = aws_sqs_queue.click_events.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowTaskRoles"
        Effect = "Allow"
        Principal = {
          AWS = var.allowed_role_arns
        }
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Resource = aws_sqs_queue.click_events.arn
      },
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.click_events.arn
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}