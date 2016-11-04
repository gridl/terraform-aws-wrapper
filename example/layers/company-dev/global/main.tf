module "global" {
  source = "../../../modules/global"

  aws_region = "${var.aws_region}"
}
