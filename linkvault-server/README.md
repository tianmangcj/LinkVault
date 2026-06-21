# LinkVault Server 1.0

LinkVault Server 1.0 是 LinkVault 1.0 的 Spring Boot 服务端，负责认证、用户与设备、文件元数据、上传下载任务、回收站、配额和对象存储访问。客户端只调用服务端 API，不直接持有 MinIO 凭据。

## 目录结构

- `src/main/java/com/linkvault/common`：通用配置、统一响应、异常处理、安全上下文和基础领域类型。
- `src/main/java/com/linkvault/modules`：业务模块，包括 `auth`、`users`、`devices`、`files`、`uploads`、`downloads`、`transfers`、`recyclebin`、`storage`、`quota` 和 `health`。
- `src/main/resources/application*.yml`：默认、开发和生产环境配置。
- `src/main/resources/db/migration`：Flyway 数据库迁移脚本。
- `src/test`：服务端测试配置与测试用例。
- `infra/docker`：本地 Docker Compose 部署文件与环境变量示例。
- `server.env`：本地后端启动配置，可修改 Spring Boot、PostgreSQL、Redis 和 MinIO 暴露端口。
- `start-server.bat` / `start-server.sh`：Windows / Linux 一键启动脚本。
- `Dockerfile`：API 服务容器镜像定义。

## 本地依赖

服务端开发需要：

- JDK 21
- Maven 3.9 或 IDE 自带 Maven
- Docker Desktop 或 Docker Engine

## 端口配置

修改 `server.env` 即可调整本地启动端口：

```env
LINKVAULT_SERVER_PORT=8080
LINKVAULT_POSTGRES_HOST_PORT=5432
LINKVAULT_REDIS_HOST_PORT=6379
LINKVAULT_MINIO_API_HOST_PORT=9000
LINKVAULT_MINIO_CONSOLE_HOST_PORT=9001
```

默认地址：

- API: `http://localhost:8080`
- PostgreSQL: `localhost:5432`
- Redis: `localhost:6379`
- MinIO API: `http://localhost:9000`
- MinIO Console: `http://localhost:9001`
- MinIO 用户名/密码：`linkvault` / `linkvault-secret`
- MinIO Bucket: `linkvault`

## 一键启动

Windows：

```bat
start-server.bat
```

Linux / macOS：

```sh
sh start-server.sh
```

脚本会读取 `server.env`，启动 PostgreSQL、Redis、MinIO 和 Bucket 初始化任务，然后运行：

```sh
mvn spring-boot:run
```

健康检查：

```powershell
Invoke-RestMethod http://localhost:8080/api/v1/health
```

如果修改了 `LINKVAULT_SERVER_PORT`，健康检查地址中的端口也要同步替换。

## 手动运行

只启动本地依赖：

```powershell
docker compose --env-file server.env -f infra/docker/docker-compose.yml up -d postgres redis minio minio-init
```

再启动 Spring Boot：

```powershell
$env:LINKVAULT_SERVER_PORT="8080"
$env:LINKVAULT_DATASOURCE_URL="jdbc:postgresql://localhost:5432/linkvault"
$env:LINKVAULT_REDIS_HOST="localhost"
$env:LINKVAULT_REDIS_PORT="6379"
$env:LINKVAULT_MINIO_ENDPOINT="http://localhost:9000"
$env:LINKVAULT_MINIO_PUBLIC_ENDPOINT="http://localhost:9000"
mvn spring-boot:run
```

## 测试与打包

```powershell
mvn test
mvn clean package
java -jar target/linkvault-server-1.0.0.jar
```

打包后的 jar 也可以通过环境变量修改端口：

```powershell
$env:LINKVAULT_SERVER_PORT="8081"
java -jar target/linkvault-server-1.0.0.jar
```

## Docker Compose

构建 jar 后，可启动完整后端栈：

```powershell
mvn clean package
docker compose --env-file server.env -f infra/docker/docker-compose.yml up --build
```

`docker-compose.yml` 会使用 `server.env` 中的端口配置。API 容器、PostgreSQL、Redis、MinIO API 和 MinIO Console 的宿主机端口都可以在 `server.env` 中修改。

## API

服务端接口统一使用 `/api/v1` 前缀，OpenAPI 契约位于仓库根目录的 `contracts/openapi/linkvault-api.yaml`。修改接口时请同步更新契约与客户端调用。
