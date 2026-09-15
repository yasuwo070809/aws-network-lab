# 費用と削除(クリーンアップ)

リージョン: `ap-northeast-1`。金額は2026年時点の東京リージョンのオンデマンド料金の目安であり、正確な請求額はAWS Billingで確認すること。

## Phase 1 apply(検証1〜4)で作成されるリソースと課金要素

| リソース | 課金の有無 | 目安 |
|---|---|---|
| VPC / Subnet / IGW / Route Table / NACL | 無料 | - |
| EC2 (`t3.micro` ×2) | **課金あり**(無料利用枠対象の可能性あり) | 無料利用枠(12ヶ月以内の対象アカウント)適用外の場合、t3.micro ×2 ×稼働時間で 約$0.0136/時 ×2 ≒ 月$20弱(常時起動した場合) |
| EBS (ルートボリューム、gp3 8GB ×2、デフォルト) | 課金あり | 約$0.0106/GB-月 ×8GB×2 ≒ 月$0.17程度 |
| Elastic IP(EC2にアタッチ中) | **アタッチ中は無料**。EC2停止中や未アタッチだと時間課金が発生 | アタッチ状態を維持する限り$0 |
| Security Group / IAM Role / Instance Profile | 無料 | - |
| CloudWatch Logs ロググループ(VPC Flow Logs) | 課金あり(取り込み+保存) | ラボ規模のトラフィックであれば月$1未満が目安 |
| VPC Flow Logs 本体 | 無料(送信先のCloudWatch Logs側で課金) | - |

**Phase 1 apply時点では、高額課金につながる構成(NAT Gateway等)は一切含まれない。**

## Phase 1 検証5(Session Manager)で追加が必要になる可能性のある構成

Private EC2はデフォルトでインターネット経路を持たない(NATなし)ため、SSM Agentがエンドポイントへ到達できず、Session Managerがそのままでは使えない。承認なしにNAT Gatewayを常設することはしない。選択肢は以下の3つで、**apply前に必ず選択と概算費用を提示し、承認を得てから作成する**:

| 選択肢 | 概算費用 | 備考 |
|---|---|---|
| ① SSM用VPCインターフェースエンドポイント3つ(ssm, ssmmessages, ec2messages)を`enable_ssm_vpc_endpoints=true`で作成 | 約$0.014/時 ×3エンドポイント ×AZ数(1)=約$0.042/時 ≒ 月$30程度(常時)+データ処理料($0.014/GB) | 本ラボが推奨する方式。検証終了後にfalseへ戻せば課金停止 |
| ② 一時的にPrivate EC2をPublicサブネットへ退避、または一時的にNAT Gatewayを作成 | NAT Gatewayは時間課金$0.062/時+データ処理$0.062/GBで**Phase1の想定を大きく超える**ため非推奨 | Phase 3で正式に扱う想定 |
| ③ Session Manager検証をスキップし、Phase 3以降へ先送り | $0 | 検証5のみ未実施として記録 |

## `terraform destroy` による削除方法

```powershell
cd aws-network-lab\terraform
terraform plan -destroy    # 削除対象を確認
terraform destroy          # 確認プロンプトで yes を入力して実行
```

- Elastic IPはEC2インスタンスごと削除されるため追加操作は不要。
- `enable_ssm_vpc_endpoints=true`にしていた場合、destroyで3つのエンドポイントも削除される(削除後は課金停止)。
- CloudWatch Logsのロググループもdestroy対象に含まれる(保持したい場合は事前にエクスポートすること)。
- destroy実行後、`aws ec2 describe-vpcs --filters "Name=tag:Project,Values=aws-network-lab"`などで残存リソースがないことを確認する。

**destroyもterraform applyと同様、実行前に対象を提示しユーザーの承認を得てから実行する。**
