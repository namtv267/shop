# 1) Sơ đồ cây Declarative Pipeline (tổng quan)
```groovy
pipeline {                              // Gốc Jenkins Declarative Pipeline

  agent any | none | label('x') |       // Khai báo nơi chạy
        { docker { ... } } |            //   - Docker agent
        { dockerfile { ... } } |        //   - Build từ Dockerfile
        { kubernetes { ... } }          //   - Pod template (k8s plugin)

  options {                              // Chính sách & tiện ích runtime
    timestamps()                         //   Thêm timestamp vào log
    disableConcurrentBuilds()            //   Chặn chạy song song cùng job
    skipDefaultCheckout()                //   Bỏ checkout scm tự động
    buildDiscarder(logRotator(...))      //   Giữ log/artifact theo TTL/số lượng
    timeout(time: 30, unit: 'MINUTES')   //   Giới hạn thời gian toàn pipeline
    ansiColor('xterm')                   //   Màu sắc log (cần plugin)
    preserveStashes(buildCount: 5)       //   Giữ stash cho build kế tiếp
    parallelsAlwaysFailFast()            //   Parallel fail nhanh khi 1 nhánh lỗi
    // ... (các option khác hỗ trợ bởi Jenkins core/plugin)
  }

  triggers {                              // Cách khởi chạy pipeline
    cron('H H * * 1-5')                   //   Lịch CRON (ví dụ ngày làm việc)
    pollSCM('H/5 * * * *')                //   Jenkins tự “hỏi” SCM theo lịch
    upstream(job: 'seed', threshold: 'SUCCESS') // Chạy khi job khác xong
    // Lưu ý: Multibranch chủ yếu dùng webhook từ SCM
  }

  parameters {                            // Tham số khi Build with Parameters
    string(name: 'VERSION', defaultValue: '1.0.0', description: 'Tag version')
    booleanParam(name: 'RUN_TEST', defaultValue: true, description: 'Chạy test?')
    choice(name: 'ENV', choices: ['dev','staging','prod'], description: 'Môi trường')
    text(name: 'NOTES', defaultValue: '', description: 'Ghi chú phát hành')
    password(name: 'SECRET', defaultValue: '', description: 'Mật khẩu tạm') // (Plugin)
    credentials(name: 'DOCKERHUB', credentialType: 'com.cloudbees.plugins.credentials.common.StandardUsernamePasswordCredentials', description: 'Cred ID') // (Plugin)
    // ... (các loại tham số khác do plugin cung cấp)
  }

  environment {                           // Biến môi trường chung
    APP_NAME = 'demo-app'
    REGISTRY = 'yourorg/demo'
    // ENV var có thể đọc từ credentials:
    // MY_TOKEN = credentials('my-secret-id')
  }

  tools {                                 // Khai báo tool do Jenkins quản lý
    // jdk 'JDK17'
    // maven 'Maven3'
    // nodejs 'Node_18_LTS'
  }

  stages {                                // Tập hợp các stage tuần tự (hoặc song song)
    stage('Checkout') {
      agent any | { docker { ... } }      // (Tùy chọn) override agent cho stage
      options { timeout(time: 10, unit: 'MINUTES') } // (Tùy chọn) option cấp stage
      tools { /* ... */ }                 // (Tùy chọn) tool cấp stage
      environment { /* ... */ }           // (Tùy chọn) env cấp stage
      when {                              // (Tùy chọn) điều kiện chạy stage
        branch 'main'                     //   Chỉ chạy khi nhánh = main
        // Hoặc: anyOf { branch 'main'; tag "v.*" }
        // Hoặc: expression { return params.RUN_TEST }
        // (xem khối WHEN chi tiết bên dưới)
      }
      steps {                             // Các bước thực thi (DSL “steps”)
        checkout scm                      //   Checkout repo mặc định
        sh 'echo "do something"'          //   Chạy shell (Linux/Mac)
        // bat 'dir'                      //   Chạy CMD (Windows)
        // powershell '...'              //   Chạy PowerShell
      }
      post {                              // Hậu xử lý cấp stage
        success { echo 'Stage OK' }
        failure { echo 'Stage FAIL' }
        always  { echo 'Stage Done' }
        unstable { echo 'Stage Unstable' }
        changed { echo 'Stage Changed' }
        aborted { echo 'Stage Aborted' }
        cleanup { cleanWs() }             //   Thường dùng dọn workspace
      }
    }

    stage('Parallel Example') {
      parallel {                          // Chạy nhiều nhánh song song
        stage('Lint') { steps { sh 'npm run lint' } }
        stage('Unit Test') { steps { sh 'npm test -- --ci' } }
        stage('Build') { steps { sh 'npm run build' } }
      }
    }

    stage('Matrix Example') {             // Ma trận kết hợp nhiều biến chạy song song
      matrix {
        axes {
          axis { name 'OS'; values 'linux', 'windows' }
          axis { name 'NODE'; values '16', '18' }
        }
        excludes {
          exclude { axis 'OS', 'windows'; axis 'NODE', '18' } // Bỏ tổ hợp
        }
        agent { label "${OS}" }           // Chọn agent theo trục
        environment { NODE_VERSION = "${NODE}" }
        stages {
          stage('Test') { steps { sh 'node -v && npm ci && npm test' } }
        }
        post { always { echo "Done ${OS}/${NODE}" } }
      }
    }

    stage('Manual Gate') {
      steps {
        input message: 'Duyệt để deploy?', ok: 'Tiếp tục' // Cửa kiểm duyệt thủ công
      }
    }

    stage('Deploy') {
      when { anyOf { branch 'main'; tag pattern: "v.*", comparator: "REGEXP" } }
      steps {
        echo "Deploying to ${params.ENV}"
        // sh 'helm upgrade ...'
      }
    }

    stage('Artifacts & Reports') {
      steps {
        junit 'reports/junit-*.xml'       // Thu thập báo cáo test JUnit
        archiveArtifacts artifacts: 'dist/**', fingerprint: true // Lưu artifact
        stash name: 'build-dist', includes: 'dist/**'  // Lưu tạm trong build
        // unstash 'build-dist'
      }
    }

    stage('Credentials & Docker') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'dockerhub-cred-id',
          usernameVariable: 'U', passwordVariable: 'P'
        )]) {
          sh 'echo "$P" | docker login -u "$U" --password-stdin'
        }
        sh '''
          docker build -t ${REGISTRY}:${env.BUILD_NUMBER} .
          docker push ${REGISTRY}:${env.BUILD_NUMBER}
        '''
      }
    }

    stage('Script Block (nâng cao)') {
      steps {
        script {                          // Chèn Groovy Scripted khi cần logic phức tạp
          def short = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
          currentBuild.displayName = "#${env.BUILD_NUMBER} ${short}"
        }
      }
    }
  }

  post {                                  // Hậu xử lý toàn pipeline
    always {
      echo 'Pipeline DONE'
      cleanWs(deleteDirs: true)
    }
    success { echo '✅ SUCCESS' }
    failure { echo '❌ FAILURE' }
    unstable { echo '⚠️ UNSTABLE' }
    aborted { echo '⏹️ ABORTED' }
    changed { echo "Trạng thái build đã thay đổi" }
    fixed { echo "Đã FIXED kể từ lần trước" }
    regression { echo "Bị REGRESSION so với lần trước" }
    unsuccessful { echo "Không thành công (FAIL/UNSTABLE/ABORTED)" }
    notBuilt { echo "Không build (skipped)" }
    cleanup { /* Nơi dọn dẹp bổ sung */ }
  }
}
```

# Khôi `when` (điều kiện chạy) - các toán tử thường dùng
```groovy
when {
  branch 'main'                               // Nhánh cụ thể
  buildingTag()                               // Build tag Git?
  tag pattern: "v\\d+\\.\\d+\\.\\d+", comparator: "REGEXP"  // Khớp tag
  environment name: 'ENV', value: 'prod'      // So khớp ENV var
  equals expected: 'prod', actual: params.ENV  // So sánh
  changeset "src/**"                           // Có thay đổi file trong path?
  changelog 'fix:'                             // Commit message chứa chuỗi
  changeRequest()                              // Pull/Merge Request build?
  expression { return params.RUN_TEST }        // Điều kiện Groovy tùy ý
  not { branch 'dev' }                         // Phủ định
  allOf { branch 'main'; environment name: 'ENV', value: 'staging' } // AND
  anyOf { branch 'main'; buildingTag() }       // OR

  beforeAgent true | false                     // Đánh giá when trước khi allocate agent
  beforeInput true | false                     // Đánh giá trước khi hiển thị input
}
```

# 3) Các steps (hay dùng nhất) theo nhóm

## SCM & Workspace
- checkout scm — checkout repo mặc định của job.
- checkout([$class: 'GitSCM', ...]) — checkout tuỳ biến.
- dir('path') { ... } — tạm chuyển thư mục làm việc.
- stash/unstash — lưu/khôi phục file tạm giữa stage/nhánh song song.

## Shell & Hệ điều hành
- sh 'cmd' (Linux/Mac), bat 'cmd' (Windows), powershell 'cmd' (Windows PS).
- tool 'name' — khai báo đường dẫn tool đã cài.

## Thời gian & Điều khiển luồng
- sleep time: 10, unit: 'SECONDS' — ngủ.
- timeout(time: 5, unit: 'MINUTES') { ... } — giới hạn thời gian block.
- retry(3) { ... } — thử lại N lần khi lỗi tạm.
- input message: '...', ok: 'Go' — dừng chờ duyệt tay.
- waitUntil { ... } — chờ điều kiện (Scripted step, dùng trong script {}).

## Báo cáo & Artifact
- junit 'reports/*.xml' — publish test results.
- archiveArtifacts artifacts: 'build/**', fingerprint: true — lưu artifact.
- publishHTML(...), cobertura(...), jacoco(...) — cần plugin tương ứng.

## Credentials & Env
- withCredentials([usernamePassword(...), string(...), file(...), sshUserPrivateKey(...)]) { ... }
- withEnv(["KEY=VALUE"]) { ... }
- credentials('id') trong environment {} — map thành biến.

## Thông báo
- emailext(...) — email (Email Ext plugin).
- slackSend(...) — Slack (Slack plugin).
- echo '...' — in ra log.
- error('message') — đánh fail ngay.
- warnError('msg') { ... } — nếu lỗi thì mark UNSTABLE, không fail cứng.
- catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') { ... } — bắt lỗi mềm.

## Docker (Docker Pipeline plugin)
- docker.image('node:18').inside { sh 'npm ci' } — chạy bước trong container.
- docker.build('repo/name:tag', '.') — build image.
- image.push('tag') — push tag.
- withDockerRegistry([credentialsId: 'id', url: '...']) { ... } — login registry.

## File I/O
- readFile 'path', writeFile file: 'path', text: '...'

## Groovy nâng cao
- script { ... } — mở “vùng Scripted” bên trong Declarative để dùng Groovy/step nâng cao (vd: currentBuild, manager, logic tùy ý).

# 4) Ghi chú nhanh (giúp tránh lỗi thực tế)

#### Multibranch Pipeline: dùng webhook từ SCM để trigger; cron OK; pollSCM thường hạn chế.

#### beforeAgent true trong when giúp không tốn thời gian cấp agent nếu điều kiện không đạt.

#### skipDefaultCheckout() + checkout scm ở stage đầu giúp bạn kiểm soát chính xác khi nào checkout.

#### parallelsAlwaysFailFast(): khi một nhánh song song fail, các nhánh khác dừng sớm — tiết kiệm tài nguyên.

#### preserveStashes(buildCount: N) hữu ích cho pipeline nhiều nhánh cần “cầm” artifact giữa các build liên tiếp.

#### Credentials: luôn qua withCredentials/credentials() — không in secret vào log.

#### script {} chỉ dùng khi cần; còn lại bám Declarative để dễ đọc và bắt lỗi sớm.