@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

set "CONFIG_FILE=%SCRIPT_DIR%server.env"
if not exist "%CONFIG_FILE%" (
  echo Missing config file: %CONFIG_FILE%
  exit /b 1
)

for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
  if not "%%A"=="" set "%%A=%%B"
)

if "%SPRING_PROFILES_ACTIVE%"=="" set "SPRING_PROFILES_ACTIVE=dev"
if "%LINKVAULT_SERVER_PORT%"=="" set "LINKVAULT_SERVER_PORT=8080"
if "%LINKVAULT_POSTGRES_HOST_PORT%"=="" set "LINKVAULT_POSTGRES_HOST_PORT=5432"
if "%LINKVAULT_REDIS_HOST_PORT%"=="" set "LINKVAULT_REDIS_HOST_PORT=6379"
if "%LINKVAULT_MINIO_API_HOST_PORT%"=="" set "LINKVAULT_MINIO_API_HOST_PORT=9000"
if "%LINKVAULT_MINIO_CONSOLE_HOST_PORT%"=="" set "LINKVAULT_MINIO_CONSOLE_HOST_PORT=9001"
if "%LINKVAULT_POSTGRES_DB%"=="" set "LINKVAULT_POSTGRES_DB=linkvault"
if "%LINKVAULT_POSTGRES_USER%"=="" set "LINKVAULT_POSTGRES_USER=linkvault"
if "%LINKVAULT_POSTGRES_PASSWORD%"=="" set "LINKVAULT_POSTGRES_PASSWORD=linkvault"
if "%LINKVAULT_MINIO_ACCESS_KEY%"=="" set "LINKVAULT_MINIO_ACCESS_KEY=linkvault"
if "%LINKVAULT_MINIO_SECRET_KEY%"=="" set "LINKVAULT_MINIO_SECRET_KEY=linkvault-secret"
if "%LINKVAULT_MINIO_BUCKET%"=="" set "LINKVAULT_MINIO_BUCKET=linkvault"

set "LINKVAULT_DATASOURCE_URL=jdbc:postgresql://localhost:%LINKVAULT_POSTGRES_HOST_PORT%/%LINKVAULT_POSTGRES_DB%"
set "LINKVAULT_DATASOURCE_USERNAME=%LINKVAULT_POSTGRES_USER%"
set "LINKVAULT_DATASOURCE_PASSWORD=%LINKVAULT_POSTGRES_PASSWORD%"
set "LINKVAULT_REDIS_HOST=localhost"
set "LINKVAULT_REDIS_PORT=%LINKVAULT_REDIS_HOST_PORT%"
set "LINKVAULT_MINIO_ENDPOINT=http://localhost:%LINKVAULT_MINIO_API_HOST_PORT%"
set "LINKVAULT_MINIO_PUBLIC_ENDPOINT=http://localhost:%LINKVAULT_MINIO_API_HOST_PORT%"
set "LINKVAULT_MINIO_INITIALIZE_BUCKET=true"

where docker >nul 2>nul
if errorlevel 1 (
  echo Docker is required but was not found in PATH.
  exit /b 1
)

docker compose version >nul 2>nul
if errorlevel 1 (
  echo Docker Compose is required but is not available through "docker compose".
  exit /b 1
)

where mvn >nul 2>nul
if errorlevel 1 (
  echo Maven is required but was not found in PATH.
  exit /b 1
)

echo Starting LinkVault Docker dependencies...
docker compose --env-file "%CONFIG_FILE%" -f infra/docker/docker-compose.yml up -d postgres redis minio minio-init
if errorlevel 1 exit /b 1

echo Starting LinkVault API on http://localhost:%LINKVAULT_SERVER_PORT%/api/v1
mvn spring-boot:run

endlocal
