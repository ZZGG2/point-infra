# Aurora PostgreSQL — Debezium CDC를 위해 논리 복제 활성화 (ADR-0005, 0006)
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
  tags = var.tags
}

resource "aws_kms_key" "aurora" {
  description         = "${var.name} aurora encryption"
  enable_key_rotation = true
  tags                = var.tags
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
  final_snapshot_identifier       = var.deletion_protection ? "${var.name}-aurora-final" : null
  enable_http_endpoint            = true # RDS Data API: 앱 계정(app_rw) 초기 생성용 (VPC 밖에서 SQL 실행)
  apply_immediately               = true

  # Data API 는 t 계열 인스턴스를 지원하지 않는다 → Serverless v2 (평시 최소 ACU, 이벤트 시 자동 확장)
  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.instance_class == "db.serverless" ? [1] : []
    content {
      min_capacity = var.serverless_min_acu
      max_capacity = var.serverless_max_acu
    }
  }
  tags = var.tags
}

resource "aws_rds_cluster_instance" "this" {
  count               = var.instance_count # writer 1 + reader N (Multi-AZ)
  identifier          = "${var.name}-aurora-${count.index}"
  cluster_identifier  = aws_rds_cluster.this.id
  instance_class      = var.instance_class
  engine              = aws_rds_cluster.this.engine
  engine_version      = aws_rds_cluster.this.engine_version
  publicly_accessible = false
  tags                = var.tags
}

resource "aws_security_group" "aurora" {
  name        = "${var.name}-aurora"
  description = "Aurora PostgreSQL"
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
  tags = merge(var.tags, { Name = "${var.name}-aurora" })
}

# 앱 전용 계정 app_rw (security.md §3) — 마스터 계정은 앱에 주지 않는다.
# Aurora 는 Private-Data 서브넷에 있으므로 RDS Data API 로 실행한다. (실행 PC 에 AWS CLI + PowerShell 7 필요)
resource "random_password" "app" {
  length  = 32
  special = false
}

resource "terraform_data" "app_user" {
  triggers_replace = [aws_rds_cluster.this.cluster_resource_id, sha256(random_password.app.result)]
  depends_on       = [aws_rds_cluster_instance.this]

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-NonInteractive", "-File"]
    command     = "${path.module}/create-app-user.ps1"
    environment = {
      CLUSTER_ARN = aws_rds_cluster.this.arn
      SECRET_ARN  = aws_rds_cluster.this.master_user_secret[0].secret_arn
      REGION      = var.region
      APP_PW      = random_password.app.result
    }
  }
}
