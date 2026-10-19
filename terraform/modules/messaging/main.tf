resource "aws_sns_topic" "order_events" {
  name              = "${var.name}-order-events"
  kms_master_key_id = var.kms_key_arn
}