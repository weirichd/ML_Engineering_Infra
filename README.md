# ML Engineering Infra

This repo is responsible for defining the deployment for the machine learning engineering course.

* MLFlow tracking server
* Feast feature store

## Getting Started

To use

1. In AWS, create a github deployment identity and role.
2. Assign the role ARN to the secret `AWS_DEPLOY_ROLE_ARN` in Github secrets for this repo.
