###################################################################################################################################################################################################
###################################################################################################################################################################################################
###################################################################################################################################################################################################


# ____   ____            .__      ___.   .__                 
# \   \ /   /____ _______|__|____ \_ |__ |  |   ____   ______
#  \   Y   /\__  \\_  __ \  \__  \ | __ \|  | _/ __ \ /  ___/
#   \     /  / __ \|  | \/  |/ __ \| \_\ \  |_\  ___/ \___ \ 
#    \___/  (____  /__|  |__(____  /___  /____/\___  >____  >
#                \/              \/    \/          \/     \/ 


###################################################################################################################################################################################################
###################################################################################################################################################################################################
###################################################################################################################################################################################################


#######################################
####
#### Main Variables Creation
####
#######################################


variable "aws_credentials_path" {
  description = ".aws/credentials"
  default     = "~/.aws/credentials"
}

variable "aws_region" {
  description = "AWS Region"
}

variable "aws_profile" {
  description = "AWS SSO Profile - stored in .aws/config after aws configure sso"
}

variable "number_of_azs" {
  description = "Number of Availability Zones in each VPC"
  type        = number
  default     = 2
  validation {
    condition     = var.number_of_azs >= 2 && var.number_of_azs <= 3
    error_message = "Number of AZs must be between 2 and 3."
  }
}

variable "number_of_vpcs" {
  description = "Number of VPCs to Deploy"
  type        = number
  default     = 1
  validation {
    condition     = var.number_of_vpcs >= 1 && var.number_of_vpcs <= 9
    error_message = "Number of VPCs must be between 1 and 9."
  }
}

variable "project_name" {
  description = "The project name used for naming resources"
  type        = string
}

# Tags variable (no default)
variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
}

variable "deploy_aws_workloads" {
  type = bool
  description = "Deploy workloads in the AWS VPCs for testing connectivity and FQDN filtering."
  default = true
}

variable "enable_flow_logs" {
  type = bool
  description = "Enable VPC Flow Logs for all VPCs"
  default = false
}

