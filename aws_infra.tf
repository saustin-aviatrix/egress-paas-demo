###################################################################################################################################################################################################
###################################################################################################################################################################################################
###################################################################################################################################################################################################


#   _____  __      __  _________ .___        _____                        __                        __                        
#  /  _  \/  \    /  \/   _____/ |   | _____/ ____\___________    _______/  |________ __ __   _____/  |_ __ _________   ____  
# /  /_\  \   \/\/   /\_____  \  |   |/    \   __\\_  __ \__  \  /  ___/\   __\_  __ \  |  \_/ ___\   __\  |  \_  __ \_/ __ \ 
#/    |    \        / /        \ |   |   |  \  |   |  | \// __ \_\___ \  |  |  |  | \/  |  /\  \___|  | |  |  /|  | \/\  ___/ 
#\____|__  /\__/\  / /_______  / |___|___|  /__|   |__|  (____  /____  > |__|  |__|  |____/  \___  >__| |____/ |__|    \___  >
#        \/      \/          \/           \/                  \/     \/                          \/                        \/ 


###################################################################################################################################################################################################
###################################################################################################################################################################################################
###################################################################################################################################################################################################


#######################################
####
#### Define Locals
####
#######################################

locals {
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  
  # Create a map of subnet indices to VPC and AZ indices
  subnet_map = {
    for i in range(var.number_of_vpcs * var.number_of_azs) : i => {
      vpc_index = floor(i / var.number_of_azs)
      az_index  = i % var.number_of_azs
    }
  }
}



#######################################
####
#### VPC Creation
####
#######################################


# Create the VPC
resource "aws_vpc" "default" {
  count      = var.number_of_vpcs
  cidr_block = "10.${100 + count.index}.0.0/21"

  tags = {
    Name = "${var.project_name}-${count.index + 1}"
  }
}



###################################################################################################################################################################################################

#######################################
####
#### IGW Creation
####
#######################################




# Create the internet gateway
resource "aws_internet_gateway" "default" {
  count  = var.number_of_vpcs
  vpc_id = aws_vpc.default[count.index].id

  tags = {
    Name = "${var.project_name}-${count.index + 1}"
  }
}



###################################################################################################################################################################################################


#######################################
####
#### SUBNETS Creation
####
#######################################


# Create the public subnets for all VPCs
resource "aws_subnet" "public" {
  count = var.number_of_vpcs * var.number_of_azs
  
  cidr_block        = cidrsubnet(aws_vpc.default[local.subnet_map[count.index].vpc_index].cidr_block, 4, local.subnet_map[count.index].az_index)
  vpc_id            = aws_vpc.default[local.subnet_map[count.index].vpc_index].id
  availability_zone = local.availability_zones[local.subnet_map[count.index].az_index]
  
  tags = merge(var.tags, {
    Name        = "${var.project_name}-${local.subnet_map[count.index].vpc_index + 1}-public-${local.availability_zones[local.subnet_map[count.index].az_index]}"
    Subnet-Type = "Public"
  })
}

# Create the private subnets for all VPCs
resource "aws_subnet" "private" {
  count = var.number_of_vpcs * var.number_of_azs
  
  # Start private subnets at 10.100.10.0/24 (subnet index 10)
  cidr_block        = cidrsubnet(aws_vpc.default[local.subnet_map[count.index].vpc_index].cidr_block, 4, local.subnet_map[count.index].az_index + 10)
  vpc_id            = aws_vpc.default[local.subnet_map[count.index].vpc_index].id
  availability_zone = local.availability_zones[local.subnet_map[count.index].az_index]

  tags = merge(var.tags, {
    Name        = "s${var.project_name}-${local.subnet_map[count.index].vpc_index + 1}-private-${local.availability_zones[local.subnet_map[count.index].az_index]}"
    Subnet-Type = "Private"
  })
}



###################################################################################################################################################################################################

#######################################
####
####  NAT GW Creation
####
#######################################


# Create the EIPs for the NAT gateways (one per AZ per VPC)
resource "aws_eip" "natgws" {
  count  = var.number_of_vpcs * var.number_of_azs
  domain = "vpc"
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${floor(count.index / var.number_of_azs) + 1}-natgw-eip-${local.availability_zones[count.index % var.number_of_azs]}"
  })
}

# Create the NAT gateways for all VPCs
resource "aws_nat_gateway" "default" {
  count = var.number_of_vpcs * var.number_of_azs

  allocation_id = aws_eip.natgws[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${floor(count.index / var.number_of_azs) + 1}-natgw-${local.availability_zones[count.index % var.number_of_azs]}"
  })
}



###################################################################################################################################################################################################

#######################################
####
#### RT Creation
####
#######################################



# Create the public route tables for all VPCs
resource "aws_route_table" "public" {
  count  = var.number_of_vpcs * var.number_of_azs
  vpc_id = aws_vpc.default[floor(count.index / var.number_of_azs)].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default[floor(count.index / var.number_of_azs)].id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${floor(count.index / var.number_of_azs) + 1}-public-rt-${local.availability_zones[count.index % var.number_of_azs]}"
  })

  lifecycle {
    ignore_changes = [route]
  }
}

# Create the private route tables for all VPCs
resource "aws_route_table" "private" {
  count  = var.number_of_vpcs * var.number_of_azs
  vpc_id = aws_vpc.default[floor(count.index / var.number_of_azs)].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.default[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${floor(count.index / var.number_of_azs) + 1}-private-rt-${local.availability_zones[count.index % var.number_of_azs]}"
  })

  lifecycle {
    ignore_changes = [route]
  }
}

# Associate the public subnets with the public route tables
resource "aws_route_table_association" "public" {
  count = var.number_of_vpcs * var.number_of_azs

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[count.index].id
}

# Associate the private subnets with the private route tables
resource "aws_route_table_association" "private" {
  count = var.number_of_vpcs * var.number_of_azs

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}


#########
####  S3 Bucket for Flow Logs - controlled by enable_flow_logs variable
########

# S3 bucket for storing VPC flow logs
resource "aws_s3_bucket" "vpc_flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = "${var.project_name}-vpc-flow-logs-${random_id.bucket_suffix[0].hex}"
  force_destroy = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc-flow-logs"
  })
}

resource "random_id" "bucket_suffix" {
  count  = var.enable_flow_logs ? 1 : 0
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "vpc_flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.vpc_flow_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vpc_flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.vpc_flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "vpc_flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.vpc_flow_logs[0].id

  rule {
    id     = "flow_logs_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""  # Apply to all objects in the bucket
    }

    expiration {
      days = 90  # Adjust retention as needed
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vpc_flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.vpc_flow_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for VPC Flow Logs to write to S3
resource "aws_iam_role" "flow_logs_role" {
  count  = var.enable_flow_logs ? 1 : 0
  name = "${var.project_name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "vpc_flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  bucket = aws_s3_bucket.vpc_flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.vpc_flow_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.vpc_flow_logs[0].arn
      }
    ]
  })
}

output "vpc_flow_logs_s3_url" {
  description = "S3 URL for VPC flow logs bucket"
  value       = var.enable_flow_logs ? "s3://${aws_s3_bucket.vpc_flow_logs[0].id}" : null
}

# VPC Flow Logs for each VPC
resource "aws_flow_log" "vpc_flow_logs" {
  count           = var.enable_flow_logs ? var.number_of_vpcs : 0
  log_destination = aws_s3_bucket.vpc_flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.default[count.index].id

  log_destination_type = "s3"

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc-${count.index + 1}-flow-logs"
  })
}



