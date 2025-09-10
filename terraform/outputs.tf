output "public_ip" {
  value = aws_instance.ci_ephemeral.public_ip
}

output "instance_id" {
  value = aws_instance.ci_ephemeral.id
}
