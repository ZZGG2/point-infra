# MSK — 이벤트 결과 비동기 전달 (ADR-0008), CDC 파이프라인 (ADR-0005)
# 클라이언트 인증: TLS(9094, 무인증) + IAM(9098) 리스너를 함께 연다.
#   현재 앱에는 aws-msk-iam-auth 라이브러리가 없어 TLS 리스너를 사용한다. (IAM 전환 시 9098 만 남기면 됨)
# TODO: MSK Connect(Debezium source / JDBC sink) — GCP DR(Cloud SQL, HA VPN) 구축 시 추가. 커넥터 설정은 cdc/ 참조
resource "aws_security_group" "this" {
  name        = "${var.name}-msk"
  description = "MSK brokers"
  vpc_id      = var.vpc_id
  ingress {
    description     = "Kafka TLS(9094) / IAM(9098) from EKS nodes"
    from_port       = 9094
    to_port         = 9098
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "${var.name}-msk" })
}

resource "aws_msk_configuration" "this" {
  name           = "${var.name}-kafka"
  kafka_versions = [var.kafka_version]
  # 앱이 토픽을 직접 만들지 않으므로 자동 생성 허용 (파티션 수는 data-architecture.md §3 기준)
  server_properties = <<-PROPS
    auto.create.topics.enable=true
    default.replication.factor=${min(var.broker_count, 3)}
    min.insync.replicas=${var.broker_count >= 3 ? 2 : 1}
    num.partitions=12
    log.retention.hours=168
  PROPS
}

resource "aws_kms_key" "msk" {
  description         = "${var.name} msk encryption"
  enable_key_rotation = true
  tags                = var.tags
}

resource "aws_msk_cluster" "this" {
  cluster_name           = "${var.name}-msk"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_count

  broker_node_group_info {
    instance_type   = var.instance_type
    client_subnets  = var.subnet_ids
    security_groups = [aws_security_group.this.id]
    storage_info {
      ebs_storage_info { volume_size = var.volume_size }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  client_authentication {
    unauthenticated = true
    sasl { iam = true }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }
  tags = var.tags
}
