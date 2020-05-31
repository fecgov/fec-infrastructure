variable "region" { default = "us-gov-west-1" }
variable "rds_az1" { default = "us-gov-west-1a" }
variable "rds_az2" { default = "us-gov-west-1b" }
variable "rds_vpc_cidr_block" {}
variable "rds_cidr_block_az1" {}
variable "rds_cidr_block_az2" {}
variable "rds_production_password" {}
variable "rds_staging_password" {}
variable "rds_development_password" {}

terraform {
  backend "s3" {
    bucket = "tts-fec"
    encrypt=true
    key="fec/terraform.tfstate"
  }
}

provider "aws" {
  region = "${var.region}"
}

resource "aws_vpc" "rds" {
  cidr_block = "${var.rds_vpc_cidr_block}"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "rds" {
  vpc_id = "${aws_vpc.rds.id}"
}

resource "aws_subnet" "rds_az1" {
  vpc_id = "${aws_vpc.rds.id}"
  cidr_block = "${var.rds_cidr_block_az1}"
  availability_zone = "${var.rds_az1}"
}

resource "aws_subnet" "rds_az2" {
  vpc_id = "${aws_vpc.rds.id}"
  cidr_block = "${var.rds_cidr_block_az2}"
  availability_zone = "${var.rds_az2}"
}

resource "aws_db_subnet_group" "rds" {
  name = "fec_rds"
  subnet_ids = ["${aws_subnet.rds_az1.id}", "${aws_subnet.rds_az2.id}"]
}

resource "aws_route_table" "rds" {
  vpc_id = "${aws_vpc.rds.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.rds.id}"
  }
}

resource "aws_route_table_association" "rds_az1" {
  subnet_id = "${aws_subnet.rds_az1.id}"
  route_table_id = "${aws_route_table.rds.id}"
}

resource "aws_route_table_association" "rds_az2" {
  subnet_id = "${aws_subnet.rds_az2.id}"
  route_table_id = "${aws_route_table.rds.id}"
}

/* TODO: Lock down ingress rules */
resource "aws_security_group" "rds" {
  name = "fec_rds"
  vpc_id = "${aws_vpc.rds.id}"

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_parameter_group" "fec_default" {
    name = "fec-default"
    family = "postgres9.6"
    description = "Custom parameters to support FEC"

    parameter {
        name = "max_parallel_workers_per_gather"
        value = "4"
    }

    parameter {
        name  = "log_connections"
        value = "1"
    }

    parameter {
        name  = "log_disconnections"
        value = "1"
    }

    parameter {
        name  = "log_hostname"
        value = "0"
    }

    parameter {
        name  = "log_statement"
        value = "ddl"
    }

    parameter {
        name  = "log_min_duration_statement"
        value = "1000" # in ms - 1s
    }

    parameter {
        name  = "max_standby_streaming_delay" # This has no effect on masters, it only affects slaves
        value = "1200000" # in mS
    }

    parameter {
        name  = "work_mem"
        value = "65536" # in kB - 64MB
    }

    parameter {
        name  = "checkpoint_timeout"
        value = "900" # in seconds - 15 minutes
    }
}

/* RDS Logging Role */
resource "aws_iam_role" "rds_logs_role" {
  name = "rds_logs_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "monitoring.rds.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

/* RDS Logging Policy */
resource "aws_iam_role_policy" "rds_logs_policy" {
  depends_on = ["aws_iam_role.rds_logs_role"]
  name = "rds_logs_policy"
  role = "${aws_iam_role.rds_logs_role.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableCreationAndManagementOfRDSCloudwatchLogGroups",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:PutRetentionPolicy"
      ],
      "Resource": [
        "arn:aws-us-gov:logs:*:*:log-group:RDS*"
      ]
    },
    {
      "Sid": "EnableCreationAndManagementOfRDSCloudwatchLogStreams",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents"
      ],
      "Resource": [
        "arn:aws-us-gov:logs:*:*:log-group:RDS*:log-stream:*"
      ]
    }
  ]
}
EOF
}

resource "aws_db_instance" "rds_development" {
  lifecycle {
    prevent_destroy = true
  }
  snapshot_identifier = "rds:tf-20170223214825431394805grs-2017-03-16-09-02"
  engine = "postgres"
  engine_version = "9.6.1"
  instance_class = "db.r4.2xlarge"
  allocated_storage = 4000
  name = "fec"
  username = "fec"
  password = "${var.rds_development_password}"
  db_subnet_group_name = "${aws_db_subnet_group.rds.name}"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"]
  backup_retention_period = 30
  publicly_accessible = true
  storage_encrypted = true
  storage_type = "gp2"
  auto_minor_version_upgrade = true
  identifier = "fec-govcloud-dev"
  maintenance_window = "Sat:06:00-Sat:08:00"
  # parameter_group_name = "${aws_db_parameter_group.fec_default.id}"
  parameter_group_name = "fec-default-log-all-dev"
  monitoring_role_arn = "${aws_iam_role.rds_logs_role.arn}"
  monitoring_interval = 5
  enabled_cloudwatch_logs_exports = ["postgresql"]
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately = true
}

# Creating Aurora clusters and instances

resource "aws_rds_cluster" "production-aurora-cluster" {
  cluster_identifier = "prod-aurora-cluster"
  database_name = "fec"
  master_username = "fec"
  master_password = "${var.rds_production_password}"
  backup_retention_period = 7
  preferred_backup_window = "06:00-08:00"
  preferred_maintenance_window = "Sat:10:00-Sat:12:00"
  db_subnet_group_name = "fec_rds"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"] 
  storage_encrypted = true
  copy_tags_to_snapshot = true
  deletion_protection = true
  apply_immediately = true
  skip_final_snapshot = true
  engine = "aurora-postgresql"
  engine_version = "10.7"
}

resource "aws_rds_cluster_instance" "production_aurora_inst" {
  cluster_identifier = "${aws_rds_cluster.production-aurora-cluster.id}"
  instance_class = "db.r4.8xlarge"
  db_subnet_group_name = "fec_rds"
  publicly_accessible = true
  engine = "aurora-postgresql"
  engine_version = "10.7"
  apply_immediately = true
  count = 3
  identifier = "prod-aurora-inst-${count.index}"
}

resource "aws_rds_cluster" "staging-aurora-cluster" {
  cluster_identifier = "stage-aurora-cluster"
  database_name = "fec"
  master_username = "fec"
  master_password = "${var.rds_staging_password}"
  backup_retention_period = 7
  preferred_backup_window = "06:00-08:00"
  preferred_maintenance_window = "Sat:10:00-Sat:12:00"
  db_subnet_group_name = "fec_rds"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"] 
  storage_encrypted = true
  copy_tags_to_snapshot = true
  deletion_protection = true
  apply_immediately = true
  skip_final_snapshot = true
  engine = "aurora-postgresql"
  engine_version = "10.7"
}

resource "aws_rds_cluster_instance" "staging_aurora_inst" {
  cluster_identifier = "${aws_rds_cluster.staging-aurora-cluster.id}"
  instance_class = "db.r4.2xlarge"
  db_subnet_group_name = "fec_rds"
  publicly_accessible = true
  engine = "aurora-postgresql"
  engine_version = "10.7"
  apply_immediately = true
  count = 2
  identifier = "stage-aurora-inst-${count.index}"
}

resource "aws_rds_cluster" "development-aurora-cluster" {
  cluster_identifier = "dev-aurora-cluster"
  database_name = "fec"
  master_username = "fec"
  master_password = "${var.rds_development_password}"
  backup_retention_period = 7
  preferred_backup_window = "06:00-08:00"
  preferred_maintenance_window = "Sat:10:00-Sat:12:00"
  db_subnet_group_name = "fec_rds"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"] 
  storage_encrypted = true
  copy_tags_to_snapshot = true
  deletion_protection = true
  apply_immediately = true
  skip_final_snapshot = true
  engine = "aurora-postgresql"
  engine_version = "10.7"
}

resource "aws_rds_cluster_instance" "development_aurora_inst" {
  cluster_identifier = "${aws_rds_cluster.development-aurora-cluster.id}"
  instance_class = "db.r4.2xlarge"
  db_subnet_group_name = "fec_rds"
  publicly_accessible = true
  engine = "aurora-postgresql"
  engine_version = "10.7"
  apply_immediately = true
  count = 2
  identifier = "dev-aurora-inst-${count.index}"
}
