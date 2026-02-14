output "n8n_url" {
  description = "n8n 웹 UI 접속 URL"
  value       = "http://${aws_eip.n8n_eip.public_ip}:${var.n8n_port}"
}

output "elastic_ip" {
  description = "Elastic IP 주소"
  value       = aws_eip.n8n_eip.public_ip
}

output "ssh_command" {
  description = "SSH 접속 명령어"
  value       = "ssh -i ${var.key_pair_name}.pem ec2-user@${aws_eip.n8n_eip.public_ip}"
}

output "instance_id" {
  description = "EC2 인스턴스 ID"
  value       = aws_instance.n8n_server.id
}
