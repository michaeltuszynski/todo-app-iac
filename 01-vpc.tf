# main.tf
# This fetches the currently available availability zones for use in VPC configuration.
data "aws_availability_zones" "available_zones" {
  state = "available"
}

# Define the main VPC.  Be sure to choose an appropriate private CIDR block. Since this will be hosting a web application, we leave DNS enabled.
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "Name Tag Value"
  }
}

# Define the public subnets.   We use the cidrsubnet helper to carve out appropriately scoped /24 subnets
resource "aws_subnet" "public" {
  count                   = 2
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, 2 + count.index)
  availability_zone       = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id                  = aws_vpc.this.id
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index}"
  }
}

# Define the private subnets.   We use the cidrsubnet helper to carve out appropriately scoped /24 subnets
resource "aws_subnet" "private" {
  count             = 2
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id            = aws_vpc.this.id

  tags = {
    Name = "private-subnet-${count.index}"
  }
}

# Define an internet gateway
resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.this.id
}

# Define a route table that routes the public subnet through the gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateways requires an Elastic IP address (EIP)
resource "aws_eip" "nat" {
  vpc        = true
  depends_on = [aws_internet_gateway.gateway]
}

resource "aws_nat_gateway" "nat_gateway" {
  subnet_id     = aws_subnet.public[0].id
  allocation_id = aws_eip.nat.id
}

# Define the routes that let resources in the private subnet communication with the public internet route (0.0.0.0/0)
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

## VPC Endpoints

# VPC Endpoint for Amazon S3
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private.*.id
  tags = {
    Name = "my-s3-vpc-endpoint"
  }
}

# VPC Endpoint for Secrets Manager
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.us-east-1.secretsmanager"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_tasks.id]
  subnet_ids          = aws_subnet.private.*.id
  private_dns_enabled = true

  tags = {
    Name = "my-secretsmanager-vpc-endpoint"
  }
}

# VPC Endpoint for ECR (Docker)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.us-east-1.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_tasks.id]
  subnet_ids          = aws_subnet.private.*.id
  private_dns_enabled = true
  tags = {
    Name = "my-ECR-docker-vpc-endpoint"
  }
}

# VPC Endpoint for ECR (API)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.us-east-1.ecr.api"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_tasks.id]
  subnet_ids          = aws_subnet.private.*.id
  private_dns_enabled = true
  tags = {
    Name = "my-ECR-API-vpc-endpoint"
  }
}

# VPC Endpoint for CloudWatch Logs
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.us-east-1.logs"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_tasks.id]
  subnet_ids          = aws_subnet.private.*.id
  private_dns_enabled = true
  tags = {
    Name = "my-cloudwatch-vpc-endpoint"
  }
}
