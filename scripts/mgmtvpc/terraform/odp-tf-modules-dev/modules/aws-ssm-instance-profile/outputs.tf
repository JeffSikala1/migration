output "ssm_instance_profile_name" {
  description = "The name of the created SSM Instance Profile"
  value       = aws_iam_instance_profile.ssm_instance_profile.name
}

output "ssm_instance_profile_arn" {
  description = "The ARN of the created SSM Instance Profile"
  value       = aws_iam_instance_profile.ssm_instance_profile.arn
}
