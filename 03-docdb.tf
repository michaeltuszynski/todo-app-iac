## Define a Secret in AWS Secrets Manager to use with the database
resource "random_integer" "password_length" {
  min = 8
  max = 16
}

resource "random_password" "db_password" {
  length  = random_integer.password_length.result
  special = false
}

# AWS requires that named entities like secrets have unique names.   Random pet generates a readable string to append to names to ensure uniqueness.
resource "random_pet" "secret_name" {
  length = 2
}

resource "aws_secretsmanager_secret" "docdb_credentials" {
  name = "my-docdb_credentials-${random_pet.secret_name.id}"
}

# This defines the format the secret is stored as, in this case JSON.  Secrets are versioned, allowing for credential rotation.
resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id     = aws_secretsmanager_secret.docdb_credentials.id
  secret_string = "{\"username\":\"root\", \"password\":\"${random_password.db_password.result}\"}"
}

## Define DocumentDB (Mongo on AWS).  DocumentDB instances are created within clusters.
resource "aws_docdb_cluster" "docdb_cluster" {
  cluster_identifier              = "my-docdb-cluster"
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
  identifier         = "my-docdb-instance"
  cluster_identifier = aws_docdb_cluster.docdb_cluster.cluster_identifier
  instance_class     = "db.r5.large"
}

resource "aws_docdb_subnet_group" "default" {
  name       = "my-subnet-group"
  subnet_ids = aws_subnet.private.*.id

  tags = {
    Name = "default"
  }
}

resource "aws_security_group" "docdb_sg" {
  name        = "my-docdb_sg"
  description = "Security group for DocumentDB"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
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

resource "aws_iam_role" "docdb_role" {
  name = "DocDBCloudWatchRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })
}