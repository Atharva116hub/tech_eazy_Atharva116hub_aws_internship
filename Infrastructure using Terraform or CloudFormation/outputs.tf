output "instance_public_ip" {
  description = "The public IP address of the EC2 instance."
  value       = aws_instance.app_server.public_ip
}

output "app_url" {
  description = "The URL where the application should be reachable."
  value       = "http://${aws_instance.app_server.public_ip}:${var.app_port}"
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket created for logs."
  value       = aws_s3_bucket.app_logs_bucket.bucket
}

output "s3_read_only_role_arn" {
  description = "ARN of the S3 Read-Only IAM Role."
  value       = aws_iam_role.s3_read_only_role.arn
}

output "cleanup_instructions" {
  description = "Manual commands to clean up AWS resources after use."
  value = [
    "",
    "--- IMPORTANT: MANUAL CLEANUP INSTRUCTIONS ---",
    "Terraform 'destroy' is the primary way to clean up. However, if 'terraform destroy' fails or if you prefer manual steps for verification, use these:",
    "",
    "1. Stop the EC2 instance (if not already stopped):",
    "   aws ec2 stop-instances --instance-ids ${aws_instance.app_server.id} --region ${var.region}",
    "2. Wait for instance to stop:",
    "   aws ec2 wait instance-stopped --instance-ids ${aws_instance.app_server.id} --region ${var.region}",
    "3. Terminate the EC2 instance:",
    "   aws ec2 terminate-instances --instance-ids ${aws_instance.app_server.id} --region ${var.region}",
    "4. Empty the S3 bucket:",
    "   aws s3 rm s3://${aws_s3_bucket.app_logs_bucket.id}/ --recursive --region ${var.region}",
    "5. Delete the S3 bucket:",
    "   aws s3api delete-bucket --bucket ${aws_s3_bucket.app_logs_bucket.id} --region ${var.region}",
    "6. Detach and delete IAM Policy for S3 Write Role:",
    "   aws iam detach-role-policy --role-name ${aws_iam_role.s3_write_role.name} --policy-arn ${aws_iam_policy.s3_write_policy.arn} --region ${var.region}",
    "   aws iam delete-policy --policy-arn ${aws_iam_policy.s3_write_policy.arn} --region ${var.region}",
    "7. Detach and delete IAM Policy for S3 Read-Only Role:",
    "   aws iam detach-role-policy --role-name ${aws_iam_role.s3_read_only_role.name} --policy-arn ${aws_iam_policy.s3_read_only_policy.arn} --region ${var.region}",
    "   aws iam delete-policy --policy-arn ${aws_iam_policy.s3_read_only_policy.arn} --region ${var.region}",
    "8. Remove role from instance profile:",
    "   aws iam remove-role-from-instance-profile --instance-profile-name ${aws_iam_instance_profile.ec2_s3_write_profile.name} --role-name ${aws_iam_role.s3_write_role.name} --region ${var.region}",
    "9. Delete instance profile:",
    "   aws iam delete-instance-profile --instance-profile-name ${aws_iam_instance_profile.ec2_s3_write_profile.name} --region ${var.region}",
    "10. Delete IAM Roles:",
    "    aws iam delete-role --role-name ${aws_iam_role.s3_write_role.name} --region ${var.region}",
    "    aws iam delete-role --role-name ${aws_iam_role.s3_read_only_role.name} --region ${var.region}",
    "",
    "Note: IAM deletions might require waiting a few minutes for propagation."
  ]
}
