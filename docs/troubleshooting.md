# トラブルシューティング

本ラボで実施した3種類の障害注入試験(`scripts/inject-*-failure.sh`)の実測結果に基づく、症状・切り分け方法・復旧方法のまとめ。実際のcurl/Flow Logs出力は `evidence/02-security-group/`, `evidence/03-nacl/`, `evidence/06-flow-logs/` を参照。

## 共通の観察: ルール変更の反映には数秒〜十数秒の遅延がある

SG・NACL・ルートテーブルのいずれも、AWS APIが成功を返した直後の1回目のcurlでは変更前の状態(HTTP 200)が返ることが3試験すべてで再現された。実際に遮断が反映されるまで約10〜20秒程度のラグがあった(初回リトライで遮断を確認できたケースが多い)。**障害試験の直後に1回だけ確認して「変化なし」と判断しないこと** - 数回リトライして安定した結果を見る必要がある。

## SG・NACL・ルート障害の比較表

| 項目 | SGでHTTP拒否 | NACLで戻りエフェメラルポート拒否 | デフォルトルート欠落 |
|---|---|---|---|
| **症状(curl)** | タイムアウト(接続確立せず) | タイムアウト(接続はできるが応答が返らない) | タイムアウト(経路自体がない) |
| **SSHへの影響** | なし(別ルールのため無影響) | なし(port 80のみ制限) | **あり**(全通信が不可になる) |
| **Flow Logsの見え方** | インバウンドtcp/80が`REJECT`。同時刻のtcp/22は`ACCEPT` | インバウンドtcp/80は`ACCEPT`、対応するアウトバウンド(src port 80)が`REJECT` | **両方向とも`ACCEPT`** (ルート評価はFlow Logsの対象外) |
| **ステートフル/ステートレス** | ステートフル(片方向のルールで往復を許可) | ステートレス(往復それぞれにルールが必要) | ルーティングの問題(SG/NACLとは無関係のレイヤー) |
| **切り分け方法** | `aws ec2 describe-security-group-rules` でport 80ルールの有無を確認 | `aws ec2 describe-network-acls` で往復両方向のルールを確認。Flow Logsで方向別のACCEPT/REJECTパターンを見る | `aws ec2 describe-route-tables` で `0.0.0.0/0` の有無を確認。Flow LogsがACCEPTでも疎通しない場合はまずここを疑う |
| **復旧方法** | `terraform apply` (SGルールはTerraform管理下、ドリフト修復で自動的に再作成) | `aws ec2 delete-network-acl-entry` (NACLルールはTerraform管理外の一時ルールのため手動削除が必要) | `terraform apply` (ルートもTerraform管理下、ドリフト修復で自動的に再作成) |

## Flow Logsだけでは判別できない限界(実測で確認)

本ラボの障害試験3(ルート欠落)で、**Flow Logsが両方向ともACCEPTを記録しているにもかかわらず、実際には通信が成立しない**という事象を実際に観測した(`evidence/06-flow-logs/flow-logs-during-route-delete.txt`)。

理由: VPC Flow LogsはENI上でのセキュリティグループ/NACL評価の結果を記録するものであり、**ルートテーブルによる経路選択の可否はFlow Logsの記録対象に含まれない**。そのため、

- SG拒否 → 明確に `REJECT` として記録される
- NACL拒否 → 明確に `REJECT` として記録される(ただし方向を見る必要がある)
- **ルート欠落 → SG/NACLの評価自体は通過するため `ACCEPT` のまま記録され、Flow Logsだけでは「届いたのか、それとも経路がなく戻ってこなかったのか」を判別できない**

さらに、SG拒否とNACL拒否についても、Flow Logsの1レコード単体(`REJECT`という結果のみ)からは「SGで拒否されたのか、NACLで拒否されたのか」を確定できない。本ラボでは以下の傍証を組み合わせて初めて区別した。

1. **SG拒否の傍証**: 同一送信元からの別ポート(SSHなど、許可されているポート)が同時刻に`ACCEPT`されているか比較する。SGはルールごとに独立して評価されるため、拒否されたポートだけが`REJECT`になる。
2. **NACL拒否の傍証**: インバウンドとアウトバウンドの両方向のレコードを突き合わせ、「片方向は`ACCEPT`だが逆方向は`REJECT`」というパターンを探す。NACLはステートレスなので、このような非対称な結果が生じる。SGだけが原因であれば、多くの場合往復とも同じ結果(許可 or 拒否)になる。

**結論**: Flow Logsは強力な一次情報源だが、単独で完全な原因特定はできない。`describe-security-group-rules` / `describe-network-acls` / `describe-route-tables` による設定の直接確認と組み合わせる必要がある。

## 一般的な切り分けフロー

1. `curl -v` で症状を確認(接続確立前に失敗 = SG/経路の疑い、接続後にハング = NACL/戻り経路の疑い)
2. `aws ec2 describe-route-tables` でデフォルトルートの有無を確認
3. `aws ec2 describe-security-group-rules` で対象ポートの許可有無を確認
4. `aws ec2 describe-network-acls` で往復両方向のルールを確認
5. CloudWatch Logs (Flow Logs) で実際のACCEPT/REJECTパターンを確認し、1〜4の仮説と突き合わせる

## 復旧手順(共通)

すべての障害試験は `scripts/restore.sh` で復旧できる。

1. Terraform管理外の一時NACLルール(rule number 90)があれば `aws ec2 delete-network-acl-entry` で削除
2. `terraform plan` / `terraform apply` でTerraform管理下のリソース(SGルール、ルート)のドリフトを修復
3. `curl` でHTTP 200が返ることを確認して復旧完了とする
