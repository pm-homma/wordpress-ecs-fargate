# ECS + Fargate + EFSで構築したWordPress環境
## 目的
- ECSとFargateを使ってAWS上でコンテナ環境を構築することができるようにすること
- EFSを使用することで、WordPressがコンテナ内で画像などの静的ファイルを永続化できない問題を解決すること

## 構成
- クライアント〜ALB間の通信はHTTPS、ALB〜ECSタスク（Fargate）間の通信はHTTP
- ECSタスク内の `/var/www/html/wp-content/uploads` はEFSで永続化

![image](https://github.com/pm-homma/wordpress-ecs-fargate/blob/images/diagrams/aws-diagram.png?raw=true)

## インフラ構築の手順
1. シンガポールリージョンにVPCを作成
2. 必要になるサブネットを作成（ひとまず各Availability Zoneにパブリックとプライベートサブネットを1つずつ）
3. 必要なセキュリティグループを作成（ECS用、EFS用、ALB用、RDS用）
4. 必要なVPCエンドポイントを作成（SSM、S3、ECR(.apiと.dkr)、Logs）→ECSをプライベートサブネットに配置すると、VPC外にあるS3やECRなどのリソースがインターネットを経由して取得できなくなるので、VPCエンドポイントを作成する）
5. ALBを作成（Fargateを配置するプライベートサブネットと同じAvailability Zoneのパブリックサブネットを、ALBのAvailabity Zoneに登録）
6. 以下の手順で、Route53にACMから取得したSSL証明書・ALBのDNS名を設定する
7. RDSを作成
8. EFSを作成し、「ネットワーク」のマウントターゲットにECSタスクからのアクセスを2049番ポートで通すセキュリティグループを設定
9. ECSクラスタを作成し、そのクラスタでタスク定義を作成。そしてそのタスク定義をもとに、ECSサービスをFargateで作成する。（タスク定義、ECSサービスの設定は以下）
10. 立ち上がったECSタスクにSession Managerでログインし、uploads配下の所有ユーザーがrootになっているので、chownで所有ユーザーをwww-dataに変更。
11. Route53で登録したドメインにアクセスしてフロントページが見れるか確認。そして管理画面にアクセスして、メディアから問題なく画像がアップロードできることを確認（Sesssion Managerでログインして、Fargate内のuploadsディレクトリ配下で対象の月日のディレクトリ内に画像が入っていることも確認できた）

## VPCエンドポイント
- SSM、S3、ECR(.apiと.dkr)、LogsのVPCエンドポイントを作成する。
### 手順
1. 「サービス名」でVPCエンドポイントが必要なサービスを選択する。
2. インターフェース型（SSM、ECR(.apiと.dkr)、Logs）はエンドポイントを配置するサブネットにそれぞれprivateのものを選択する。ゲートウェイ型（S3）は「ルートテーブルの設定」で、privateサブネットに紐づけられているルートテーブルを選択する。
3. （インターフェース型のみ）セキュリティグループに、443番ポートからの通信を許可するセキュリティグループを紐付ける（VPCエンドポイントで使用するSecure Linkでは443番ポートで通信するため）

## ドメイン設定
1. ドメインを取得
2. Route53で上で取得したドメインのホストゾーンを作成
3. ACMからSSL証明書を取得
4. ホストゾーンのCNAMEレコードにSSL証明書の情報を登録
5. ALBを作成
6. ホストゾーンのAレコードにALBのDNS名を登録

## ECS
### Task Definition
- タスクロール・タスク実行ロール：ポリシーAmazonSSMManagedInstanceCore、AmazonECSTaskExecutionRolePolicy をアタッチしたロールを設定する
- コンテナの定義は以下のように設定する
	- イメージ：今回作成したDockerfileのイメージをプッシュしたECRリポジトリのURI
	- ポートマッピング：80, tcp
	- 環境変数：
		- WORDPRESS_DB_HOST：RDSのエンドポイント
		- WORDPRESS_DB_NAME：RDSで設定したDBの名前
		- WORDPRESS_DB_PASSWORD：RDSで設定したパスワード
		- WORDPRESS_DB_USER：RDSで設定したユーザー名
		- SSM_AGENT_CODE：Systems Managerのハイブリッドアクティベーション登録で取得したActivation Code（今回はParameter Storeに保存して、valueFromでキー名を指定して値を参照）
		- SSM_AGENT_ID：Systems Managerのハイブリッドアクティベーション登録で取得したActivation ID（今回はParameter Storeに保存して、valueFromでキー名を指定して値を参照）
	- マウントポイント：
		- ソースボリューム：「ボリューム」で追加したEFS
		- コンテナパス：/var/www/html/wp-content/uploads

### ECSサービス
- タスク定義：上記設定のタスク定義
- プラットフォームのバージョン：1.4.0（LATEST or 1.3.0だとEFSマウント失敗する）
- 許可されたサブネット：ALBで指定したパブリックサブネットと同じAvailability Zoneにあるプライベートサブネットを選択する。
- セキュリティグループ：ALBからの80番ポートへの通信を許可するセキュリティグループを紐付ける（ALBに紐づけているセキュリティグループをソースに指定する）
- ロードバランシング：
	- ロードバランサーの種類：Application Load Balancer
	- ロードバランサー名：ECS用に作成したALB
	- ロードバランス用のコンテナ：タスク定義で定義したコンテナが表示されるので選択
		- ターゲットグループ名：ALBに紐づけているターゲットグループを選択

## EFS
- EFSの「ネットワーク」にセキュリティグループを設定（EFS用のセキュリティグループを作成して、FargateインスタンスのSGからのアクセスを2049番ポートで受け付ける）
- Session Managerでログインして、/var/www/html/wp-content/uploadsの権限を `chown www-data:www-data /var/www/html/wp-content/uploads` で、所有ユーザーをwww-dataに変更。この際ついでに `df -h` でEFSがマウントされているかどうかチェックする。

## 現構成の問題点と解決法
### 問題点
- タスク数を2つ以上にすると、WordPressの管理画面にログインすることができなくなる
### トライしたこと
- wp-config.phpに、リダイレクトループを防ぐコードを追加した
- .htaccessにリダイレクトループを防ぐコードを追加した

### 解決したやり方
- ALBのターゲットグループを2つ紐づけて、1つ目のターゲットグループにECSサービスでタスクを1つ立ち上げて、もう1つのターゲットグループに別のECSサービスでタスクを1つ立ち上げると管理画面にログインできた。
