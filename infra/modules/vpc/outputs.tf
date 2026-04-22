output "vpc_id"               { value = aws_vpc.main.id }
output "vpc_cidr"             { value = aws_vpc.main.cidr_block }
output "public_subnet_ids"    { value = aws_subnet.public[*].id }
output "private_subnet_ids"   { value = aws_subnet.private[*].id }
output "private_subnet_cidrs" { value = aws_subnet.private[*].cidr_block }
output "vpc_endpoint_sg_id"   { value = aws_security_group.vpc_endpoints.id }