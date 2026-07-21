pipeline {
    agent any

    options {
        timestamps()

        // Jenkins가 자동 Checkout을 한 번 더 수행하는 것을 방지
        skipDefaultCheckout(true)

        // 동시에 두 번 빌드되어 Docker 컨테이너가 충돌하는 것을 방지
        disableConcurrentBuilds()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Check Environment') {
            steps {
                bat 'git --version'
                bat 'docker --version'
                bat 'docker compose version'
            }
        }

        stage('Prepare Environment') {
            steps {
                withCredentials([
                    file(
                        credentialsId: 'backend-env-file',
                        variable: 'BACKEND_ENV_FILE'
                    )
                ]) {
                    bat '''
                        @echo off

                        copy /Y "%BACKEND_ENV_FILE%" "backend\\.env" >nul

                        if not exist "backend\\.env" (
                            echo [ERROR] backend\\.env 파일 생성 실패
                            exit /b 1
                        )

                        echo [SUCCESS] backend\\.env 파일 준비 완료
                    '''
                }
            }
        }

        stage('Docker Build and Deploy') {
            steps {
                bat 'docker compose up -d --build --force-recreate'
            }
        }

        stage('Check Containers') {
            steps {
                bat 'docker ps'

                bat '''
                    docker exec no_snoring_backend python -c "import openai; print('OPENAI_VERSION=', openai.__version__)"
                '''

                bat '''
                    docker exec no_snoring_backend python -c "import os; print('KEY_SET=', bool(os.getenv('OPENAI_API_KEY'))); print('MODEL=', os.getenv('OPENAI_MODEL'))"
                '''
            }
        }
    }

    post {
        success {
            echo 'No_snoring_Great_sleeping Docker deploy success'
        }

        failure {
            echo 'No_snoring_Great_sleeping Docker deploy failed'
        }

        always {
            bat '''
                @echo off
                if exist "backend\\.env" (
                    del /F /Q "backend\\.env"
                    echo Jenkins workspace의 backend\\.env 파일 삭제 완료
                )
            '''
        }
    }
}