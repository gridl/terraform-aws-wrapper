module "service1" {
  source  = "../../../modules/typical_service"

  service = "${lookup(var.parameters, "service")}"
  version = "${var.layer_version}"
}
