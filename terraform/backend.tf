# bucket comes from ../bootstrap. using s3 native locking
terraform {
  backend "s3" {
    bucket       = "sentinel-tfstate-juani-721500739616"
    key          = "sentinel-split-architecture/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
