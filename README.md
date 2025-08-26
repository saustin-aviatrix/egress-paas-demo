# Aviatrix Egress PaaS Demo Environment

 This code will deploy 1 or more VPCs in AWS with 2 Linux workloads in different AZs running Gatus

 Before running, please note the following:

 1. Update the AWS Provider with your credentials information
 2. Update the tfvars file to your required inputs if you choose to use tfvars (see example tfvars file)
 3. You can modify the Gatus config in the test_servers_gatus.tftpl
 4. If you run without tfvars, you will be prompted for your AWS account name, controller ip and credentials
 5. If you want to run the security assessment, set the variable enable_flow_logs to true
 6. If enable_flow_logs is true, a S3 bucket will be setup and flow logs enabled for all the VPCs
 7. The code will output the loadbalancer URL for the 2 workloads. It's the same URL with port 80 and port 81


# This TF was modified from Pauls SP1 Demo
![Paul Aviatrix Template v2 - Page 10](https://github.com/user-attachments/assets/ad1ca413-cf3c-49bf-ae85-2444b0a7b575)
