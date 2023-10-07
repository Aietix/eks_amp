# eks_amp
Monitor your EKS cluster by Amazon Managed Service for Prometheus (AMP)  
This is a basic demonstration of how it functions, based on the following tutorial:
https://medium.com/@KimiHuang/monitor-your-eks-cluster-by-amazon-managed-service-for-prometheus-amp-f009ba149cab

Create workspace via AWS CLI
```aws amp create-workspace --region=eu-west-1 --alias amp_poc```



Now, let's perform some ClickOps. Open your AMP from the AWS console, copy the Helm configuration file, and paste it into the "amp_ingest_override_values.yaml" file.

Use "eksctl" to create/delete the EKS cluster.

Create:
```eksctl create cluster -f eks.yaml```

Delete:
```eksctl delete cluster --name=eks-poc --region=eu-west-1```


Execute the "zebra.sh" bash script.
```chmod +x zebra.sh```
```./zebra.sh```

Access Prometheus UI:
Let’s use port-forward command to forward amp-server traffic to localhost:3000.
```kubectl port-forward -n observability service/prometheus-for-amp-server 3000:80```

Using browser to visit http://localhost:3000/

If you're adding a Prometheus data source to Amazon Managed Grafana, be sure to use Sigv4 for authentication.

Potential Issues:

This script only creates the roles: "amp-ebs-csi-iam-role" and "amp-iamproxy-ingest-role". If you run the script again, these roles won't be updated. If you plan to start from scratch, please delete these roles manually. Failing to do so may result in your Prometheus PVC being stuck in a pending state.

If you're connecting AMP to AMG, ensure that Grafana operates within the same VPC.

When changing instance types, ensure that the chosen type meets Prometheus's system requirements.
