output "public_ip" {
  value = aws_eip.node.public_ip
}

output "ssh" {
  value = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_eip.node.public_ip}"
}

output "app_url" {
  value = "http://${aws_eip.node.public_ip}"
}

output "grafana_url" {
  value = "http://grafana.${aws_eip.node.public_ip}.nip.io"
}
