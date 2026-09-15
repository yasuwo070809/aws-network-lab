# AWSリソースインベントリ

## 現在の実リソース状態(読み取り専用で確認、2026-09-16時点)

```
aws resourcegroupstaggingapi get-resources --tag-filters "Key=Project,Values=aws-network-lab"
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=aws-network-lab"
aws ec2 describe-instances --instance-ids <public-id> <private-id>
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids <vpce-id...>
```

**結果: AWS上に稼働中のリソースは存在しない。**

- `describe-vpcs` (tag filter) → 0件
- `describe-instances` → 両EC2とも `terminated`
- `describe-vpc-endpoints` → `InvalidVpcEndpointId.NotFound`(3件とも)
- `describe-volumes` → `InvalidVolume.NotFound`
- Resource Groups Tagging APIには削除直後は数分の反映遅延があり、削除済みリソースのARNが一時的に残ることを確認済み(本インベントリは上記の個別`describe-*`による直接確認を正としている)

`terraform/terraform.tfstate`(ローカル、gitignore対象)も `resources: []` (0件) であることを確認済み。

以降の表は、**2026-09-16のPhase 1検証実施時点で実際にデプロイされていた構成の記録**であり、現在のAWS上の状態ではない。再現するには `terraform apply` が必要。値はすべて `terraform apply`/`terraform state show`/AWS CLIの実出力から転記しており、AWSアカウントIDは含めていない。

## VPC

| 項目 | 値 |
|---|---|
| VPC ID | `vpc-046710bdced6fcf2b` |
| CIDR | `10.10.0.0/16` |
| DNS support | 有効 (`enable_dns_support=true`) |
| DNS hostnames | 有効 (`enable_dns_hostnames=true`) |

## Subnet

| 項目 | Public | Private |
|---|---|---|
| Subnet ID | `subnet-0ee150cca5ebf1b98` | `subnet-0fba248ba26c45923` |
| CIDR | `10.10.1.0/24` | `10.10.11.0/24` |
| AZ | `ap-northeast-1a` | `ap-northeast-1a` |
| Public IP自動割当 | 無効 (`map_public_ip_on_launch=false`、到達性はEIPのみに一本化) | 無効 |

## Route Table

| 項目 | Public | Private |
|---|---|---|
| Route Table ID | `rtb-0a850fc50b9962a40` | `rtb-068197df5e38dec52` |
| 関連付けSubnet | `subnet-0ee150cca5ebf1b98` | `subnet-0fba248ba26c45923` |
| ルート | `10.10.0.0/16 → local`, `0.0.0.0/0 → igw-01cd2518501843ce0` | `10.10.0.0/16 → local` のみ(NATなし、意図的) |

## Internet Gateway

| 項目 | 値 |
|---|---|
| IGW ID | `igw-01cd2518501843ce0` |
| 接続VPC | `vpc-046710bdced6fcf2b` |

## Elastic IP

| 項目 | 値 |
|---|---|
| Public IP | `16.76.139.218`(検証当時。再デプロイ時は別IPが払い出される) |
| Allocation ID | `eipalloc-0dd4f6705c913fa4c` |
| 関連付け先 | Public EC2 (`i-0a5838639674bf494`) |

## EC2 Instances

| 項目 | Public EC2 | Private EC2 |
|---|---|---|
| Instance ID | `i-0a5838639674bf494` | `i-0e2ea7846d0f11353` |
| Name | `aws-network-lab-public-ec2` | `aws-network-lab-private-ec2` |
| AMI | Amazon Linux 2023 最新(SSMパラメータ `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64` から解決。具体的なAMI IDは記録していない = 再デプロイ時に自動で最新版に解決される) |同左 |
| Instance Type | `t3.micro` | `t3.micro` |
| Private IP | `10.10.1.234` | `10.10.11.63` |
| Public IP | `16.76.139.218` (EIP) | なし(設計通り) |
| 状態(検証当時) | `running` | `running` |
| 状態(現在) | `terminated` | `terminated` |

## Security Group

| 項目 | Public SG | Private SG | VPCエンドポイント用SG |
|---|---|---|---|
| SG ID | `sg-07fddc86c8475f82e` | `sg-042535f996c24cc3f` | `sg-04814c6f58cad89b6` |
| Inbound | tcp/22 from `16.76.33.91/32`(管理者IP)、tcp/80 from `0.0.0.0/0` | tcp/22 from Public SG(`sg-07fddc86c8475f82e`) | tcp/443 from Private SG(`sg-042535f996c24cc3f`) |
| Outbound | all (`0.0.0.0/0`) | all (`0.0.0.0/0`) | all (`0.0.0.0/0`) |

## Network ACL

| 項目 | Public NACL | Private NACL |
|---|---|---|
| NACL ID | `acl-02b4030a0bd26574d` | `acl-0785a1ddfbc95c9e7` |
| 関連Subnet | `subnet-0ee150cca5ebf1b98` | `subnet-0fba248ba26c45923` |
| Inbound(既定) | rule 100: allow -1 `0.0.0.0/0`、rule 32767: deny -1(暗黙) | 同左 |
| Outbound(既定) | rule 100: allow -1 `0.0.0.0/0`、rule 32767: deny -1(暗黙) | 同左 |

障害試験中に追加した一時ルール(rule 90、エフェメラルポート拒否)は試験後に削除済み。恒久的なTerraform管理対象ではない。

## IAM

| 項目 | 値 |
|---|---|
| EC2用 Role | `aws-network-lab-ec2-ssm-role` |
| Instance Profile | `aws-network-lab-ec2-ssm-profile` |
| アタッチポリシー | `AmazonSSMManagedInstanceCore`(AWS管理ポリシー) |
| アタッチ先 | Public EC2・Private EC2の両方 |
| Flow Logs用 Role | `aws-network-lab-flow-logs-role`(CloudWatch Logsへの書き込み権限のみのインラインポリシー) |

## VPC Endpoint(検証5で承認の上追加作成)

| 項目 | ssm | ec2messages | ssmmessages |
|---|---|---|---|
| Endpoint ID | `vpce-0112885140e7542b2` | `vpce-08973e329198c0476` | `vpce-0969593b03edfc15f` |
| サービス名 | `com.amazonaws.ap-northeast-1.ssm` | `com.amazonaws.ap-northeast-1.ec2messages` | `com.amazonaws.ap-northeast-1.ssmmessages` |
| Type | Interface | Interface | Interface |
| Subnet | `subnet-0fba248ba26c45923`(private) | 同左 | 同左 |
| Security Group | `sg-04814c6f58cad89b6` | 同左 | 同左 |
| Private DNS | 有効 | 有効 | 有効 |
| 状態(現在) | 削除済み(`NotFound`) | 削除済み | 削除済み |

## VPC Flow Logs / CloudWatch Logs

| 項目 | 値 |
|---|---|
| Flow Log ID | `fl-0601337cb2e21ff1c`(検証当時。現在は削除済み) |
| 送信先 | CloudWatch Logs |
| Traffic Type | `ALL`(ACCEPT/REJECT両方) |
| Max aggregation interval | 60秒 |
| CloudWatch Log Group名 | `/aws-network-lab/aws-network-lab/vpc-flow-logs` |
| 保持期間 | 14日間(`flow_logs_retention_days`変数、既定値) |

## Key Pair

| 項目 | 値 |
|---|---|
| Key Pair名 | `aws-network-lab-key` |
| 登録内容 | 公開鍵のみ(`~/.ssh/aws-network-lab.pub`)。秘密鍵はAWSにもGitにも存在しない |
