# ElastiCache Valkey — 이벤트 대기열·중복 방지·재고 카운터 (ADR-0007)
# event-service 가 단일 엔드포인트(spring.data.redis.host) + 다중 키 Lua 를 사용하므로
# Cluster mode 는 끄고(샤드 1개) Primary + Replica, Multi-AZ 로 구성한다.
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-cache"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-redis"
  description = "ElastiCache Valkey"
  vpc_id      = var.vpc_id
  ingress {
    description     = "Valkey from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "${var.name}-redis" })
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name}-redis"
  description          = "${var.name} event queue / dedup"
  engine               = "valkey"
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = 6379

  num_cache_clusters         = var.replicas + 1
  automatic_failover_enabled = var.replicas > 0
  multi_az_enabled           = var.replicas > 0

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  apply_immediately          = true
  tags                       = var.tags
}
