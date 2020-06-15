provider "aws" {
  region  = "ap-south-1"
  profile = "root"
}

// create security_groups for the instance

resource "aws_security_group" "sec_grp" {
  name        = "sec_grp"
  description = "Allow req inbound traffic"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sec_grp"
  }
}

// create key_pair for code

//key_gen process
resource "tls_private_key" "key_pair" {
  algorithm   = "RSA"
}

// attach key to key_pair file to be created
resource "aws_key_pair" "task_1key" {
  depends_on = [aws_security_group.sec_grp,]

  key_name   = "task_1key"
  public_key = tls_private_key.key_pair.public_key_openssh
}

// save file to local dir
resource "local_file" "task_1key" {
  depends_on = [aws_key_pair.task_1key,]

  content = tls_private_key.key_pair.private_key_pem
  filename = "C:/Users/smc181002/Desktop/hybrid-cloud/pem-ppk-files/task_1key.pem"
}

output "key_gen" {
  value = tls_private_key.key_pair.private_key_pem
}


resource "aws_instance" "task_1os" {
  depends_on = [aws_security_group.sec_grp, aws_key_pair.task_1key,]

  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name      = "task_1key"
  security_groups = ["sec_grp"]
  tags = {
    Name = "task_1os"
  }
}

resource "null_resource" "install_soft"  {
  depends_on = [aws_instance.task_1os,local_file.task_1key,]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.key_pair.private_key_pem
    host        = aws_instance.task_1os.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd -y",
      "sudo yum install git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
}

resource "aws_ebs_volume" "ebs_task1" {
  availability_zone = aws_instance.task_1os.availability_zone
  size              = 1
  tags = {
    Name = "external"
  }
}

resource "aws_volume_attachment" "ebs_attach" {
  depends_on = [aws_ebs_volume.ebs_task1,]

  device_name  = "/dev/sdh"
  volume_id    = aws_ebs_volume.ebs_task1.id
  instance_id  = aws_instance.task_1os.id
  force_detach = true
}

resource "null_resource" "add_code"  {
  depends_on = [aws_instance.task_1os,local_file.task_1key,aws_volume_attachment.ebs_attach]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.key_pair.private_key_pem
    host        = aws_instance.task_1os.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/smc181002/test.git /var/www/html/",
    ]
  }
}

resource "aws_s3_bucket" "buckettask1"{
  bucket = "buckettask1"
  acl    = "public-read"

  versioning {
    enabled = true
  }

  tags = {
    Name = "terraform bucket task1"
  }
}



resource "null_resource" "download_images" {
  depends_on = [aws_s3_bucket.buckettask1,]

  provisioner "local-exec" {
    command = "git clone https://github.com/smc181002/test.git ./code/"
  }
}

resource "aws_s3_bucket_object" "frame2obj" {
  depends_on = [aws_s3_bucket.buckettask1, null_resource.download_images,]
  key    = "frame2.png"
  bucket = aws_s3_bucket.buckettask1.id
  source = "C:/Users/smc181002/Desktop/hybrid-cloud/terraform/project-1/code/frame2.png"
  // source = "C:/Users/smc181002/Desktop/figma/Frame 2.png"
  acl    = "public-read"
  content_type = "image/png"
}

// create cloud Front

resource "aws_cloudfront_distribution" "task1cf" {
  depends_on = [aws_s3_bucket.buckettask1, aws_s3_bucket_object.frame2obj, null_resource.download_images, ]

  origin {
    domain_name = aws_s3_bucket.buckettask1.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.buckettask1.id
  }

  enabled         = true
  is_ipv6_enabled = true

  default_cache_behavior {
    allowed_methods    = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.buckettask1.id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "null_resource" "edit_code"  {
  depends_on = [aws_instance.task_1os,local_file.task_1key,aws_volume_attachment.ebs_attach, aws_s3_bucket.buckettask1, aws_s3_bucket_object.frame2obj, aws_cloudfront_distribution.task1cf, ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.key_pair.private_key_pem
    host        = aws_instance.task_1os.public_ip
  }

  provisioner "remote-exec" {
    inline = ["sudo sed -i 's,Frame2.png,https://${aws_cloudfront_distribution.task1cf.domain_name}/frame2.png,g' /var/www/html/index.html", ]
  }
}

// open browser to check the output
resource "null_resource" "nulllocal1"  {
  depends_on = [aws_instance.task_1os,local_file.task_1key,aws_volume_attachment.ebs_attach, aws_s3_bucket.buckettask1, aws_s3_bucket_object.frame2obj, aws_cloudfront_distribution.task1cf, null_resource.edit_code, ]

  provisioner "local-exec" {
    command = "MicrosoftEdge.exe  ${aws_instance.task_1os.public_ip}"
  }
}