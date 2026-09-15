# Phase 1 ステータスシート

> **前提**: 本シートはPhase 1検証実施時点(2026-09-16 JST早朝、UTC 2026-09-15 20:37〜21:11)の記録である。検証完了後、`terraform destroy`により**AWS上の実リソースは全て削除済み**(2026-09-16、40リソース削除、`describe-instances`等で残存なしを個別確認済み)。以下のステータスは「その時点で実際に確認できた結果」であり、現在AWS上にリソースが稼働しているという意味ではない。現在の実リソース有無は `docs/resource-inventory.md` を参照。
>
> 再現するには `terraform apply` が必要(`README.md` 構築手順)。再デプロイ後は `scripts/update-status.sh` で最新状態を `evidence/current-status.txt` に反映できる。

## ステータス凡例

| 記号 | 意味 |
|---|---|
| ⬜ | 未着手 |
| 🟡 | 構築済み・未検証 |
| 🟢 | PASS |
| 🔴 | FAIL |
| ⚪ | 対象外 |

## 概要表

| No. | 検証テーマ | 構築状態 | 正常性試験 | 障害試験 | 復旧確認 | 実施日時(UTC) | 結果 | 証跡へのリンク | 備考・考察 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Public EC2の構築 | 🟢 | 🟢 | ⬜ | 🟢 | 2026-09-15 21:11 | PASS | [evidence/01-public-ec2/](../evidence/01-public-ec2/) | 障害試験候補「Webサービス停止」は本セッションでは未実施(⬜)。ルート欠落試験はNo.6に計上 |
| 2 | Security Group | 🟢 | 🟢 | 🟢 | 🟢 | 2026-09-15 21:04-21:11 | PASS | [evidence/02-security-group/](../evidence/02-security-group/) | SGからHTTP許可を削除する試験を実施・復旧確認済み |
| 3 | NACL | 🟢 | 🟢 | 🟡 | 🟢 | 2026-09-15 21:06-21:11 | PASS(一部未実施) | [evidence/03-nacl/](../evidence/03-nacl/) | 「エフェメラルポート拒否」のみ実施。「HTTP受信拒否」モードはスクリプト対応済みだが本セッションでは未実行(⬜) |
| 4 | Private EC2への接続 | 🟢 | 🟢 | ⚪ | 🟢 | 2026-09-15 21:11 | PASS | [evidence/04-private-ec2/](../evidence/04-private-ec2/) | 本テーマ向けの障害試験は仕様上定義なし(対象外) |
| 5 | Session Manager接続 | 🟢 | 🟢 | ⚪ | ⚪ | 2026-09-15 21:00 | PASS | [evidence/05-session-manager/](../evidence/05-session-manager/) | SSM用VPCエンドポイント追加(ユーザー承認済み)。障害注入・障害試験後の再確認は未実施 |
| 6 | VPC Flow Logs解析 | 🟢 | 🟢 | 🟢 | 🟢 | 2026-09-15 21:01-21:10 | PASS | [evidence/06-flow-logs/](../evidence/06-flow-logs/) | デフォルトルート削除試験で「Flow Logsだけでは判別不可」の限界を実測で確認 |

**総合結果**: 6テーマ中 6テーマがPASS(構築・正常性試験は全テーマで実施・確認済み)。ただし障害試験は「NACL HTTP受信拒否」「Webサービス停止」の2件が未実施(⬜)であり、これらを推測でPASS扱いにはしていない。

---

## 1. Public EC2の構築 — 詳細

| Test ID | 確認内容 | 実行コマンド | 期待結果 | 実測結果 | 判定 | 証跡ファイル | 復旧確認 |
|---|---|---|---|---|---|---|---|
| PUB-01 | HTTP疎通 | `curl -i http://<EIP>/` | HTTP 200、Apacheのレスポンス | `HTTP/1.1 200 OK`, `Server: Apache/2.4.68 (Amazon Linux)` | 🟢 PASS | [http-response.txt](../evidence/01-public-ec2/http-response.txt) | ⚪ (障害注入なし) |
| PUB-02 | SSH到達性(バナーのみ) | `exec 3<>/dev/tcp/<EIP>/22; head -c 64 <&3` | SSHバナー文字列を受信 | バナー受信を確認 | 🟢 PASS | [ssh-banner.txt](../evidence/01-public-ec2/ssh-banner.txt) | ⚪ |
| PUB-03 | 内部IP・ルーティングテーブル取得 | `ssh ... "hostname; ip -4 addr show; ip route"` | プライベートIP・`default via <gw>`ルートが表示される | `10.10.1.234/24`, `default via 10.10.1.1 dev ens5` を確認 | 🟢 PASS | [ip-and-route.txt](../evidence/01-public-ec2/ip-and-route.txt) | ⚪ |
| PUB-04 | デフォルトルート削除(障害試験) | `aws ec2 delete-route --route-table-id <rtb> --destination-cidr-block 0.0.0.0/0` | 反映後、HTTP/SSH全断 | 反映まで約10-20秒のラグの後、5回連続タイムアウトを確認 | 🟢 PASS(評価はNo.6のFlow Logs観点で詳述) | [evidence/06-flow-logs/](../evidence/06-flow-logs/) | 🟢 `terraform apply`でルート再作成、HTTP 200へ復旧確認 |
| PUB-05 | Webサービス停止(障害試験) | `systemctl stop httpd`(想定) | HTTPのみ不通、SSHは継続 | **未実施** | ⬜ 未着手 | なし | ⬜ |

---

## 2. Security Group — 詳細

| Test ID | 確認内容 | 実行コマンド | 期待結果 | 実測結果 | 判定 | 証跡ファイル | 復旧確認 |
|---|---|---|---|---|---|---|---|
| SG-01 | ルール内容確認 | `aws ec2 describe-security-group-rules --filters Name=group-id,Values=<sg-id>` | SSH:22(管理者IP/32)、HTTP:80(0.0.0.0/0)、Egress全許可の3ルール | 3ルールとも定義通り | 🟢 PASS | [sg-rules-current.txt](../evidence/02-security-group/sg-rules-current.txt) | ⚪ |
| SG-02 | HTTP許可時の疎通 | `curl -o /dev/null -w "%{http_code}" http://<EIP>/` | 200 | `http_status=200` | 🟢 PASS | [http-allowed.txt](../evidence/02-security-group/http-allowed.txt) | ⚪ |
| SG-03 | ステートフル動作確認 | 同一セッションでHTTP応答が自動的に返る(戻り方向のルール不要) | 往路ルールのみで応答が返る | 単一方向ルールで正常応答を確認 | 🟢 PASS | [stateful-note.txt](../evidence/02-security-group/stateful-note.txt) | ⚪ |
| **SG-04** | **SGからHTTP許可を削除** | `aws ec2 revoke-security-group-ingress --group-id <sg> --protocol tcp --port 80 --cidr 0.0.0.0/0` | HTTPタイムアウト、SSHは無影響 | API成功直後は反映ラグでHTTP 200のまま。10-20秒後、5回連続タイムアウトを確認。同時刻のSSHバナー到達は正常 | 🟢 PASS | [before-revoke-http.txt](../evidence/02-security-group/before-revoke-http.txt), [after-revoke-http.txt](../evidence/02-security-group/after-revoke-http.txt), [after-revoke-ssh-still-ok.txt](../evidence/02-security-group/after-revoke-ssh-still-ok.txt), [flow-logs-during-sg-deny.txt](../evidence/02-security-group/flow-logs-during-sg-deny.txt) | 🟢 |
| **SG-06** | **復旧後の再疎通** | `terraform apply`(ドリフト修復)→`curl` | HTTP 200へ復帰 | ルール自動再作成、HTTP 200を確認。直後の全体再検証(`verify.sh all`)でも200を再確認 | 🟢 PASS | [restored-http.txt](../evidence/02-security-group/restored-http.txt) | 🟢 |

---

## 3. NACL — 詳細

| Test ID | 確認内容 | 実行コマンド | 期待結果 | 実測結果 | 判定 | 証跡ファイル | 復旧確認 |
|---|---|---|---|---|---|---|---|
| NACL-01 | ルール内容確認 | `aws ec2 describe-network-acls --network-acl-ids <nacl-id>` | 既定は全許可(allow -1, 両方向) | ルール100(allow -1)を往復とも確認 | 🟢 PASS | [nacl-rules-current.txt](../evidence/03-nacl/nacl-rules-current.txt) | ⚪ |
| NACL-02 | ステートレス性・エフェメラルポートに関する考察 | (ドキュメント確認) | 戻りパケットはエフェメラルポート(32768-60999)宛であることを理解した上で試験設計 | ノートとして記録 | 🟢 PASS | [ephemeral-port-note.txt](../evidence/03-nacl/ephemeral-port-note.txt) | ⚪ |
| **NACL-03** | **NACLでHTTP受信を拒否** | `aws ec2 create-network-acl-entry --rule-number 90 --protocol tcp --port-range From=80,To=80 --cidr-block 0.0.0.0/0 --rule-action deny --ingress`(`scripts/inject-nacl-failure.sh http`で自動化済みだが未実行) | HTTPタイムアウト | **未実施** | ⬜ 未着手 | なし | ⬜ |
| **NACL-04** | **NACLでエフェメラルポートを拒否** | `aws ec2 create-network-acl-entry --rule-number 90 --protocol tcp --port-range From=1024,To=65535 --cidr-block 0.0.0.0/0 --rule-action deny --egress` | インバウンド80は許可のままだが応答が戻らずタイムアウト | 反映まで約10-15秒。以降5回連続タイムアウト。Flow Logsで「インバウンド`ACCEPT`/アウトバウンド(src port 80)`REJECT`」の非対称パターンを確認(ステートレス性の直接証拠) | 🟢 PASS | [before-ephemeral-deny.txt](../evidence/03-nacl/before-ephemeral-deny.txt), [after-ephemeral-deny.txt](../evidence/03-nacl/after-ephemeral-deny.txt), [rules-after-ephemeral-deny.txt](../evidence/03-nacl/rules-after-ephemeral-deny.txt), [flow-logs-during-ephemeral-deny.txt](../evidence/03-nacl/flow-logs-during-ephemeral-deny.txt) | 🟢 |
| NACL-06 | 復旧後の再疎通 | `aws ec2 delete-network-acl-entry --rule-number 90`(Terraform管理外のため手動削除)→`curl` | HTTP 200へ復帰 | ルール削除後、直後の全体再検証(`verify.sh all`)でHTTP 200を確認 | 🟢 PASS | [restored-http.txt](../evidence/02-security-group/restored-http.txt)(共通ファイル、最終復旧時点の内容) | 🟢 |

---

## 4. Private EC2への接続 — 詳細

| Test ID | 確認内容 | 実行コマンド | 期待結果 | 実測結果 | 判定 | 証跡ファイル | 復旧確認 |
|---|---|---|---|---|---|---|---|
| PRIV-01 | Public IP不付与の確認 | `aws ec2 describe-instances --instance-ids <private-id> --query "...PublicIpAddress..."` | `PublicIpAddress`が`None` | `None`を確認 | 🟢 PASS | [no-public-ip.txt](../evidence/04-private-ec2/no-public-ip.txt) | ⚪ |
| PRIV-02 | ProxyJump経由の接続(秘密鍵は踏み台へコピーしない) | `ssh -i <key> -o ProxyCommand="ssh -i <key> -W %h:%p ec2-user@<EIP>" ec2-user@<private-ip>` | 踏み台経由でPrivate EC2にログインでき、秘密鍵は操作端末に留まる | ログイン成功、hostname/IPを確認 | 🟢 PASS | [proxyjump-session.txt](../evidence/04-private-ec2/proxyjump-session.txt) | ⚪ |

`-J`単体では一部OpenSSHビルドで踏み台ホップへ`-i`が継承されず認証失敗する事象に遭遇したため、`ProxyCommand`明示方式に修正(README「実行結果と設計上の考察」参照)。本テーマに対する障害試験は仕様上定義していない(対象外)。

---

## 5. Session Manager接続 — 詳細

| Test ID | 確認内容 | 実行コマンド | 期待結果 | 実測結果 | 判定 | 証跡ファイル | 復旧確認 |
|---|---|---|---|---|---|---|---|
| SSM-01 | IAM Role/Instance Profile付与確認 | (Terraform管理、`aws_iam_role`+`AmazonSSMManagedInstanceCore`) | Private/Public EC2の両方にアタッチ | アタッチ済み | 🟢 PASS | [iam-role-note.txt](../evidence/05-session-manager/iam-role-note.txt) | ⚪ |
| SSM-02 | SSM Agent登録状態確認 | `aws ssm describe-instance-information` | Private EC2が`Online` | 当初はNAT/エンドポイント不在のため未登録 → SSM用VPCエンドポイント3種(ユーザー承認後に作成)により登録・`Online`化 | 🟢 PASS | [ssm-instance-information.txt](../evidence/05-session-manager/ssm-instance-information.txt) | ⚪ |
| SSM-03 | SSHポート・踏み台を使わない接続 | `aws ssm start-session --target <private-id> --document-name AWS-StartNonInteractiveCommand ...` | SSH(22番ポート)を一切使わずコマンド実行できる | 成功。`curl http://example.com`は到達不可(NAT/IGW経路なし)も確認し、SSM専用の最小経路であることを裏付け | 🟢 PASS | [session-no-ssh-no-bastion.txt](../evidence/05-session-manager/session-no-ssh-no-bastion.txt) | ⚪ |

本テーマに対する障害注入試験(エンドポイント側の意図的な遮断など)は本Phase 1セッションでは実施していない(対象外)。障害試験後(SG/NACL/ルート)の再確認もSSM側では別途行っていない。

---

## 6. VPC Flow Logs解析 — 詳細

| Test ID | 確認内容 | 実行コマンド | 期待結果 | 実測結果 | 判定 | 証跡ファイル | 復旧確認 |
|---|---|---|---|---|---|---|---|
| FLOW-01 | ACCEPT/REJECTの記録確認 | `aws logs get-log-events --log-group-name /aws-network-lab/aws-network-lab/vpc-flow-logs --log-stream-name <eni>-all` | 送信元/宛先IP・ポート・actionが記録される | 複数ENIで`ACCEPT`/`REJECT`双方を確認(インターネットスキャン由来の`REJECT`含む) | 🟢 PASS | [baseline-events.txt](../evidence/06-flow-logs/baseline-events.txt) | ⚪ |
| **FLOW-04** | **デフォルトルートを削除** | `aws ec2 delete-route --route-table-id <rtb> --destination-cidr-block 0.0.0.0/0` | 通信不可になるが、Flow Logsの記録内容を検証 | curlは5回連続タイムアウト。**しかしFlow Logsは往復ともに`ACCEPT`のまま記録され、ルート欠落はFlow Logsだけでは判別不可能であることを実測で確認**(本試験の核心的発見) | 🟢 PASS(重要な限界を実証) | [before-route-delete.txt](../evidence/06-flow-logs/before-route-delete.txt), [after-route-delete.txt](../evidence/06-flow-logs/after-route-delete.txt), [route-table-after-delete.txt](../evidence/06-flow-logs/route-table-after-delete.txt), [flow-logs-during-route-delete.txt](../evidence/06-flow-logs/flow-logs-during-route-delete.txt) | 🟢 |
| FLOW-06 | 復旧後の再疎通(全体) | `terraform apply`→`scripts/verify.sh all` | 全検証(1-4)が正常復帰 | `FINAL_EXIT=0`。HTTP/SSH/NACL/ProxyJumpすべて正常復帰を再確認 | 🟢 PASS | [http-response.txt](../evidence/01-public-ec2/http-response.txt) 等、21:11台のタイムスタンプを持つ一連のファイル(最終再検証時に更新) | 🟢 |

詳細な比較・限界の説明は `docs/troubleshooting.md`「Flow Logsだけでは判別できない限界」を参照。
