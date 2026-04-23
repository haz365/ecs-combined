output "sns_topic_arn"       { value = aws_sns_topic.alerts.arn }
output "guardduty_id"        { value = aws_guardduty_detector.main.id }
output "cloudtrail_bucket"   { value = aws_s3_bucket.cloudtrail.bucket }