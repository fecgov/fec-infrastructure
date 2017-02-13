# fec-infrastructure

Terraform configuration and Concourse pipeline for managing custom FEC infrastructure in AWS.

## Setup
* Concourse pipeline is deployed to a concourse team owned by 18F Infrastructure
* Terraform configuration is deployed via Concourse to an AWS account owned by Infrastructure
* FEC staff are responsible for adding resources that incur a cost to Chandika

## Workflow
* FEC team member sends a pull request to 18F/fec-infrastructure
* If applicable, FEC team member sends updated Concourse credentials to infrastructure staff
* 18F Infrastructure team member reviews pull request to ensure that all resources are properly tagged
* After pull request is merged, updates are automatically deployed via Concourse
* If applicable, Infrastructure team member sends updated Terraform outputs to FEC staff
