# Aurora PostgreSQL — Debezium CDC를 위해 논리 복제 활성화 (ADR-0005, 0006)
# ※ ADR-0006 은 ADR-0013(RDS for PostgreSQL)으로 대체됨 → 구현 단계에서 modules/aws/rds 로 교체 예정
resource "aws_rds_cluster_parameter_group" "this" {
  name   = "${var.name}-aurora-pg16"
  family = "aurora-postgresql16"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_kms_key" "aurora" {
  description         = "${var.name} aurora encryption"
  enable_key_rotation = true
}

resource "aws_rds_cluster" "this" {
  cluster_identifier              = "${var.name}-aurora"
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  database_name                   = "point"
  master_username                 = "postgres"
  manage_master_user_password     = true # Secrets Manager 자동 관리
  db_subnet_group_name            = var.db_subnet_group
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.aurora.arn
  backup_retention_period         = 7
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = !var.deletion_protection
  tags                            = var.tags
}

resource "aws_rds_cluster_instance" "this" {
  count              = var.instance_count # writer 1 + reader N (Multi-AZ)
  identifier         = "${var.name}-aurora-${count.index}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.this.engine
}

resource "aws_security_group" "aurora" {
  name   = "${var.name}-aurora"
  vpc_id = var.vpc_id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids # EKS 노드, MSK Connect
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
