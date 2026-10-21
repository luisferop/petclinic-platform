terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-195421724327"
    key            = "petclinic/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
