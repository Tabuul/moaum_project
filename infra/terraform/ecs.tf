resource "aws_ecs_cluster" "main" {
  name = local.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_service_discovery_http_namespace" "internal" {
  name = "${local.name}.internal"
}

resource "aws_cloudwatch_log_group" "svc" {
  for_each          = toset(["api", "frontend", "migrate"])
  name              = "/ecs/${local.name}/${each.key}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# The execution role pulls the image, writes logs and reads the secrets at start.
resource "aws_iam_role" "execution" {
  name               = "${local.name}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "read_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = concat(
      [aws_secretsmanager_secret.hmac.arn, aws_db_instance.main.master_user_secret[0].secret_arn],
      [for s in aws_secretsmanager_secret.app : s.arn],
    )
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.read_secrets.json
}

# The task role is what the running application may do. Today: nothing in AWS
# (files are still in the database) except answer ECS Exec, for psql from inside
# a task. S3 permissions are added here when file storage moves (phase 2).
resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "task_exec_command" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_exec_command" {
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_exec_command.json
}

locals {
  db_secret = aws_db_instance.main.master_user_secret[0].secret_arn
  db_host   = aws_db_instance.main.address

  api_secrets = concat(
    [
      { name = "PGPASSWORD", valueFrom = "${local.db_secret}:password::" },
      { name = "MOAUM_AUTH_HMAC_SECRET", valueFrom = aws_secretsmanager_secret.hmac.arn },
    ],
    [for k, s in aws_secretsmanager_secret.app : { name = k, valueFrom = s.arn }],
  )

  api_env = [
    { name = "JDBC_DATABASE_URL", value = "jdbc:postgresql://${local.db_host}:5432/moaumpp?sslmode=require" },
    { name = "PGUSER", value = aws_db_instance.main.username },
    { name = "DB_POOL_SIZE", value = tostring(var.db_pool_size) },
    { name = "MOAUM_PORTAL_URL", value = var.portal_url },
    { name = "PORT", value = "8081" },
  ]

  logs = { for k, g in aws_cloudwatch_log_group.svc : k => {
    logDriver = "awslogs"
    options = {
      awslogs-group         = g.name
      awslogs-region        = var.region
      awslogs-stream-prefix = k
    }
  } }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.api_cpu
  memory                   = var.api_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name             = "api"
    image            = "${aws_ecr_repository.svc["api"].repository_url}:${var.api_image_tag}"
    essential        = true
    portMappings     = [{ name = "api", containerPort = 8081, protocol = "tcp" }]
    environment      = local.api_env
    secrets          = local.api_secrets
    logConfiguration = local.logs["api"]
    healthCheck = {
      command     = ["CMD-SHELL", "curl -fsS http://localhost:8081/actuator/health/liveness || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 90
    }
  }])
}

# One-off task: bash db/migrate.sh from the API image, run by the deploy
# workflow before the new API revision is rolled out. Same image, same scripts.
resource "aws_ecs_task_definition" "migrate" {
  family                   = "${local.name}-migrate"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "migrate"
    image     = "${aws_ecr_repository.svc["api"].repository_url}:${var.api_image_tag}"
    essential = true
    command   = ["bash", "db/migrate.sh"]
    environment = [
      { name = "DATABASE_URL", value = "postgres://${aws_db_instance.main.username}@${local.db_host}:5432/moaumpp?sslmode=require" },
    ]
    secrets          = [{ name = "PGPASSWORD", valueFrom = "${local.db_secret}:password::" }]
    logConfiguration = local.logs["migrate"]
  }])
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.name}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.frontend_cpu
  memory                   = var.frontend_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "frontend"
    image        = "${aws_ecr_repository.svc["frontend"].repository_url}:${var.frontend_image_tag}"
    essential    = true
    portMappings = [{ name = "web", containerPort = 3000, protocol = "tcp" }]
    environment = [
      # Service Connect name, never the internet: the BFF's only route to the API.
      { name = "PORTAL_API_URL", value = "http://api:8081" },
      # awsvpc tasks are IPv4; the image's default "::" is for Railway's network.
      { name = "HOSTNAME", value = "0.0.0.0" },
      { name = "PORT", value = "3000" },
      { name = "NODE_ENV", value = "production" },
    ]
    logConfiguration = local.logs["frontend"]
  }])
}

resource "aws_ecs_service" "api" {
  name                              = "api"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.api.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 180
  enable_execute_command            = true

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.tasks.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8081
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.internal.arn
    service {
      port_name      = "api"
      discovery_name = "api"
      client_alias {
        port     = 8081
        dns_name = "api"
      }
    }
  }

  # The deploy workflow registers task-definition revisions by commit SHA and
  # sets the count; Terraform must not undo a deployment on its next apply.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}

resource "aws_ecs_service" "frontend" {
  name                              = "frontend"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.frontend.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60
  enable_execute_command            = true

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.tasks.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 3000
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.internal.arn
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_ecs_service.api]
}
