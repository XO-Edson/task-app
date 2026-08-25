terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    tls = {
      source = "hashicorp/tls"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name        = "devops-task-vpc"
    Environment = "dev"
  }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name        = "devops-task-public-subnet"
    Environment = "dev"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "devops-task-igw"
    Environment = "dev"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "devops-task-public-route-table"
    Environment = "dev"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "app" {
  name        = "devops-task-sg"
  description = "Security group for the DevOps task application"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "devops-task-sg"
    Environment = "dev"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.app.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  description = "Allow HTTP traffic"
}
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.app.id

  cidr_ipv4   = "102.203.101.200/32"
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"

  description = "Allow SSH from my IP"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.app.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  description = "Allow outbound traffic"
}

resource "aws_key_pair" "app" {
  key_name   = "devops-task-app-key"
  public_key = file("~/.ssh/devops-task-app.pub")

  tags = {
    Name        = "devops-task-app-key"
    Environment = "dev"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  owners = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "app" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.public.id

  vpc_security_group_ids = [
    aws_security_group.app.id
  ]

  key_name = aws_key_pair.app.key_name

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.app.name

  tags = {
    Name        = "devops-task-server"
    Environment = "dev"
  }
}

resource "aws_ecr_repository" "app" {
  name                 = "devops-task-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "devops-task-app"
    Environment = "dev"
  }
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "devops-task-app/db-password"
  description             = "PostgreSQL password for the DevOps task application"

  tags = {
    Name        = "devops-task-db-password"
    Environment = "dev"
  }
}

resource "aws_iam_role" "app" {
  name = "devops-task-app-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "devops-task-app-ec2-role"
    Environment = "dev"
  }
}

resource "aws_iam_policy" "read_db_secret" {
  name        = "devops-task-app-read-db-secret"
  description = "Allow EC2 to read the application database password"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue"
        ]

        Resource = aws_secretsmanager_secret.db_password.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "read_db_secret" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.read_db_secret.arn
}

resource "aws_iam_instance_profile" "app" {
  name = "devops-task-app-instance-profile"
  role = aws_iam_role.app.name
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.github.certificates[0].sha1_fingerprint
  ]

  tags = {
    Name        = "github-actions-oidc"
    Environment = "dev"
  }
}

resource "aws_iam_role" "github_actions" {
  name = "devops-task-app-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }

          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:XO-Edson/task-app:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "devops-task-app-github-actions"
    Environment = "dev"
  }
}

resource "aws_iam_policy" "github_actions_ecr" {
  name        = "devops-task-app-github-actions-ecr"
  description = "Allow GitHub Actions to push the application image to ECR"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },
      {
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]

        Resource = aws_ecr_repository.app.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_ecr.arn
}
