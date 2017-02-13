variable "region" { default = "us-gov-west-1" }
variable "rds_az1" { default = "us-gov-west-1a" }
variable "rds_az2" { default = "us-gov-west-1b" }
variable "rds_vpc_id" {}
variable "rds_cidr_block_az1" {}
variable "rds_cidr_block_az2" {}
variable "rds_production_username" {}
variable "rds_production_password" {}
variable "rds_staging_username" {}
variable "rds_staging_password" {}
variable "rds_development_username" {}
variable "rds_development_password" {}

provider "aws" {
  region = "${var.region}"
}

resource "aws_subnet" "rds_az1" {
  vpc_id = "${var.rds_vpc_id}"
  cidr_block = "${var.rds_cidr_block_az1}"
  availability_zone = "${var.rds_az1}"
  tags {
    Name = ""
  }
}

resource "aws_subnet" "rds_az2" {
  vpc_id = "${var.rds_vpc_id}"
  cidr_block = "${var.rds_cidr_block_az2}"
  availability_zone = "${var.rds_az2}"
  tags {
    Name = ""
  }
}

resource "aws_db_subnet_group" "rds" {
  name = "fec_rds"
  subnet_ids = ["${aws_subnet.rds_az1.id}", "${aws_subnet.rds_az2.id}"]
  tags {
    Name = ""
  }
}

/* TODO: Lock down ingress rules */
resource "aws_security_group" "rds" {
  name = "fec_rds"

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

resource "aws_db_instance" "rds_production" {
  lifecycle {
    prevent_destroy = true
  }
  engine = "postgres"
  engine_version = "9.6.1"
  instance_class = "db.t2.micro"
  allocated_storage = 10
  name = "fec_production"
  username = "${var.rds_production_username}"
  password = "${var.rds_production_password}"
  db_subnet_group_name = "${aws_db_subnet_group.rds.name}"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"]
  publicly_accessible = true
  storage_encrypted = true
  multi_az = true
  tags {
    Name = ""
  }
}

resource "aws_db_instance" "rds_production_replica_1" {
  replicate_source_db = "${aws_db_instance.rds_production.identifier}"
  instance_class = "db.t2.micro"
  tags {
    Name = ""
  }
}

resource "aws_db_instance" "rds_staging" {
  lifecycle {
    prevent_destroy = true
  }
  engine = "postgres"
  engine_version = "9.6.1"
  instance_class = "db.t2.micro"
  allocated_storage = 10
  name = "fec_staging"
  username = "${var.rds_staging_username}"
  password = "${var.rds_staging_password}"
  db_subnet_group_name = "${aws_db_subnet_group.rds.name}"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"]
  publicly_accessible = true
  storage_encrypted = true
  tags {
    Name = ""
  }
}

resource "aws_db_instance" "rds_development" {
  lifecycle {
    prevent_destroy = true
  }
  engine = "postgres"
  engine_version = "9.6.1"
  instance_class = "db.t2.micro"
  allocated_storage = 10
  name = "fec_development"
  username = "${var.rds_development_username}"
  password = "${var.rds_development_password}"
  db_subnet_group_name = "${aws_db_subnet_group.rds.name}"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"]
  publicly_accessible = true
  storage_encrypted = true
  tags {
    Name = ""
  }
}

output "rds_production_url" { value = "${aws_db_instance.rds_production.endpoint}" }
output "rds_production_username" { value = "${aws_db_instance.rds_production.username}" }
output "rds_production_password" { value = "${aws_db_instance.rds_production.password}" }
output "rds_production_replica_1_url" { value = "${aws_db_instance.rds_production_replica_1.endpoint}" }

output "rds_staging_url" { value = "${aws_db_instance.rds_staging.endpoint}" }
output "rds_staging_username" { value = "${aws_db_instance.rds_staging.username}" }
output "rds_staging_password" { value = "${aws_db_instance.rds_staging.password}" }

output "rds_development_url" { value = "${aws_db_instance.rds_development.endpoint}" }
output "rds_development_username" { value = "${aws_db_instance.rds_development.username}" }
output "rds_development_password" { value = "${aws_db_instance.rds_development.password}" }
