resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = aws_subnet.private[*].id
}

# Tuned from what production showed on Railway: 29 GB of sorts spilled to disk on
# a 4 MB work_mem, SSD storage costed as spinning disk, no I/O timing, no lock
# logging. Sized for db.t4g.medium (4 GiB): shared_buffers stays at RDS's 25 %.
# pg_stat_statements is what the performance audit is read from; keep it on.
resource "aws_db_parameter_group" "pg17" {
  name   = "${local.name}-pg17"
  family = "postgres17"

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "pg_stat_statements.track"
    value = "all"
  }
  parameter {
    name  = "work_mem"
    value = "16384" # kB: 16 MB per sort/hash node; the pools are small
  }
  parameter {
    name  = "maintenance_work_mem"
    value = "262144" # kB: 256 MB for index builds and vacuum
  }
  parameter {
    name  = "random_page_cost"
    value = "1.1"
  }
  parameter {
    name  = "effective_io_concurrency"
    value = "200"
  }
  parameter {
    name  = "track_io_timing"
    value = "1"
  }
  parameter {
    name  = "log_lock_waits"
    value = "1"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "2000" # ms: a query slower than this is in the log by text
  }
  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "300000" # ms: a forgotten open transaction cannot hold locks for ever
  }
}

resource "aws_db_instance" "main" {
  identifier     = local.name
  engine         = "postgres"
  engine_version = "17"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 10
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name                     = "moaumpp"
  username                    = "moaum_admin"
  manage_master_user_password = true

  multi_az               = var.db_multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.pg17.name
  publicly_accessible    = false

  backup_retention_period   = 14
  copy_tags_to_snapshot     = true
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-final"

  performance_insights_enabled = true
}
