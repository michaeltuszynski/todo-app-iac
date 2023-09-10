output "ecs_task_role" {
  value = aws_iam_role.ecs_task_role.arn
}

output "ecs_execution_role" {
  value = aws_iam_role.ecs_execution_role.arn
}

output "docdb_role" {
  value = aws_iam_role.docdb_role.arn
}
