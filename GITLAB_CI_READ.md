# .gitlab-ci.yml — Monorepo: order & product
stages:
- test
- build
- push

# Thiết lập dùng lại cho các job cần Docker
.docker:
image: docker:28
services:
- name: docker:24-dind
variables:
DOCKER_TLS_CERTDIR: ""        # đơn giản hoá auth với dind
DOCKER_DRIVER: overlay2
before_script:
- docker info
- docker login -u "$CI_REGISTRY_USER" -p "$CI_REGISTRY_PASSWORD" $CI_REGISTRY

# Biến tiện dụng cho tên image
variables:
ORDER_IMAGE: $CI_REGISTRY_IMAGE/order
PRODUCT_IMAGE: $CI_REGISTRY_IMAGE/product

# =========================
# 1) TEST
# =========================
test:order:
stage: test
image: alpine:3.20
rules:
- changes:
- order/**        # chỉ chạy khi thư mục order thay đổi
script:
# Thay bằng lệnh test thực tế (npm/maven/pytest...)
- echo "Running tests for order..."
- echo "✅ Tests order passed"

test:product:
stage: test
image: alpine:3.20
rules:
- changes:
- product/**
script:
- echo "Running tests for product..."
- echo "✅ Tests product passed"

# =========================
# 2) BUILD IMAGE
# =========================
build:order:
stage: build
extends: .docker
needs: ["test:order"]
rules:
- changes:
- order/**
exists:
- order/Dockerfile
script:
- docker build --pull -t "$ORDER_IMAGE:$CI_COMMIT_REF_SLUG" -f order/Dockerfile order
- |
if [[ "$CI_COMMIT_BRANCH" == "$CI_DEFAULT_BRANCH" ]]; then
docker tag "$ORDER_IMAGE:$CI_COMMIT_REF_SLUG" "$ORDER_IMAGE:latest"
fi

build:product:
stage: build
extends: .docker
needs: ["test:product"]
rules:
- changes:
- product/**
exists:
- product/Dockerfile
script:
- docker build --pull -t "$PRODUCT_IMAGE:$CI_COMMIT_REF_SLUG" -f product/Dockerfile product
- |
if [[ "$CI_COMMIT_BRANCH" == "$CI_DEFAULT_BRANCH" ]]; then
docker tag "$PRODUCT_IMAGE:$CI_COMMIT_REF_SLUG" "$PRODUCT_IMAGE:latest"
fi

# =========================
# 3) PUSH IMAGE
# =========================
push:order:
stage: push
extends: .docker
needs: ["build:order"]
rules:
- changes:
- order/**
exists:
- order/Dockerfile
script:
- docker push "$ORDER_IMAGE:$CI_COMMIT_REF_SLUG"
- |
if [[ "$CI_COMMIT_BRANCH" == "$CI_DEFAULT_BRANCH" ]]; then
docker push "$ORDER_IMAGE:latest"
fi

push:product:
stage: push
extends: .docker
needs: ["build:product"]
rules:
- changes:
- product/**
exists:
- product/Dockerfile
script:
- docker push "$PRODUCT_IMAGE:$CI_COMMIT_REF_SLUG"
- |
if [[ "$CI_COMMIT_BRANCH" == "$CI_DEFAULT_BRANCH" ]]; then
docker push "$PRODUCT_IMAGE:latest"
fi
