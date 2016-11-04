provider "aws" {
  region = "${var.aws_region}"
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
//
//data "terraform_remote_state" "shared" {
//  backend = "s3"
//
//  config {
//    bucket  = "${var.remote_states_bucket}"
//    region  = "${var.remote_states_region}"
//    key     = "${var.region}_shared"
//    encrypt = true
//  }
//}