pipelineJob("goit-django-docker") {
  definition {
    cpsScm {
      scm {
        git {
          remote {
            url("https://github.com/AntonChubarov/goit-microservice-project.git")
            credentials("github-token")
          }
          branches("*/final-project")
        }
      }
      scriptPath("final-project/Jenkinsfile")
    }
  }
}
