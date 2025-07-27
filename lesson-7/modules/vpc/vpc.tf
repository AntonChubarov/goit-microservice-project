resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  tags = {
    Name = var.vpc_name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "public" {
  for_each                = toset(var.public_subnets)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = var.availability_zones[index(var.public_subnets, each.value)]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.vpc_name}-public-${index(var.public_subnets, each.value)+1}"
  }
}

resource "aws_subnet" "private" {
  for_each          = toset(var.private_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = var.availability_zones[index(var.private_subnets, each.value)]
  tags = {
    Name = "${var.vpc_name}-private-${index(var.private_subnets, each.value)+1}"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = {
    Name = "${var.vpc_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.public_subnets[0]].id
  depends_on    = [aws_internet_gateway.this]
}
