###################################################################################################################################################################################################
###################################################################################################################################################################################################
###################################################################################################################################################################################################


#    _____  __      __  _________  __      __             __   .__                    .___      
#   /  _  \/  \    /  \/   _____/ /  \    /  \___________|  | _|  |   _________     __| _/______
#  /  /_\  \   \/\/   /\_____  \  \   \/\/   /  _ \_  __ \  |/ /  |  /  _ \__  \   / __ |/  ___/
# /    |    \        / /        \  \        (  <_> )  | \/    <|  |_(  <_> ) __ \_/ /_/ |\___ \ 
# \____|__  /\__/\  / /_______  /   \__/\  / \____/|__|  |__|_ \____/\____(____  /\____ /____  >
#         \/      \/          \/         \/                   \/               \/      \/    \/ 


###################################################################################################################################################################################################
###################################################################################################################################################################################################
###################################################################################################################################################################################################


locals {
  reduce_length_for_suffix = [
    for i in range(var.number_of_vpcs * var.number_of_azs) :
    "${floor(i / var.number_of_azs) + 1}-${local.availability_zones[i % var.number_of_azs]}"
  ]
}


#######################################
####
#### SSH Key Creation
####
#######################################

module "key_pair" {
  count  = var.deploy_aws_workloads ? 1 : 0
  source = "terraform-aws-modules/key-pair/aws"

  key_name           = "${var.project_name}-${random_string.name.result}"
  create_private_key = true
}



###################################################################################################################################################################################################

#######################################
####
#### SG Creation
####
#######################################



resource "aws_security_group" "allow_all_rfc1918" {
  count       = var.number_of_vpcs
  name        = "${var.project_name}-allow-all-rfc1918-vpc${count.index + 1}"
  description = "Allow all RFC1918 traffic for VPC${count.index + 1}"
  vpc_id      = aws_vpc.default[count.index].id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-allow-all-rfc1918-vpc${count.index + 1}"
    Type = "Security-Group"
    Purpose = "RFC1918-Internal"
  })
}



resource "aws_security_group" "allow_web_public" {
  count       = var.number_of_vpcs
  name        = "${var.project_name}-allow-web-public-vpc${count.index + 1}"
  description = "Allow web and SSH from public internet for VPC${count.index + 1}"
  vpc_id      = aws_vpc.default[count.index].id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 83
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-allow-web-public-vpc${count.index + 1}"
    Type = "Security-Group"
    Purpose = "Public-Access"
  })
}





###################################################################################################################################################################################################

#######################################
####
#### AMI Definition
####
#######################################


data "aws_ami" "amazon-linux-2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
}



###################################################################################################################################################################################################

#######################################
####
#### Workload Creation
####
#######################################



## Wait for NAT GW's to be ready before deploying private workloads
resource "time_sleep" "egress_ready" {
  count      = var.number_of_vpcs
  depends_on = [aws_nat_gateway.default]

  create_duration = "90s"
}

## Deploy Linux Test Hosts in all VPCs, All AZs running Gatus for connectivity testing
module "ec2_instance" {
  count  = var.deploy_aws_workloads ? var.number_of_vpcs * var.number_of_azs : 0
  source = "terraform-aws-modules/ec2-instance/aws"

  ami                         = data.aws_ami.amazon-linux-2.image_id
  instance_type               = "t3a.micro"
  key_name                    = module.key_pair[0].key_pair_name
  monitoring                  = true
  vpc_security_group_ids      = [aws_security_group.allow_all_rfc1918[floor(count.index / var.number_of_azs)].id]
  subnet_id                   = aws_subnet.private[count.index].id
  user_data                   = templatefile("${path.module}/test_servers_gatus.tftpl", { 
    az = "${local.availability_zones[count.index % var.number_of_azs]}"
    vpc = "${floor(count.index / var.number_of_azs) + 1}"
  })
  user_data_replace_on_change = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-workload-vpc${local.reduce_length_for_suffix[count.index]}"
    Type = "EC2-Instance"
    OS = "Linux"
    Purpose = "Test-Workload"
    VPC = "vpc${floor(count.index / var.number_of_azs) + 1}"
    AZ = "${local.availability_zones[count.index % var.number_of_azs]}"
  })

  depends_on = [
    aws_route_table_association.private,
    time_sleep.egress_ready
  ]
}


###################################################################################################################################################################################################

#######################################
####
#### ELB Creation
####
#######################################


# Deploy an ELB for each VPC to enable public access to web portal on the test Linux servers
resource "aws_lb" "test-machine-ingress" {
  count              = var.deploy_aws_workloads ? var.number_of_vpcs : 0
  name               = "${var.project_name}-alb-vpc${count.index + 1}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_web_public[count.index].id]
  subnets            = [for i in range(var.number_of_azs) : aws_subnet.public[count.index * var.number_of_azs + i].id]

  tags = merge(var.tags, {
    Name = "${var.project_name}-alb-vpc${count.index + 1}"
    Type = "Application-Load-Balancer"
    VPC = "vpc${count.index + 1}"
  })
}

resource "aws_lb_listener" "test-machine-ingress" {
  count             = var.deploy_aws_workloads ? var.number_of_vpcs * var.number_of_azs : 0
  load_balancer_arn = aws_lb.test-machine-ingress[floor(count.index / var.number_of_azs)].arn
  port              = "8${count.index % var.number_of_azs}"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test-machine-ingress[count.index].arn
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-listener-vpc${floor(count.index / var.number_of_azs) + 1}-port-8${count.index % var.number_of_azs}"
    Type = "ALB-Listener"
  })
}

resource "aws_lb_target_group" "test-machine-ingress" {
  count       = var.deploy_aws_workloads ? var.number_of_vpcs * var.number_of_azs : 0
  name_prefix        = "tg-"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.default[floor(count.index / var.number_of_azs)].id
  
  health_check {
    path                = "/"
    port                = 80
    healthy_threshold   = 6
    unhealthy_threshold = 2
    timeout             = 2
    interval            = 5
    matcher             = "200,302"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-tg-vpc${local.reduce_length_for_suffix[count.index]}"
    Type = "Target-Group"
    VPC = "vpc${floor(count.index / var.number_of_azs) + 1}"
    AZ = "${local.availability_zones[count.index % var.number_of_azs]}"
  })
}

resource "aws_lb_target_group_attachment" "test-machine-ingress" {
  count            = var.deploy_aws_workloads ? var.number_of_vpcs * var.number_of_azs : 0
  target_group_arn = aws_lb_target_group.test-machine-ingress[count.index].arn
  target_id        = module.ec2_instance[count.index].private_ip
  port             = 80
}

# Dynamic outputs for all VPCs and ports
output "lb_dns_names" {
  value = var.deploy_aws_workloads ? {
    for i in range(var.number_of_vpcs) : "vpc${i + 1}" => {
      for j in range(var.number_of_azs) : "port_8${j}" => "http://${aws_lb.test-machine-ingress[i].dns_name}:8${j}/"
    }
  } : {}
  description = "Load balancer DNS names and ports for all VPCs"
}