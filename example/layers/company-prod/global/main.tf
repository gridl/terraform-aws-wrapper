provider "aws" {
  region = "${var.region}"
}

module "global" {
  source = "../../../modules/global"

  # ...
}
