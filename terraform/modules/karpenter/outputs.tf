output "karpenter_role_arn" {
  description = "Karpenter controller IRSA role ARN"
  value       = aws_iam_role.controller.arn
}

output "karpenter_queue_name" {
  description = "SQS interruption queue name"
  value       = aws_sqs_queue.interruption.name
}

output "karpenter_queue_arn" {
  description = "SQS interruption queue ARN"
  value       = aws_sqs_queue.interruption.arn
}

output "karpenter_instance_profile_name" {
  description = "Instance profile for Karpenter-launched nodes"
  value       = aws_iam_instance_profile.node.name
}
