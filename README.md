# terraform-aws-copilot

AWS Copilot を Terraform で再現してみる

以下の順番で実行していく

- terraform/app ディレクトリで terraform apply
- svc_rdws,svc_lbws,svc_bs,svc_ws,job_sjディレクトでdocker build & docker push
- terraform/env_dev ディレクトリで terraform apply
- terraform/env_dev_svcs ディレクトリで terraform apply

消すときは逆から順番に
