# fec-infrastructure

Terraform configuration and CircleCI for managing custom FEC infrastructure in AWS.

## Setup
* CircleCI is configured to deploy the master branch
* Terraform configuration is deployed via CircleCI to the FEC's AWS account

## Workflow
* FEC team member sends a pull request to fecgov/fec-infrastructure
* After pull request is merged, updates are automatically deployed via CircleCI
