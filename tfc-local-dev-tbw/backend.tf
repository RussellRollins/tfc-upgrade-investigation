terraform {
  backend "remote" {}
  required_providers {
    random = {
      source = "hashicorp/random"
    }
  }
}
