# LinkVault Server 1.0

LinkVault Server 1.0 是 LinkVault 1.0 的 Spring Boot 服务端，负责认证、用户与设备、文件元数据、上传下载任务、回收站、配额和对象存储访问。客户端只调用服务端 API，不直接持有 MinIO 凭据。

## 目录结构

- `src/main/java/com/linkvault/common`：通用配置、统一响应、异常处理、安全上下文和基础领域类型。
- `src/main/java/com/linkvault/modules`：业务模块，包括 `auth`、`users`、`devices`、`files`、`uploads`、`downloads`、`transfers`、`recyclebin`、`storage`、`quota` 和 `health`。
- `src/main/resources/application*.yml`：默认、开发和生产环境配置。
- `src/main/resources/db/migration`：Flyway 数据库迁移脚本。
- `src/test`：服务端测试配置与测试用例。
- `infra/docker`：本地 Docker Compose 部署文件与环境变量示例。
- `Dockerfile`：API 服务容器镜像定义。

## 本地依赖

服务端开发需要：

- JDK 21
- Maven 3.9 或 IDE 自带 Maven
- Docker Desktop

本地依赖包括 PostgreSQL、Redis 和 MinIO，可在本目录启动：

```powershell
docker compose -f infra/docker/docker-compose.yml up -d postgres redis minio minio-init
```

默认地址：

- PostgreSQL: `localhost:5432`
- Redis: `localhost:6379`
- MinIO API: `http://localhost:9000`
- MinIO Console: `http://localhost:9001`
- MinIO 用户名/密码：`linkvault` / `linkvault-secret`
- MinIO Bucket: `linkvault`

## 本地运行

```powershell
mvn spring-boot:run
```

如果系统 `PATH` 中没有 Maven，也可以使用 IDE 自带 Maven 或直接在 IDE 中运行 `LinkVaultApplication`。

健康检查：

```powershell
Invoke-RestMethod http://localhost:8080/api/v1/health
```

## 测试与打包

```powershell
mvn test
mvn clean package
java -jar target/linkvault-server-1.0.0.jar
```

## Docker Compose

构建 jar 后，可启动完整后端栈：

```powershell
mvn clean package
docker compose -f infra/docker/docker-compose.yml up --build
```

默认暴露服务：

- API: `http://localhost:8080`
- PostgreSQL: `localhost:5432`
- Redis: `localhost:6379`
- MinIO API: `http://localhost:9000`
- MinIO Console: `http://localhost:9001`

## API

服务端接口统一使用 `/api/v1` 前缀，OpenAPI 契约位于仓库根目录的 `contracts/openapi/linkvault-api.yaml`。修改接口时请同步更新契约与客户端调用。
