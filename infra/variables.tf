variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-1"
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t2.micro"
}

variable "volume_size" {
  description = "EBS 볼륨 크기 (GB, Free Tier 최대 30GB)"
  type        = number
  default     = 30
}

variable "key_pair_name" {
  description = "EC2 SSH 키 페어 이름 (AWS 콘솔에서 미리 생성 필요)"
  type        = string
}

variable "allowed_cidr" {
  description = "SSH 및 n8n 접속을 허용할 CIDR (예: \"1.2.3.4/32\")"
  type        = string
}

variable "n8n_port" {
  description = "n8n 웹 UI 포트"
  type        = number
  default     = 5678
}

variable "n8n_timezone" {
  description = "n8n 타임존"
  type        = string
  default     = "Asia/Seoul"
}
