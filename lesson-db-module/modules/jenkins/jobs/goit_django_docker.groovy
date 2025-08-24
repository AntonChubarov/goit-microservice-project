pipelineJob("goit-django-docker") {
  definition {
    cpsScm {
      scm {
        git {
          remote {
            url("https://github.com/AntonChubarov/goit-microservice-project.git")
            credentials("github-token")
          }
          branches("*/lesson-8-9")
        }
      }
      scriptPath("lesson-8-9/Jenkinsfile")
    }
  }
}
