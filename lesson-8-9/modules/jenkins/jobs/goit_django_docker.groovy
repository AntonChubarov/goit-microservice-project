pipelineJob("goit-django-docker") {
  definition {
    cpsScm {
      scm {
        git {
          remote {
            url("${github_repo_url}")
            credentials("github-token")
          }
          branches("*/lesson-8-9")
        }
      }
      // Jenkinsfile lives under lesson-8-9/
      scriptPath("lesson-8-9/Jenkinsfile")
    }
  }
}
