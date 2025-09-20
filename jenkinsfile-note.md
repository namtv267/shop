pipeline {                                  // Gốc của Declarative Pipeline
  agent {                                   // Chọn nơi chạy
    any | none | label('linux') | node('x') |
    docker { image 'img:tag'; args ''; reuseNode true } |
    dockerfile { filename 'Dockerfile'; dir '.'; additionalBuildArgs '--build-arg FOO=bar' } |
    kubernetes { yaml '...'; defaultContainer 'jnlp' }     // (cần K8s plugin)
  }

  options {                                 // Chính sách chạy pipeline
    buildDiscarder(logRotator(numToKeepStr: '20', daysToKeepStr: '30'))
    disableConcurrentBuilds()               // Không cho chạy song song job này
    timeout(time: 30, unit: 'MINUTES')
    retry(2)                                // Tự thử lại pipeline khi fail (ngoài steps)
    timestamps()                            // Thêm timestamp vào log
    ansiColor('xterm')                      // Màu log (cần AnsiColor plugin)
    skipDefaultCheckout(true)               // Bỏ checkout scm tự động
    checkoutToSubdirectory('src')           // Checkout vào thư mục con
    overrideIndexTriggers(true)             // Ghi đè trigger index (MBP)
    skipStagesAfterUnstable()               // Dừng các stage sau khi UNSTABLE
    preserveStashes(buildCount: 5)
    parallelsAlwaysFailFast()               // Một nhánh song song fail -> fail nhanh
    quietPeriod(10)                         // Trì hoãn N giây trước khi bắt đầu
    rateLimitBuilds(throttle: [count: 1, durationName: 'hour', userBoost: true])
  }

  environment {                             // Biến môi trường dùng chung
    KEY = 'value'
    SECRET = credentials('cred-id')         // Bind credential -> biến env
  }

  parameters {                              // Tham số input khi bấm Build
    string(name: 'APP_ENV', defaultValue: 'dev', description: 'Môi trường')
    booleanParam(name: 'RUN_TESTS', defaultValue: true, description: 'Chạy test?')
    choice(name: 'REGION', choices: ['us','eu'], description: 'Khu vực')
    text(name: 'NOTES', defaultValue: '', description: 'Ghi chú')
    password(name: 'PASS', defaultValue: '', description: 'Ví dụ (ít dùng)')
    // file(name: 'UPLOAD')                  // (cần bật file param)
  }

  tools {                                   // Khai báo tools Jenkins quản lý
    jdk 'jdk17'
    maven 'mvn3'
    gradle 'gradle8'
    nodejs 'node18'                         // (cần NodeJS plugin)
  }

  triggers {                                // Cách kích hoạt pipeline tự động
    cron('H 2 * * *')                       // Lịch: ~02:00 hằng ngày (H = hash)
    pollSCM('H/15 * * * *')                 // Mỗi 15' kiểm tra SCM, có thay đổi thì chạy
    upstream(job: 'order-service', threshold: 'SUCCESS') // Upstream build xong -> chạy
  }

  stages {                                  // Danh sách công việc chính
    stage('Init') {                         // Một stage
      agent any | none | docker { ... }     // (Tùy chọn) override agent cho stage
      options { timeout(time: 10, unit: 'MINUTES') } // (Tùy chọn) policy cấp stage
      tools   { jdk 'jdk17' }               // (Tùy chọn) tools cấp stage
      environment { STAGE_VAR = 'abc' }     // (Tùy chọn) env cấp stage
      when {                                // (Tùy chọn) điều kiện chạy stage
        branch 'main'                       // Chỉ chạy trên nhánh main
        anyOf { branch 'dev'; branch 'stg' }
        allOf { not { branch 'hotfix' }; expression { return env.BUILD_NUMBER != null } }
        changeset "**/*.java"               // Chỉ chạy nếu có file khớp thay đổi
        tag "v*"                            // Khi build tag
        buildingTag() | changeRequest()     // Tag hoặc PR
        equals expected: 'prod', actual: env.APP_ENV
        beforeAgent true                    // Đánh giá điều kiện trước khi alloc agent
      }
      input {                               // (Tùy chọn) chờ phê duyệt thủ công
        message 'Deploy PROD?'; ok 'Proceed'; submitter 'ops,lead'
      }
      stages {                              // (Tùy chọn) nhóm con — hay dùng cho parallel
        stage('A') { steps { echo 'A' } }
      }
      steps {                               // Các bước thực thi bên trong stage
        echo "Hello"
        sh "printenv | sort"
        script {                            // Chạy Groovy Scripted khi cần linh hoạt
          def x = 1; echo "x=${x}"
        }
      }
      post {                                // Hậu xử lý cấp stage
        success { echo 'Stage OK' }
        failure { echo 'Stage FAIL' }
        always  { echo 'Stage DONE' }
      }
    }

    stage('Parallel Example') {
      parallel {                            // Chạy nhiều stage con song song
        stage('Unit Tests')   { steps { sh './gradlew test' } }
        stage('Lint')         { steps { sh './gradlew check' } }
        stage('Docker Build') { steps { sh 'docker build -t app:ci .' } }
      }
    }

    stage('Matrix Example') {               // Chạy tổ hợp biến môi trường/axis
      matrix {
        axes {
          axis { name 'OS';   values 'linux', 'windows' }
          axis { name 'JDK';  values '17', '21' }
        }
        excludes {                          // Loại trừ tổ hợp nếu cần
          exclude { axis { name 'OS'; value 'windows' }; axis { name 'JDK'; value '21' } }
        }
        stages {
          stage('Build') { steps { echo "Build on ${OS} JDK ${JDK}" } }
        }
        post {
          always { echo "Matrix combo done" }
        }
      }
    }
  }

  post {                                    // Hậu xử lý cấp pipeline
    always   { echo 'Pipeline kết thúc (always)' }
    success  { echo '✅ Thành công' }
    failure  { echo '❌ Thất bại' }
    unstable { echo '⚠️ Unstable' }
    aborted  { echo '⏹️ Bị hủy' }
    changed  { echo 'Kết quả thay đổi so với build trước' }
    fixed    { echo 'Lỗi đã được sửa (trước fail/unstable, giờ success)' }
    regression { echo 'Từ success chuyển sang fail/unstable' }
    cleanup  { echo 'Dọn dẹp sau cùng (luôn chạy cuối)' }
  }
}
