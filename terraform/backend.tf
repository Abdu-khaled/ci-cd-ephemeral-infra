terraform {
  required_version = "~> 4.18.0"
  backend "s3" {
    bucket         	   = "cicd-tfstate-infra"
    key                = "cicd/terraform.tfstate"
    region         	   = "eu-central-1"
    dynamodb_table     = "tf-locks"
    encrypt        	   = true
  }
}