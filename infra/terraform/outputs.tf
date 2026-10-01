output "alb_dns_name" { value = aws_lb.main.dns_name }
output "ecr_api" { value = aws_ecr_repository.svc["api"].repository_url }
output "ecr_frontend" { value = aws_ecr_repository.svc["frontend"].repository_url }
output "cluster" { value = aws_ecs_cluster.main.name }
output "migrate_task_definition" { value = aws_ecs_task_definition.migrate.family }
output "private_subnets" { value = aws_subnet.private[*].id }
output "tasks_security_group" { value = aws_security_group.tasks.id }
output "db_endpoint" { value = aws_db_instance.main.address }
