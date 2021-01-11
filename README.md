# ECS + Fargate + EFSで構築したWordPress環境
## 目的
- ECS、Fargateなど先進コンテナ技術に対しての理解を深めること
- EFSを使用することで、WordPressがコンテナ内で画像などの静的ファイルを永続化できない問題を解決する

## 構成
- クライアント〜ALB間の通信はHTTPS、ALB〜ECSタスク（Fargate）間の通信はHTTP
- ECSタスク内の `/var/www/html/wp-content/uploads` はEFSで永続化

![image](https://github.com/pm-homma/wordpress-ecs-fargate/blob/images/diagrams/aws-diagram.png?raw=true)

## インフラ構築の手順
1. シンガポールリージョンにVPCを作成
2. 必要になるサブネット（ひとまず各Availability Zoneにパブリックとプライベートサブネットを1つずつ作成）
3. 必要なセキュリティグループを作成（ECS用、EFS用、ALB用、RDS用）
4. 必要なVPCエンドポイントを作成（SSM、S3、ECR(.apiと.dkr)、Logs）→ECSをプライベートサブネットに配置すると、VPC外にあるS3やECRなどのリソースがインターネットを経由して取得できなくなるので、VPCエンドポイントを作成する）
5. ALBを作成（Fargateを配置するプライベートサブネットと同じAvailability Zoneのパブリックサブネットを、ALBのAvailabity Zoneに登録）
6. 以下の手順で、Route53にACMから取得したSSL証明書・ALBのDNS名を設定する
7. RDSを作成
8. EFSを作成し、「ネットワーク」のマウントターゲットにECSからのアクセスを2049番ポートで通すセキュリティグループを設定
9. ECSクラスタを作成し、そのクラスタでタスク定義を作成。そしてそのタスク定義をもとに、ECSサービスをFargateで作成する。（タスク定義、ECSサービスの設定は以下）
10. 立ち上がったECSタスクにSession Managerでログインし、uploads配下の所有ユーザーがrootになっているので、chownで所有ユーザーをwww-dataに変更。
11. Route53で登録したドメインにアクセスしてフロントページが見れるか確認。そして管理画面にアクセスして、メディアから問題なく画像がアップロードできることを確認（Sesssion Managerでログインして、Fargate内のuploadsディレクトリ配下で対象の月日のディレクトリ内に画像が入っていることも確認できた）

## Route53

## ECS
### Task Definition
### ECSサービス

## EFS
### 設定したこと
- EFSの「ネットワーク」にセキュリティグループを設定（EFS用のセキュリティグループを作成して、FargateインスタンスのSGからのアクセスを2049番ポートで受け付ける）
- Session Managerでログインして、/var/www/html/wp-content/uploadsの権限を `chown www-data:www-data /var/www/html/wp-content/uploads` で、所有ユーザーをwww-dataに変更。この際ついでに `df -h` でEFSがマウントされているかどうかチェックする。

## 現構成の問題点と解決法
### 問題点
- タスク数を2つ以上にすると、WordPressの管理画面にログインすることができなくなる
### トライしたこと
- wp-config.phpに、リダイレクトループを防ぐコードを追加した

### 解決法
- WordPressの.htaccessに、HTTPでアクセスされたらHTTPSに書き換えるように設定を追記する（現時点ではうまくいっていない）
