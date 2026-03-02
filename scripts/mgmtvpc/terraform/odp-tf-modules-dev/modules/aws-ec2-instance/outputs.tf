# Outputs for EC2 Instance

output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.this.id
}

output "instance_public_ip" {
  description = "The public IP address of the EC2 instance"
  value       = aws_instance.this.public_ip
}

output "instance_private_ip" {
  description = "The private IP address of the EC2 instance"
  value       = aws_instance.this.private_ip
}

output "instance_availability_zone" {
  description = "The availability zone of the EC2 instance"
  value       = aws_instance.this.availability_zone
}

output "instance_arn" {
  description = "The ARN of the EC2 instance"
  value       = aws_instance.this.arn
}

output "instance_state" {
  description = "The current state of the EC2 instance"
  value       = aws_instance.this.instance_state
}
