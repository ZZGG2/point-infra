# RDS for PostgreSQL 16 Multi-AZ (ADR-0006 엔진, ADR-0013)
# Debezium CDC 를 위해 논리 복제 활성화 (ADR-0005), 전송 암호화 강제
resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-pg16"
  family = "postgres16"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  tags = var.tags
}

resource "aws_kms_key" "this" {
  description         = "${var.name} rds encryption"
  enable_key_rotation = true
  tags                = var.tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "RDS PostgreSQL"
  vpc_id      = var.vpc_id
  ingress {
    description     = "PostgreSQL from EKS nodes / MSK Connect"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "${var.name}-rds" })
}

# 마스터 비밀번호는 db-init Job(k8s/overlays/aws/db-init.yaml)이 app_rw 생성에만 사용 → Secrets Manager 경유
resource "random_password" "master" {
  length  = 32
  special = false
}

resource "random_password" "app" {
  length  = 32
  special = false
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-pg"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class
  multi_az       = var.multi_az

  db_name  = "point"
  username = "postgres"
  password = random_password.master.result
  port     = 5432

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.this.arn

  db_subnet_group_name   = var.db_subnet_group
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  backup_retention_period    = 7
  auto_minor_version_upgrade = true
  apply_immediately          = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = !var.deletion_protection
  final_snapshot_identifier  = var.deletion_protection ? "${var.name}-pg-final" : null

  performance_insights_enabled = true
  tags                         = var.tags
}
