pipeline {
    agent any

    options {
        timestamps()
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

        stage('Docker Build and Deploy') {
            steps {
                bat 'docker compose up -d --build'
            }
        }

        stage('Check Containers') {
            steps {
                bat 'docker ps'
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
    }
}