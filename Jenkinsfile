pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                echo 'Building...'
            }
        }
    }
    post {
        always {
            echo 'Always'
        }
    }
    post {
        always {
            echo 'Always'
        }
    }
    post {
        always {
            echo 'Always'
        }
    }
    post {
        always {
            echo 'Always'
        }
    }
    triggers {
        pollSCM('H/15 * * * *')
        upstream(job: 'order-service', threshold: 'SUCCESS')
        upstream(job: 'product-service', threshold: 'SUCCESS')
        upstream(job: 'oauth-oidc-service', threshold: 'SUCCESS')
        upstream(job: 'gateway-service', threshold: 'SUCCESS')
        upstream(job: 'auth-service', threshold: 'SUCCESS')
        upstream(job: 'user-service', threshold: 'SUCCESS')
    }
}