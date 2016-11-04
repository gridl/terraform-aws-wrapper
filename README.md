# terraform-aws-wrapper

*** WORK IN PROGRESS ***

Terraform+AWS wrapper script makes it easy to follow my opinionated set of best practices when it comes to manage primarily AWS infrastructure:

1. Well-formatted code by using pre-commit hook

2. Use Terragrunt to configure locking and remote states

3. Use recommended way to organize Terraform configurations for AWS infrastructures of almost any size (from single AWS account with few resources to largely distributed, multi-regional using several AWS accounts) 

3.1. Multiple AWS accounts with multiple layers - **draw diagram**

3.2. Single AWS account with multiple layers - **draw diagram**

Getting started
===============

Put `terraform.sh` into your project with Terraform configurations and make it executable.

Project structure
=================

For optimal use of terraform-aws-wrapper (aka `terraform.sh`) configurations of the infrastructure should be structured like this:
```
.
├── accounts
│   ├── company-dev
│   │   ├── global.tfvars
│   │   ├── service1.eu-west-1.tfvars
│   │   └── shared.eu-west-1.tfvars
│   └── company-prod
│       ├── global.tfvars
│       ├── service1.us-west-2.tfvars
│       └── shared.us-west-2.tfvars
├── layers
│   ├── company-dev
│   │   ├── global
│   │   │   └── *.tf
│   │   ├── service1
│   │   │   └── *.tf
│   │   └── shared
│   │       └── *.tf
│   └── company-prod
│       ├── global
│       │   └── *.tf
│       ├── service1
│       │   └── *.tf
│       └── shared
│           └── *.tf
├── modules
│   ├── global
│   │   └── *.tf
│   ├── shared
│   │   └── *.tf
│   └── typical_service
│       └── *.tf
├── common_variables.sh
└── terraform.sh
```

More details about proposed structure is [here](http://www.antonbabenko.com/2016/09/21/how-i-structure-terraform-configurations.html)

Usage
=====

There are several ways to use it. The basic one:

    ./terraform.sh [--account ...] [--region ...] [--layer ...] [--version ...] [command]

Example:
    
    ./terraform.sh --account company-dev --layer global --region eu-west-1 init
    ./terraform.sh company-dev eu-west-1 global init
or:

    TF_AWS_ACCOUNT_ALIAS=company-dev TF_AWS_REGION=eu-west-1 ./terraform.sh --layer global init
    
Changelog
=========

* 0.1 - initial release (wip)