pipelineJob("goit-django-docker") {
  definition {
    cpsScm {
      scm {
        git {
          remote {
            url("https://github.com/AntonChubarov/goit-microservice-project.git")
            credentials("github-token")
          }
          branches("*/lesson-db-module")
        }
      }
      scriptPath("lesson-db-module/Jenkinsfile")
    }
  }
}
