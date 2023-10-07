# eks_amp
Amazon Managed Service for Prometheus 

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
