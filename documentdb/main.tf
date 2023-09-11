## Secrets for DB

resource "random_integer" "password_length" {
  min = 8
  max = 16
}

resource "random_password" "db_password" {
  length  = random_integer.password_length.result
  special = false
}

resource "random_pet" "secret_name" {
  length = 2
}

resource "aws_secretsmanager_secret" "docdb_credentials" {
  name = "${var.app_name}-docdb_credentials-${random_pet.secret_name.id}"
}

resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id     = aws_secretsmanager_secret.docdb_credentials.id
  secret_string = "{\"username\":\"root\", \"password\":\"${random_password.db_password.result}\"}"
}

## DocumentDB (Mongo on AWS)
resource "aws_docdb_cluster" "docdb_cluster" {
  cluster_identifier              = "${var.app_name}-docdb-cluster"
  skip_final_snapshot             = true
  engine_version                  = "4.0.0"
  backup_retention_period         = 1
  enabled_cloudwatch_logs_exports = ["audit", "profiler"]
  master_username                 = jsondecode(aws_secretsmanager_secret_version.db_secret_version.secret_string)["username"]
  master_password                 = jsondecode(aws_secretsmanager_secret_version.db_secret_version.secret_string)["password"]
  db_subnet_group_name            = aws_docdb_subnet_group.default.name
  vpc_security_group_ids          = [aws_security_group.docdb_sg.id]
}

resource "aws_docdb_cluster_instance" "docdb_instance" {
  identifier         = "${var.app_name}-docdb-instance"
  cluster_identifier = aws_docdb_cluster.docdb_cluster.cluster_identifier
  instance_class     = "db.r5.large"
}

resource "aws_docdb_subnet_group" "default" {
  name       = "${var.app_name}-subnet-group"
  subnet_ids = var.private_subnets

  tags = {
    Name = "default"
  }
}

resource "aws_security_group" "docdb_sg" {
  name        = "${var.app_name}-docdb_sg"
  description = "Security group for DocumentDB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0", var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "docdb_sg"
  }
}