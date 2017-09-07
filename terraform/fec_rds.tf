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
  backend "s3" {}
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

resource "aws_db_instance" "rds_production" {
  lifecycle {
    prevent_destroy = true
  }
  snapshot_identifier = "rds:tf-20170223214825431394805grs-2017-03-16-09-02"
  engine = "postgres"
  engine_version = "9.6.1"
  instance_class = "db.r3.2xlarge"
  allocated_storage = 2000
  name = "fec"
  username = "fec"
  password = "${var.rds_production_password}"
  db_subnet_group_name = "${aws_db_subnet_group.rds.name}"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"]
  backup_retention_period = 30
  publicly_accessible = true
  storage_encrypted = true
  multi_az = true
  auto_minor_version_upgrade = true
  storage_type = "io1"
  identifier = "fec-govcloud-prod"
  iops = 12000
  maintenance_window = "Sat:06:00-Sat:08:00"
  parameter_group_name = "${aws_db_parameter_group.fec_default.id}"
  monitoring_role_arn = "${aws_iam_role.rds_logs_role.arn}"
  monitoring_interval = 5
  apply_immediately = true
}

resource "aws_db_instance" "rds_production_replica_1" {
  replicate_source_db = "${aws_db_instance.rds_production.identifier}"
  instance_class = "db.r3.2xlarge"
  publicly_accessible = true
  storage_encrypted = true
  auto_minor_version_upgrade = true
  storage_type = "io1"
  identifier = "fec-govcloud-prod-replica-1"
  iops = 12000
  maintenance_window = "Sat:06:00-Sat:08:00"
  parameter_group_name = "${aws_db_parameter_group.fec_default.id}"
  monitoring_role_arn = "${aws_iam_role.rds_logs_role.arn}"
  monitoring_interval = 5
  apply_immediately = true
}

resource "aws_db_instance" "rds_production_replica_2" {
  replicate_source_db = "${aws_db_instance.rds_production.identifier}"
  instance_class = "db.r3.2xlarge"
  publicly_accessible = true
  storage_encrypted = true
  auto_minor_version_upgrade = true
  storage_type = "io1"
  identifier = "fec-govcloud-prod-replica-2"
  iops = 12000
  maintenance_window = "Sat:06:00-Sat:08:00"
  parameter_group_name = "${aws_db_parameter_group.fec_default.id}"
  monitoring_role_arn = "${aws_iam_role.rds_logs_role.arn}"
  monitoring_interval = 5
  apply_immediately = true
}

resource "aws_db_instance" "rds_staging" {
  lifecycle {
    prevent_destroy = true
  }
  snapshot_identifier = "pre-final-staging-magnetic-snapshot-03-17-2017"
  engine = "postgres"
  engine_version = "9.6.1"
  instance_class = "db.r3.2xlarge"
  allocated_storage = 2000
  name = "fec"
  username = "fec"
  password = "${var.rds_staging_password}"
  db_subnet_group_name = "${aws_db_subnet_group.rds.name}"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"]
  backup_retention_period = 30
  publicly_accessible = true
  storage_encrypted = true
  storage_type = "gp2"
  auto_minor_version_upgrade = true
  identifier = "fec-govcloud-stage"
  maintenance_window = "Sat:06:00-Sat:08:00"
  parameter_group_name = "${aws_db_parameter_group.fec_default.id}"
  monitoring_role_arn = "${aws_iam_role.rds_logs_role.arn}"
  monitoring_interval = 5
  apply_immediately = true
}

resource "aws_db_instance" "rds_development" {
  lifecycle {
    prevent_destroy = true
  }
  snapshot_identifier = "rds:tf-20170223214825431394805grs-2017-03-16-09-02"
  engine = "postgres"
  engine_version = "9.6.1"
  instance_class = "db.r3.2xlarge"
  allocated_storage = 2000
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
  parameter_group_name = "${aws_db_parameter_group.fec_default.id}"
  monitoring_role_arn = "${aws_iam_role.rds_logs_role.arn}"
  monitoring_interval = 5
  apply_immediately = true
}

resource "aws_db_instance" "rds_development_replica_1" {
  replicate_source_db = "${aws_db_instance.rds_development.identifier}"
  instance_class = "db.r3.2xlarge"
  publicly_accessible = true
  storage_encrypted = true
  storage_type = "gp2"
  auto_minor_version_upgrade = true
  identifier = "fec-govcloud-dev-replica-1"
  maintenance_window = "Sat:06:00-Sat:08:00"
  parameter_group_name = "${aws_db_parameter_group.fec_default.id}"
  monitoring_role_arn = "${aws_iam_role.rds_logs_role.arn}"
  monitoring_interval = 5
  apply_immediately = true
}

output "rds_production_url" { value = "${aws_db_instance.rds_production.endpoint}" }
output "rds_production_password" { value = "${aws_db_instance.rds_production.password}" }
output "rds_production_replica_1_url" { value = "${aws_db_instance.rds_production_replica_1.endpoint}" }

output "rds_staging_url" { value = "${aws_db_instance.rds_staging.endpoint}" }
output "rds_staging_password" { value = "${aws_db_instance.rds_staging.password}" }

output "rds_development_url" { value = "${aws_db_instance.rds_development.endpoint}" }
output "rds_development_password" { value = "${aws_db_instance.rds_development.password}" }
output "rds_development_replica_1_url" { value = "${aws_db_instance.rds_development_replica_1.endpoint}" }
