resource "random_pet" "dog" {}

module "m" {
  source = "./m"
}
