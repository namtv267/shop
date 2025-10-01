# Microservice “Microshop” – Hướng dẫn triển khai (Local & AWS)

Tài liệu này hướng dẫn “end-to-end” để bạn dựng microservice gồm `order-service` (MongoDB) và `product-service` (PostgreSQL) với Spring Boot (Java 17, Gradle), quan trắc bằng Prometheus/Grafana, cảnh báo qua Slack & Maildev; phát triển bằng `docker-compose` và kiểm thử cluster bằng Docker Swarm. Phần cuối có lộ trình lên AWS (Swarm trên EC2 + RDS/Postgres + MongoDB Atlas hoặc self-managed).

---

## 0) Kiến trúc tổng thể

- 2 service tách biệt:
    - **product-service**: CRUD sản phẩm, dùng **PostgreSQL**.
    - **order-service**: quản lý đơn hàng, dùng **MongoDB**.
- Quan trắc & cảnh báo:
    - **Micrometer + Spring Actuator** → `/actuator/prometheus`
    - **Prometheus** scrape metrics → **Alertmanager** → Slack (webhook) & Maildev (SMTP 1025)
    - **Grafana** xem dashboard (datasource Prometheus)
- Môi trường:
    - **Dev local**: `docker-compose` (tốc độ nhanh, hot-reload).
    - **Test local dạng cluster**: Docker **Swarm** (`docker stack deploy`).
    - **AWS** (bước sau): Swarm trên EC2 (hoặc ECS), DB managed (RDS Postgres) + MongoDB Atlas (hoặc self-managed).

---

## 1) Khởi tạo project & cấu trúc repo

```
microshop/
├─ services/
│  ├─ product-service/
│  │  ├─ build.gradle
│  │  └─ src/main/java/com/example/product/...
│  └─ order-service/
│     ├─ build.gradle
│     └─ src/main/java/com/example/order/...
├─ ops/
│  ├─ docker-compose.dev.yml
│  ├─ docker-stack.local.yml               # cho Swarm
│  ├─ prometheus/
│  │  ├─ prometheus.yml
│  │  └─ alerts.yml
│  ├─ alertmanager/
│  │  └─ alertmanager.yml
│  └─ grafana/
│     ├─ provisioning/
│     │  ├─ datasources/datasource.yml
│     │  └─ dashboards/dashboards.yml
│     └─ dashboards/spring-micrometer.json # có thể dùng dashboard mẫu
├─ settings.gradle
├─ build.gradle
└─ .env.example
```

### 1.1) `settings.gradle`
```groovy
rootProject.name = 'microshop'
include 'services:product-service', 'services:order-service'
```

### 1.2) Gradle cha (quy định Java 17, Spring Boot 3.x)
```groovy
plugins {
  id 'org.springframework.boot' version '3.3.2' apply false
  id 'io.spring.dependency-management' version '1.1.5' apply false
  id 'java' apply false
}

subprojects {
  apply plugin: 'java'
  apply plugin: 'io.spring.dependency-management'

  group = 'com.example'
  version = '0.0.1-SNAPSHOT'
  sourceCompatibility = '17'

  repositories { mavenCentral() }

  dependencies {
    testImplementation 'org.springframework.boot:spring-boot-starter-test'
  }
}
```

### 1.3) `product-service/build.gradle`
```groovy
plugins { id 'org.springframework.boot' }

dependencies {
  implementation 'org.springframework.boot:spring-boot-starter-web'
  implementation 'org.springframework.boot:spring-boot-starter-actuator'
  implementation 'io.micrometer:micrometer-registry-prometheus'
  implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
  runtimeOnly 'org.postgresql:postgresql'
}
```

### 1.4) `order-service/build.gradle`
```groovy
plugins { id 'org.springframework.boot' }

dependencies {
  implementation 'org.springframework.boot:spring-boot-starter-web'
  implementation 'org.springframework.boot:spring-boot-starter-actuator'
  implementation 'io.micrometer:micrometer-registry-prometheus'
  implementation 'org.springframework.boot:spring-boot-starter-data-mongodb'
}
```

---

## 2) Mô hình DDD (gợi ý layout)

Ví dụ cho mỗi service:

```
src/main/java/com/example/<svc>/
├─ domain/
│  ├─ model/              # Entities/Aggregates (Product, Order, OrderItem…)
│  ├─ repository/         # Interface repository (domain-facing)
│  └─ service/            # Business logic (ứng dụng + domain)
├─ application/
│  └─ usecase/            # Application services, DTO vào/ra
├─ infrastructure/
│  ├─ persistence/        # JPA/Mongo impl của domain repository
│  └─ config/             # Spring configs (DB, Actuator, Micrometer)
└─ interfaces/
   └─ web/                # REST controllers, request/response mappers
```

### 2.1) Domain tối thiểu
- **product-service** (PostgreSQL/JPA):
    - `Product{id, name, price, stock}`
    - Repository: `ProductRepository` (JPA extends `JpaRepository`)
- **order-service** (MongoDB):
    - `Order{id, customerId, items:[{productId, qty, price}], status, createdAt}`
    - Repository: `OrderRepository` extends `MongoRepository`

### 2.2) Actuator & Prometheus
`application.yml` (mỗi service)
```yaml
server:
  port: 8080

management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      probes:
        enabled: true
  metrics:
    tags:
      application: ${SPRING_APP_NAME:product-service} # thay bằng service tương ứng
```

### 2.3) Cấu hình DB qua env

**product-service**:
```yaml
spring:
  datasource:
    url: jdbc:postgresql://${POSTGRES_HOST:postgres}:${POSTGRES_PORT:5432}/${POSTGRES_DB:productdb}
    username: ${POSTGRES_USER:product}
    password: ${POSTGRES_PASSWORD:product}
  jpa:
    hibernate:
      ddl-auto: update
    properties:
      hibernate.jdbc.lob.non_contextual_creation: true
```

**order-service**:
```yaml
spring:
  data:
    mongodb:
      uri: mongodb://${MONGO_USER:root}:${MONGO_PASSWORD:root}@${MONGO_HOST:mongo}:${MONGO_PORT:27017}/${MONGO_DB:orderdb}?authSource=admin
```

---

## 3) Docker cho phát triển (docker-compose)

Tạo `.env` từ `.env.example` (không commit secrets):
```
POSTGRES_DB=productdb
POSTGRES_USER=product
POSTGRES_PASSWORD=product
MONGO_INITDB_ROOT_USERNAME=root
MONGO_INITDB_ROOT_PASSWORD=root
MONGO_DB=orderdb

# Alerting
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX/YYY/ZZZ
ALERT_EMAIL_TO=alerts@example.com
```

### 3.1) `ops/docker-compose.dev.yml`
```yaml
version: "3.9"
name: microshop-dev

services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports: [ "5432:5432" ]
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  mongo:
    image: mongo:6
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_INITDB_ROOT_USERNAME}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD}
    ports: [ "27017:27017" ]
    volumes:
      - mongodata:/data/db
    healthcheck:
      test: ["CMD", "mongo", "--quiet", "localhost/test", "--eval", "db.runCommand({ ping: 1 })"]
      interval: 10s
      timeout: 5s
      retries: 6

  product-service:
    build:
      context: ../
      dockerfile: services/product-service/product.order.Dockerfile
    environment:
      SPRING_APP_NAME: product-service
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    depends_on:
      postgres:
        condition: service_healthy
    ports: [ "8081:8080" ]

  order-service:
    build:
      context: ../
      dockerfile: services/order-service/product.order.Dockerfile
    environment:
      SPRING_APP_NAME: order-service
      MONGO_HOST: mongo
      MONGO_PORT: 27017
      MONGO_DB: ${MONGO_DB}
      MONGO_USER: ${MONGO_INITDB_ROOT_USERNAME}
      MONGO_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD}
    depends_on:
      mongo:
        condition: service_healthy
    ports: [ "8082:8080" ]

  prometheus:
    image: prom/prometheus:v2.55.0
    command: ["--config.file=/etc/prometheus/prometheus.yml", "--web.enable-lifecycle"]
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/alerts.yml:/etc/prometheus/alerts.yml:ro
    ports: [ "9090:9090" ]

  alertmanager:
    image: prom/alertmanager:v0.27.0
    command: ["--config.file=/etc/alertmanager/alertmanager.yml"]
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    environment:
      SLACK_WEBHOOK_URL: ${SLACK_WEBHOOK_URL}
      ALERT_EMAIL_TO: ${ALERT_EMAIL_TO}
    ports: [ "9093:9093" ]

  grafana:
    image: grafana/grafana:11.1.0
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin
    volumes:
      - grafana:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
    ports: [ "3000:3000" ]
    depends_on: [prometheus]

  maildev:
    image: maildev/maildev:2
    ports:
      - "1080:1080"  # UI
      - "1025:1025"  # SMTP

volumes:
  pgdata: {}
  mongodata: {}
  grafana: {}
```

### 3.2) Dockerfile (mẫu) cho mỗi service
`services/product-service/Dockerfile` (tương tự cho order-service, đổi đường dẫn module)
```dockerfile
FROM gradle:8.9-jdk17 AS build
WORKDIR /home/gradle/project
COPY . .
RUN gradle :services:product-service:bootJar --no-daemon

FROM eclipse-temurin:17-jre
ENV JAVA_OPTS=""
WORKDIR /app
COPY --from=build /home/gradle/project/services/product-service/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["sh","-c","java $JAVA_OPTS -jar app.jar"]
```

---

## 4) Prometheus, Alertmanager, Grafana

### 4.1) `ops/prometheus/prometheus.yml`
```yaml
global:
  scrape_interval: 10s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/alerts.yml

scrape_configs:
  - job_name: product-service
    metrics_path: /actuator/prometheus
    static_configs:
      - targets: ['product-service:8080']
  - job_name: order-service
    metrics_path: /actuator/prometheus
    static_configs:
      - targets: ['order-service:8080']
  - job_name: alertmanager
    static_configs:
      - targets: ['alertmanager:9093']
```

### 4.2) `ops/prometheus/alerts.yml` (ví dụ cơ bản)
```yaml
groups:
- name: microshop.rules
  rules:
  - alert: InstanceDown
    expr: up == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Target down ({{ $labels.job }})"
      description: "{{ $labels.instance }} is down"

  - alert: HighErrorRate
    expr: rate(http_server_requests_seconds_count{outcome="SERVER_ERROR"}[5m]) > 0.1
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "5xx error rate high ({{ $labels.job }})"

  - alert: HighJVMHeapUsage
    expr: jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"} > 0.85
    for: 3m
    labels:
      severity: warning
    annotations:
      summary: "JVM heap > 85% ({{ $labels.job }})"
```

### 4.3) `ops/alertmanager/alertmanager.yml`
```yaml
route:
  receiver: 'default'
  group_by: ['alertname','job']
  group_wait: 10s
  group_interval: 1m
  repeat_interval: 3h
  routes:
    - matchers:
        - severity="critical"
      receiver: 'slack'

receivers:
  - name: 'default'
    email_configs:
      - to: ${ALERT_EMAIL_TO}
        from: alertmanager@microshop.local
        smarthost: maildev:1025
        require_tls: false

  - name: 'slack'
    slack_configs:
      - send_resolved: true
        api_url: ${SLACK_WEBHOOK_URL}
        channel: '#alerts'          # có thể để trống nếu webhook đã gắn kênh
        title: '{{ .CommonAnnotations.summary }}'
        text: >-
          *Alert:* {{ .CommonLabels.alertname }}
          *Severity:* {{ .CommonLabels.severity }}
          *Details:* {{ range .Alerts }} - {{ .Annotations.description }} {{ end }}
```

### 4.4) Grafana provisioning

`ops/grafana/provisioning/datasources/datasource.yml`
```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
```

`ops/grafana/provisioning/dashboards/dashboards.yml`
```yaml
apiVersion: 1
providers:
  - name: 'microshop-dashboards'
    orgId: 1
    folder: ''
    type: file
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
```

> Bạn có thể dùng dashboard JSON “Spring Boot Micrometer” (export từ Grafana Marketplace) lưu vào `ops/grafana/dashboards/spring-micrometer.json`.

---

## 5) Luồng dev & kiểm thử local

### 5.1) Chạy dev
```bash
cd ops
cp ../.env.example ../.env   # sửa giá trị trong .env
docker compose -f docker-compose.dev.yml up -d --build
```

- API:
    - Product: `http://localhost:8081/api/products`
    - Order:   `http://localhost:8082/api/orders`
- Quan trắc:
    - Prometheus: `http://localhost:9090/`
    - Alertmanager: `http://localhost:9093/`
    - Grafana: `http://localhost:3000/` (admin/admin)
    - Maildev UI: `http://localhost:1080/`

> Đảm bảo hai service expose `/actuator/health` và `/actuator/prometheus`.

### 5.2) Kiểm thử cảnh báo
- Tạm dừng `product-service` để xem **InstanceDown** alert → Alertmanager → Slack + Maildev.
- Gửi vài request lỗi (500) để kích hoạt **HighErrorRate**.

---

## 6) Kiểm thử cluster tại local bằng Docker Swarm

### 6.1) Tạo stack file `ops/docker-stack.local.yml`
```yaml
version: "3.9"

networks:
  overlay:
    driver: overlay

volumes:
  pgdata: {}
  mongodata: {}
  grafana: {}

configs:
  prometheus_yml:
    file: ./prometheus/prometheus.yml
  alerts_yml:
    file: ./prometheus/alerts.yml
  alertmanager_yml:
    file: ./alertmanager/alertmanager.yml
  grafana_ds_yml:
    file: ./grafana/provisioning/datasources/datasource.yml
  grafana_dash_yml:
    file: ./grafana/provisioning/dashboards/dashboards.yml

services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks: [overlay]
    deploy:
      replicas: 1

  mongo:
    image: mongo:6
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_INITDB_ROOT_USERNAME}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD}
    volumes:
      - mongodata:/data/db
    networks: [overlay]
    deploy:
      replicas: 1

  product-service:
    image: microshop/product-service:latest   # push image trước (xem CI/CD)
    environment:
      SPRING_APP_NAME: product-service
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports: [ "8081:8080" ]
    networks: [overlay]
    depends_on: [postgres]
    deploy:
      replicas: 2
      restart_policy: { condition: on-failure }

  order-service:
    image: microshop/order-service:latest
    environment:
      SPRING_APP_NAME: order-service
      MONGO_HOST: mongo
      MONGO_PORT: 27017
      MONGO_DB: ${MONGO_DB}
      MONGO_USER: ${MONGO_INITDB_ROOT_USERNAME}
      MONGO_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD}
    ports: [ "8082:8080" ]
    networks: [overlay]
    depends_on: [mongo]
    deploy:
      replicas: 2
      restart_policy: { condition: on-failure }

  prometheus:
    image: prom/prometheus:v2.55.0
    configs:
      - source: prometheus_yml
        target: /etc/prometheus/prometheus.yml
      - source: alerts_yml
        target: /etc/prometheus/alerts.yml
    ports: [ "9090:9090" ]
    networks: [overlay]
    deploy: { replicas: 1 }

  alertmanager:
    image: prom/alertmanager:v0.27.0
    configs:
      - source: alertmanager_yml
        target: /etc/alertmanager/alertmanager.yml
    environment:
      SLACK_WEBHOOK_URL: ${SLACK_WEBHOOK_URL}
      ALERT_EMAIL_TO: ${ALERT_EMAIL_TO}
    ports: [ "9093:9093" ]
    networks: [overlay]
    deploy: { replicas: 1 }

  grafana:
    image: grafana/grafana:11.1.0
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin
    volumes:
      - grafana:/var/lib/grafana
      - ./grafana/dashboards:/var/lib/grafana/dashboards
    configs:
      - source: grafana_ds_yml
        target: /etc/grafana/provisioning/datasources/datasource.yml
      - source: grafana_dash_yml
        target: /etc/grafana/provisioning/dashboards/dashboards.yml
    ports: [ "3000:3000" ]
    networks: [overlay]
    deploy: { replicas: 1 }
```

### 6.2) Chạy Swarm
```bash
docker swarm init
# build & push image trước (local registry hoặc Docker Hub)
docker build -t microshop/product-service:latest -f services/product-service/product.order.Dockerfile .
docker build -t microshop/order-service:latest -f services/order-service/product.order.Dockerfile .
docker tag microshop/product-service:latest <your-dockerhub>/product-service:latest
docker tag microshop/order-service:latest <your-dockerhub>/order-service:latest
docker push <your-dockerhub>/product-service:latest
docker push <your-dockerhub>/order-service:latest

cd ops
docker stack deploy -c docker-stack.local.yml microshop
docker stack services microshop
```

---

## 7) CI/CD (gợi ý GitHub Actions → Docker Hub/ECR)

`.github/workflows/build.yml` (rút gọn)
```yaml
name: Build & Push

on: [push]

jobs:
  product:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          file: services/product-service/product.order.Dockerfile
          tags: yourrepo/product-service:latest
          push: true

  order:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          file: services/order-service/product.order.Dockerfile
          tags: yourrepo/order-service:latest
          push: true
```

---

## 8) Lên AWS (sau khi ổn định local)

### 8.1) Lựa chọn hạ tầng
- **Phù hợp nhất (đơn giản, tương thích Swarm):**  
  Swarm cluster trên **EC2** (3 manager + 2 worker), reverse proxy (ALB → managers), **RDS PostgreSQL** (Multi-AZ), **MongoDB Atlas** (M10+).
  > *Lưu ý:* Amazon DocumentDB không 100% tương thích MongoDB; Atlas an toàn hơn.
- **Thay thế:** ECS/Fargate (dịch stack sang ECS task definitions), nhưng khác Swarm.

### 8.2) Các bước chính (EC2 + Swarm)
1. **Networking**: VPC / Private + Public subnets, Security Groups mở cổng:
    - 80/443 (ALB), 9090/9093/3000 (giới hạn IP admin), 5432 (từ service → RDS), 27017 (từ service → Atlas private peering / public IP + IP allowlist), 22 (SSH hạn chế IP).
2. **RDS PostgreSQL**: tạo DB `productdb`, user/password; lưu vào **AWS Secrets Manager**.
3. **MongoDB Atlas**: tạo Cluster, DB `orderdb`, user; set **Network Access** (VPC peering hoặc allowlist IP EC2).
4. **EC2**: tạo Auto Scaling Group:
    - Cài Docker & init Swarm (`docker swarm init --advertise-addr <manager-ip>`).
    - Join workers bằng token `docker swarm join ...`.
5. **Registry**: ECR hoặc Docker Hub. Push image 2 service.
6. **Secrets & configs**: dùng **Docker Swarm secrets/configs** hoặc export env từ **SSM Parameter Store/Secrets Manager**.
7. **Triển khai**: upload `docker-stack.local.yml` biến đổi thành `docker-stack.aws.yml`:
    - Thay DB hosts bằng RDS endpoint & Atlas connection string.
    - Bỏ `ports` public nếu dùng **Traefik/Nginx**/ALB route; hoặc giữ cổng nội bộ, ALB target → host:port.
    - Cấu hình Alertmanager dùng Slack webhook thật & SES (nếu muốn), còn test có thể giữ Maildev (private).
    - `docker stack deploy -c docker-stack.aws.yml microshop`.
8. **Giám sát**:
    - Hạn chế truy cập Grafana/Prometheus qua VPN/Bastion hoặc Auth proxy.
    - Import dashboards & tạo alert rules phù hợp traffic thực.

---

## 9) Checklist chất lượng & vận hành

- **Health/Liveness/Readiness**: Actuator probes bật `management.endpoint.health.probes.enabled=true`.
- **Observability**:
    - Log JSON (nếu cần ELK/CloudWatch sau này).
    - Micrometer tags: `application`, `instance`, `env`.
- **DB migration**:
    - Postgres: thêm **Flyway** vào `product-service` (khuyên dùng).
- **API hợp đồng**:
    - Springdoc OpenAPI (`springdoc-openapi-starter-webmvc-ui`) để tự sinh Swagger UI.
- **Test**:
    - Unit + Slice test cho domain (không phụ thuộc framework).
    - Integration test với Testcontainers cho Postgres/Mongo (khi chạy ngoài Docker).
- **Security**:
    - Không commit `.env`; dùng secrets trong CI/CD.
    - Restrict network giữa services (overlay network riêng).
- **Scaling**:
    - Swarm `deploy.replicas` ≥ 2 cho service; sticky session nếu cần.
- **Backups**:
    - RDS automated backups; Mongo Atlas backup snapshot.

---

## 10) Lời gọi API mẫu (để sanity check)

- `POST /api/products` → tạo sản phẩm
- `GET  /api/products`
- `POST /api/orders` body:
```json
{
  "customerId": "c1",
  "items": [{"productId": 1, "qty": 2}]
}
```
- `GET /actuator/health`
- `GET /actuator/prometheus`
