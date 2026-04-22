terraform {
  backend "s3" {
    bucket         = "ecs-combined-tfstate-989346120260"
    key            = "staging/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "ecs-combined-tfstate-lock"
    encrypt        = true
  }
}