provider "aws" {
  region = "${var.region}"
}

//data "terraform_remote_state" "global" {
//  backend = "s3"
//
//  config {
//    bucket  = "${var.remote_states_bucket}"
//    region  = "${var.remote_states_region}"
//    key     = "global"
//    encrypt = true
//  }
//}

module "shared" {
  source = "../../../modules/shared"

  # ...
}
