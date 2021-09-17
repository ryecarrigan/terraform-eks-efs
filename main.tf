data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_caller_identity" "current" {}
data "aws_eks_cluster_auth" "auth" {
  name = data.aws_eks_cluster.cluster.name
}

data "aws_region" "current" {}
data "helm_repository" "efs_csi" {
  name = "aws-efs-csi-driver"
  url  = "https://kubernetes-sigs.github.io/aws-efs-csi-driver"
}

data "helm_repository" "ebs_csi" {
  name = "aws-ebs-csi-driver"
  url = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
}

data "aws_subnet" "subnet" {
  for_each = var.subnet_ids
  id       = each.value
}

resource "aws_security_group" "efs" {
  description = "Security group for EFS mount targets"
  name        = "${var.cluster_name}-EFS"
  vpc_id      = local.vpc_id

  tags = var.extra_tags
}

resource "aws_security_group_rule" "efs_egress" {
  from_port                = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.efs.id
  source_security_group_id = var.node_security_group
  to_port                  = 2049
  type                     = "egress"
}

resource "aws_security_group_rule" "efs_ingress" {
  from_port                = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.efs.id
  source_security_group_id = var.node_security_group
  to_port                  = 2049
  type                     = "ingress"
}

resource "helm_release" "eks_efs_csi_driver" {
  chart      = "aws-efs-csi-driver/aws-efs-csi-driver"
  name       = local.app_name
  namespace  = local.kube_system
  repository = data.helm_repository.efs_csi.metadata[0].name

  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/eks/aws-efs-csi-driver"
  }
}

resource "helm_release" "eks_ebs_csi_driver" {
  chart      = "aws-ebs-csi-driver/aws-ebs-csi-driver"
  name       = "aws-ebs-csi-driver"
  namespace  = local.kube_system
  repository = data.helm_repository.ebs_csi.metadata[0].name

  set {
    name  = "enableVolumeSnapshot"
    value = "true"
  }

  set {
    name  = "controller.extraVolumeTags"
    value = jsonencode(var.extra_tags)
  }
}

resource "aws_efs_file_system" "efs_file_system" {
  tags = var.extra_tags
}

resource "aws_efs_mount_target" "efs_mount_target" {
  for_each        = var.subnet_ids
  file_system_id  = aws_efs_file_system.efs_file_system.id
  security_groups = [aws_security_group.efs.id]
  subnet_id       = each.value
}

resource "kubernetes_storage_class" "storage_class" {
  storage_provisioner = "efs.csi.aws.com"

  parameters = {
    directoryPerms   = "700"
    fileSystemId     = aws_efs_file_system.efs_file_system.id
    provisioningMode = "efs-ap"
  }

  metadata {
    name = var.storage_class_name
  }
}

resource "kubernetes_storage_class" "ebs_storage_class" {
  storage_provisioner = "ebs.csi.aws.com"
  parameters = {
    encrypted = true
    type      = "gp2"
  }

  metadata {
    name = "ebs-sc"
  }
}

resource "aws_iam_policy" "eks_efs_csi" {
  name   = "${var.cluster_name}-AmazonEKS_EFS_CSI_Driver_Policy"
  policy = file("${path.module}/efs-policy.json")
}

resource "aws_iam_policy" "eks_ebs_csi" {
  name   = "${var.cluster_name}-AmazonEKS_EBS_CSI_Driver_Policy"
  policy = file("${path.module}/ebs-policy.json")
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  for_each = var.node_role_ids

  policy_arn = aws_iam_policy.eks_efs_csi.arn
  role       = each.value
}

resource "aws_iam_role_policy_attachment" "ebs_policy_attachment" {
  for_each = var.node_role_ids

  policy_arn = aws_iam_policy.eks_ebs_csi.arn
  role       = each.value
}

locals {
  app_name    = "aws-efs-csi-driver"
  kube_system = "kube-system"

  # Parse the VPC ID from one of the provided subnets.
  vpc_id      = tolist([for net in data.aws_subnet.subnet : net.vpc_id])[0]
}
