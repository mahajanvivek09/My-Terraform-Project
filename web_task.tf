#setup provider
provider "aws" {
  region = "ap-south-1"
  profile = "webpro"
}

#setup key pair
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits = "2048"
}
resource "aws_key_pair" "key_pair" {
  key_name = "vivek_key144"
  public_key = tls_private_key.private_key.public_key_openssh
}

resource "local_file" "stored_key" {
  content = tls_private_key.private_key.private_key_pem
  filename = "key144.pem"
}

#setup security group
resource "aws_security_group" "securitygroup" {
  name = "security_to_allow_all"
  description = "allow HTTP_port_80 and SSH_port_22"

ingress {
  cidr_blocks = ["0.0.0.0/0"]
  from_port = 80
  to_port = 80
  protocol = "tcp"
}
  ingress {
  cidr_blocks = ["0.0.0.0/0"]
  from_port = 22
  to_port = 22
  protocol = "tcp"
}
  egress {
  cidr_blocks = ["0.0.0.0/0"]
  from_port = 0
  to_port = 0
  protocol = "-1"
}
  tags = {
    Name = "my_security_group"
  }
}

#creating variable for ami
variable "my_ami" {
  default = "ami-0447a12f28fddb066"
}


#launching an ec2 instance
resource "aws_instance" "myinstance" {
  ami = var.my_ami
  instance_type = "t2.micro"
  key_name = aws_key_pair.key_pair.key_name
  security_groups = ["${aws_security_group.securitygroup.name}"]

  #as soon as you launched, connect to this instance using ssh
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.private_key.private_key_pem
    host = aws_instance.myinstance.public_ip
  }
  #Run these commands on baseOS i.e; cloud instance/OS(remote), we use provisioner
  provisioner "remote-exec" {
    inline = [
              "sudo yum install httpd git sed -y",
              "sudo systemctl restart httpd",
              "sudo systemctl enable httpd",
    ]
  }
  tags = {
    Name = "My_Web_OS"
  }
}


#creating an ebs volume
resource "aws_ebs_volume" "myebs" {
  availability_zone = aws_instance.myinstance.availability_zone
  size = 1
  tags = {
    Name = "MyEBS_Volume"
  }
}


#attach the ebs volume to ec2 instance
resource "aws_volume_attachment" "ebs_ec2_attach" {
  device_name = "/dev/sdh"
  instance_id = aws_instance.myinstance.id
  volume_id = aws_ebs_volume.myebs.id
  force_detach = true
}

#download images from github
resource "null_resource" "null_git_images" {

  provisioner "local-exec" {
    command = "git clone https://github.com/mahajanvivek09/my_images.git myimages"
  }
}

#create s3 bucket
resource "aws_s3_bucket" "mybucket" {
  bucket = "percybucket09"
  acl = "public-read"
  force_destroy = true
}

#Providing accessing permissions
resource "aws_s3_bucket_public_access_block" "task1_s3_bucket" {

depends_on=[aws_s3_bucket.mybucket,]

  bucket = aws_s3_bucket.mybucket.id
  block_public_acls   = false
  block_public_policy = false
  ignore_public_acls = false
  restrict_public_buckets = false
}


#create bucket object
resource "aws_s3_bucket_object" "buckobj" {
  depends_on = [aws_s3_bucket.mybucket, null_resource.null_git_images]
  bucket = aws_s3_bucket.mybucket.bucket
  key = "chicken_biryani.jpg"
  source = "myimages/chicken_biryani.jpg"
}

#creating cloudfront distribution
resource "aws_cloudfront_distribution" "clouddist" {
  depends_on = [aws_s3_bucket.mybucket]
  enabled = true

  default_cache_behavior {
    allowed_methods = ["DELETE","GET","HEAD","OPTIONS","PATCH","POST","PUT"]
    cached_methods = ["GET","HEAD"]
    target_origin_id = aws_s3_bucket.mybucket.id

    viewer_protocol_policy = "allow-all"
    min_ttl = 0
    max_ttl = 86400
    default_ttl = 3600
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }
  origin {
    domain_name = aws_s3_bucket.mybucket.bucket_regional_domain_name
    origin_id = aws_s3_bucket.mybucket.id

    custom_origin_config {
      http_port = 80
      https_port = 443
      origin_protocol_policy = "match-viewer"
      origin_ssl_protocols = ["TLSv1","TLSv1.1","TLSv1.2"]
    }
  }
  #If there is 404 error, return index.html with a HTTP 200 response
  custom_error_response {
    error_code = 404
    error_caching_min_ttl = 3000
    response_code = 200
    response_page_path = "/chicken_biryani.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations = ["US","CA","GB","DE","IN"]
    }
  }

  #SSl certificate for the service
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "null_resource" "null_remote" {
  depends_on = [aws_volume_attachment.ebs_ec2_attach]

  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.private_key.private_key_pem
    host = aws_instance.myinstance.public_ip

  }
  provisioner "remote-exec" {
    inline = [
              "sudo mkfs.ext4  /dev/xvdh",
              "sudo mount /dev/xvdh  /var/www/html",
              "sudo rm -rf  /var/www/html/*",
              "sudo git clone https://github.com/mahajanvivek09/my_web_page.git  /var/www/html/",
              "sudo sed -i 's+myurl+https://${aws_cloudfront_distribution.clouddist.domain_name}/${aws_s3_bucket_object.buckobj.key}+g' /var/www/html/chicken_biryani.html",
              "sudo systemctl restart httpd",
      ]

  }
}


resource "null_resource" "null_chrome" {
depends_on = [
aws_cloudfront_distribution.clouddist,
]
provisioner "local-exec" {
command = "cd C:/Program Files (x86)/Google/Chrome/Application && chrome ${aws_instance.myinstance.public_ip}/chicken_biryani.html"
}
}

output "cloudfront_distribution_URL" {
  value = aws_cloudfront_distribution.clouddist.domain_name
}
output "instance_public_ip" {
  value = aws_instance.myinstance.public_ip
}






















