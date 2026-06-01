#!/usr/bin/env python3
"""Generate the architecture diagram with official AWS icons.

Usage:
    pip install diagrams   # requires graphviz on PATH
    python3 docs/generate_diagram.py

Outputs docs/architecture.png
"""
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import (
    VPC, InternetGateway, NATGateway, PublicSubnet, PrivateSubnet,
    ELB, Route53, RouteTable,
)
from diagrams.aws.compute import EC2, EC2AutoScaling
from diagrams.aws.security import IAMRole, SecretsManager
from diagrams.aws.management import Cloudwatch
from diagrams.aws.storage import S3
from diagrams.onprem.client import Users
from diagrams.onprem.container import Docker

graph_attr = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.6",
    "splines": "spline",
}

with Diagram(
    "Docker Swarm on AWS",
    filename="docs/architecture",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    users = Users("Users / Clients")
    dns = Route53("Route 53\n(swarm.example.com)")

    with Cluster("AWS Region: us-east-1"):
        with Cluster("VPC 10.0.0.0/16"):
            igw = InternetGateway("Internet Gateway")
            secrets = SecretsManager("Secrets Manager\n(swarm join tokens)")
            logs = Cloudwatch("CloudWatch Logs\n+ ASG alarms")

            with Cluster("Public Subnets (x2 AZ)"):
                alb = ELB("Application\nLoad Balancer")
                nat = NATGateway("NAT Gateway")
                with Cluster("Swarm Managers (3)"):
                    managers = [
                        Docker("manager-1"),
                        Docker("manager-2"),
                        Docker("manager-3"),
                    ]

            with Cluster("Private Subnets (x2 AZ)"):
                with Cluster("Worker Auto Scaling Group (2-10)"):
                    workers = EC2AutoScaling("Worker nodes")

            iam = IAMRole("IAM Roles\n(manager / worker\ninstance profiles)")
            alb_logs = S3("S3\n(ALB access logs)")

    # Traffic flow
    users >> Edge(label="HTTPS/HTTP") >> dns >> alb
    igw >> alb
    alb >> Edge(label="app traffic\n(target group)") >> workers

    # Swarm control plane
    managers[0] - Edge(style="dashed", label="raft") - managers[1]
    managers[1] - Edge(style="dashed") - managers[2]
    workers >> Edge(style="dotted", label="join swarm") >> managers[0]

    # Outbound + supporting services
    workers >> Edge(label="egress") >> nat >> igw
    managers[0] >> secrets
    workers >> Edge(style="dotted") >> secrets
    managers[0] >> iam
    workers >> Edge(style="dotted") >> iam
    workers >> logs
    alb >> Edge(style="dotted", label="logs") >> alb_logs
